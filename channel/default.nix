# Arguments for the channel file in floxpkgs
{ name ? null
, topdir
# FIXME: Deprecation warning
, extraOverlays ? null
, dependencies ? null
, conflictResolution ? {}
}@chanArgs:

# Arguments for the command line
{ name ? null, debugVerbosity ? 0
, subsystemVerbosities ? {}
  # JSON string of a `<channelName> -> <projectName> -> <srcpath>` mapping. This overrides the sources used by these channels/projects to the given paths.
, sourceOverrideJson ? "{}", _return ? "outputs"
  # Used to detect whether this default.nix is a channel (by inspecting function arguments)
, _isFloxChannel ? throw "This argument isn't meant to be accessed"
  # When evaluating for an attributes _floxPath, passing a lower number in
  # this argument allows for still getting a result in case of failing
  # evaluation, at the expense of a potentially less precise result. The
  # highest number not giving evaluation failures should be used
, _floxPathDepth ? 2
  # Allow passing other arguments for nixpkgs pkgs/top-level/release-lib.nix compatibility
, ... }@args:
let topdir' = topdir;
in let


  # To prevent any accidental imports into the store, and to make sure it's a string, not a path
  topdir = toString topdir';

  nixpkgsArgs = removeAttrs args [
    "name"
    "debugVerbosity"
    "_return"
    "sourceOverrideJson"
    "_isFloxChannel"
  ];

  # We only import nixpkgs once with an overlay that adds all channels, which is
  # also used as a base set for all channels themselves
  pkgs = import <nixpkgs> nixpkgsArgs;
  inherit (pkgs) lib;

  utils = import ./utils { inherit lib; };

  trace = utils.traceWith {
    defaultVerbosity = debugVerbosity;
    inherit subsystemVerbosities;
  };

  # A list of { name; success | failure } entries, representing heuristics used
  # to determine the channel name, in the order of preference
  #
  # See https://github.com/flox/floxpkgs/blob/staging/docs/expl/name-inference.md
  # for an explanation of why this is done
  nameHeuristics = let
    f = name: value:
      let
        result = /*if value ? success then
          let
            # Find a channel mapping in NIX_PATH that matches the name
            # This is case-insensitive because GitHub usernames are as well
            found =
              lib.findFirst (e: lib.toLower e.name == lib.toLower value.success)
              null channelFloxpkgsList;
          in if found != null then {
            success = found.name;
          } else {
            success = lib.warn
              "Inferred channel name ${value.success} using heuristic ${name}, but no entry for this channel found in NIX_PATH"
              value.success;
          }
        else*/
          value;
      in result // { inherit name; };

    heuristics = lib.mapAttrs f {
      chanArgs = if chanArgs ? name then {
        success = chanArgs.name;
      } else {
        failure = ''No "name" defined in the floxpkgs default.nix'';
      };
      cmdArgs = if args ? name then {
        success = args.name;
      } else {
        failure = ''No "name" passed with `--argstr name <channel name>`'';
      };
      baseName = if dirOf topdir == builtins.storeDir then {
        failure = "topdir is in /nix/store, basename is nonsensical";
      } else if baseNameOf topdir != "floxpkgs" then {
        success = baseNameOf topdir;
      } else {
        failure = ''Directory name of topdir is just "floxpkgs"'';
      };
      gitConfig = utils.nameFromGit topdir;
      #nixPath = let
      #  matchingEntries = lib.filter (e: e.path == topdir) channelFloxpkgsList;
      #  matchingNames = lib.unique (map (e: e.name) matchingEntries);
      #in if lib.length matchingNames == 0 then {
      #  failure = "No entries in NIX_PATH match path ${topdir}";
      #} else if lib.length matchingNames == 1 then {
      #  success = lib.elemAt matchingNames 0;
      #} else {
      #  failure = "Multiple entries in NIX_PATH match path ${topdir}";
      #};
    };
    ordered = [
      heuristics.chanArgs
      heuristics.cmdArgs
      #heuristics.nixPath
      heuristics.baseName
      heuristics.gitConfig
    ];
  in ordered;

  # The warning to issue when no name heuristic was successful
  fallbackNameWarning = ''
    Channel name could not be inferred because all heuristics failed:
    ${lib.concatMapStringsSep "\n" (h: "- ${h.name}: ${h.failure}")
    nameHeuristics}
    Using channel name "_unknown" instead. Because of this, channels dependent on your channel won't use your local uncommitted changes, and you will get failures if attempting to use sources from this channel.
  '';

  # The name as determined by the first successful name heuristic
  name = let
    fallback = {
      name = "fallback";
      success = lib.warn fallbackNameWarning "_unknown";
    };
    firstSuccess = lib.findFirst (e: e ? success) fallback nameHeuristics;
  in trace "name" 2
    "Determined root channel name to be ${firstSuccess.success} with heuristic ${firstSuccess.name}"
  firstSuccess.success;

  closure =
    let
      root = {
        key = name;
        value = own;
      };

      getChannel = name:
        let
          path = builtins.tryEval (builtins.findFile builtins.nixPath name);
        in
        if ! path.success then throw "Channel \"${name}\" wasn't found in NIX_PATH"
        else import path.value {
          inherit name debugVerbosity subsystemVerbosities;
          _return = "own";
        };

      operator = entry: map (name:
        if name == "nixpkgs"
        then throw "Channel ${entry.key} has \"nixpkgs\" specified as a dependency, which is not necessary"
        else trace "closure" 2 "Channel ${entry.key} depends on ${name}" {
          key = name;
          value = getChannel name;
        }
      ) entry.value.dependencies;

      result = builtins.genericClosure {
        startSet = [ root ];
        operator = operator;
      };
    in trace "closure" 1 "Determining channel closure" result;

  dependencyGraph = pkgs.runCommandNoCC "floxpkgs-${name}-dependency-graph" {
    graph = ''
      digraph {
        "${name}" [shape=box];
      ${lib.concatMapStrings (entry:
        lib.concatMapStrings (dep:
          "  \"${entry.key}\" -> \"${dep}\";\n"
        ) entry.value.dependencies
      ) closure}}
    '';
    passAsFile = [ "graph" ];
    nativeBuildInputs = [ pkgs.graphviz ];
  } ''
    mkdir -p "$out"
    mv "$graphPath" "$out/graph.dot"
    dot -Tpng "$out/graph.dot" -Gdpi=250 -o "$out/graph.png"
    cat <<EOF > $out/view
    #!${pkgs.runtimeShell}
    export PATH=${lib.makeBinPath [ pkgs.xdot pkgs.graphviz ]}
    exec xdot $out/graph.dot
    EOF
    chmod +x $out/view
  '';

  rootChannel = name;

  pregenPath = toString (<nixpkgs-pregen> + "/package-sets.json");
  pregenResult = if builtins.pathExists pregenPath then
    trace "pregen" 1 "Reusing pregenerated ${pregenPath}"
    (lib.importJSON pregenPath)
  else
    lib.warn
    "Path ${pregenPath} doesn't exist, won't be able to use precomputed result, evaluation will be slow"
    (import ./package-sets.nix {
      inherit lib;
      pregenerate = true;
      nixpkgs = <nixpkgs>;
    });

  packageSets = import ./package-sets.nix {
    inherit lib pregenResult;
    pregenerate = false;
  };

  /*
  ## Package specifications

  A package specification is a structure containing all the necessary
  information of a package for it to be usable by a dependent channel.

  It contains these fields

  {
    # Whether this package should be deeply overridden. If true, this
    # causes it to be injected into nixpkgs via an overlay
    deep = <bool>;

    # Which channel (or nixpkgs), if any, this package is extended from. When the
    # same package attribute is used in the expression as an argument, this
    # is the channel it refers to
    extends = null | "nixpkgs" | <channel>;

    # The path to the package expression
    exprPath = <path>;
  }
  */

  own = import ./own.nix {
    inherit lib utils trace name packageSets;
    firstArgs = chanArgs;
    secondArgs = args;
  };

  /*
  Gives a package specification for each package in each channel.

  {
    <channel>.<packageSet>.<pname> = <package specification>;
  }
  */
  channelPackageSpecs = lib.listToAttrs (map (entry: {
    name = entry.key;
    # Gets the package specs of each channel, passing it the packageChannels
    # evaluated from the root channel to share work
    value = entry.value.packageSpecs packageChannels;
  }) closure);

  /*
  Lists all channels (including nixpkgs) that contain a given package

  This value is passed to all ownPackageSpecs functions in all channels for them to be
  able to efficiently decide the `extends` of all the channels packages.

  This is later also going to be used by the root channel to decide where to
  get packages from.

  {
    <packageSet>.<pname> = {
      # Only if nixpkgs contains this package
      nixpkgs = null;
      # For all the channels that contain this package
      <channel> = null;
    };
  }
  */
  packageChannels = lib.mapAttrs (setName: packageSet:
    let
      packages = lib.concatMap (channel:
        lib.mapAttrsToList (pname: value: {
          inherit pname;
          name = channel;
          value = null;
        }) channelPackageSpecs.${channel}.${setName}
      ) (lib.attrNames channelPackageSpecs);

      result = lib.mapAttrs (name: values:
        lib.listToAttrs values
        # Note that this relies on the fact that pkgs ? x == pkgs.pkgs ? x
        // lib.optionalAttrs (pkgs ? ${setName}.${name}) {
          nixpkgs = null;
        }
      ) (lib.groupBy (p: p.pname) packages);
    in result
  ) packageSets;

  packageRoots = lib.mapAttrs (setName: setValue:
    lib.mapAttrs (pname: channels:
      let
        existsInNixpkgs = channels ? nixpkgs;
        channelList = lib.attrNames (removeAttrs channels [ "nixpkgs" ]);
        split = lib.partition (channel: channelPackageSpecs.${channel}.${setName}.${pname}.deep) channelList;

        root = deep: entries:
          if entries == [] then {}
          else {
            channel =
              # Otherwise, if some channel overrides it, disallow that if the package doesn't exist in nixpkgs already
              if deep && ! existsInNixpkgs then throw "Can't deeply override attribute ${setName}.${pname} that doesn't exist in nixpkgs"
              # The root channel takes precedence
              else if lib.elem rootChannel entries then rootChannel
              else if conflictResolution ? ${setName}.${pname} then conflictResolution.${setName}.${pname} # TODO: Validate that this option exists
              # Only when we have a single entry and it doesn't exist in nixpkgs, we can have an automatic conflict-free resolution
              else if lib.length entries == 1 && (lib.head entries == "flox" || ! existsInNixpkgs) then lib.head entries
              else throw "conflictResolution needs to be provided for ${setName}.${pname} in channel ${rootChannel}. Options are ${toString entries + lib.optionalString existsInNixpkgs " nixpkgs"}";
          };

      in {
        deep = root true split.right;
        shallow = root false split.wrong;
      }
    ) setValue
  ) packageChannels;


  perImportingChannel = lib.mapAttrs (importingChannel: _:
    let
      outputs = lib.mapAttrs (ownChannel: _:
        utils.nestedListToAttrs (lib.concatMap (setName:
          lib.concatMap (version:
            let
              value = called.${ownChannel}.${setName}.${version};

              versionInfo = packageSets.${setName}.versions.${version};
              paths = [ versionInfo.canonicalPath ] ++ versionInfo.aliases;

              result = map (path: {
                inherit path value;
              }) paths;

            in lib.optionals (value != {}) result
          ) (lib.attrNames packageSets.${setName}.versions)
        ) (lib.attrNames packageRoots))
      ) channelPackageSpecs;

      pathsToModify = type: lib.concatMap (setName:
        lib.concatMap (version:
          let
            canonicalPath = packageSets.${setName}.versions.${version}.canonicalPath;

            overridingSet = lib.mapAttrs (pname: spec:
              called.${spec.${type}.channel}.${setName}.${version}.${pname}
            ) (lib.filterAttrs (pname: spec: spec.${type} != {}) packageRoots.${setName});

            canonical = {
              path = canonicalPath;
              mod = super:
                if type == "deep"
                then packageSets.${setName}.deepOverride super overridingSet
                else super // overridingSet;
            };

            aliases = map (alias: {
              path = alias;
              mod = super: lib.getAttrFromPath canonicalPath (if type == "deep" then myPkgs else basePkgs);
            }) packageSets.${setName}.versions.${version}.aliases;

          in [ canonical ] ++ aliases
        ) (lib.attrNames packageSets.${setName}.versions)
      ) (lib.attrNames packageRoots);

      deepPaths = pathsToModify "deep";
      shallowPaths = pathsToModify "shallow";

      myPkgs = pkgs.extend (self: utils.modifyPaths deepPaths);

      basePkgs = utils.modifyPaths shallowPaths myPkgs;

      baseScope = basePkgs // basePkgs.xorg;

      called = lib.mapAttrs (ownChannel:
        lib.mapAttrs (setName: packages:
          lib.mapAttrs (version: versionInfo:
            let
              deepAnchor = lib.getAttrFromPath versionInfo.canonicalPath pkgs;
              shallowAnchor = lib.getAttrFromPath versionInfo.canonicalPath myPkgs;
            in
            lib.mapAttrs (pname: spec:
              let
                superPackage =
                  if spec.extends == null then
                    throw "${pname} is accessed in ${spec.exprPath}, but is not defined because nixpkgs has no ${pname} attribute"
                  else if spec.extends == "nixpkgs" then
                    if spec.deep then deepAnchor.${pname} else shallowAnchor.${pname}
                  else if ! called ? ${spec.extends} then
                    throw "extends channel ${spec.extends} doesn't exist"
                  else if ! called.${spec.extends}.${setName}.${version} ? ${pname} then
                    throw "extends package ${pname} doesn't exist in channel ${spec.extends}"
                  else called.${spec.extends}.${setName}.${version}.${pname};

                packageSetScope = lib.getAttrFromPath versionInfo.canonicalPath perImportingChannel.${ownChannel}.baseScope // {
                  ${packageSets.${setName}.callScopeAttr} = packageSetScope;
                };

                baseScope' = perImportingChannel.${ownChannel}.baseScope
                  // lib.optionalAttrs (packageSets.${setName}.callScopeAttr != null) {
                    ${packageSets.${setName}.callScopeAttr} = packageSetScope;
                  };

                extraScope = lib.optionalAttrs (packageSets.${setName}.callScopeAttr != null) packageSetScope;

                # TODO: Probably more efficient to directly inspect function arguments and fill these entries out.
                # A callPackage abstraction that allows specifying multiple attribute sets might be nice
                createScope = isOwn:
                  let
                    channels =
                      let
                        original = lib.mapAttrs (channel: value:
                          let
                            x = lib.mapAttrs (pname:
                              lib.warn "Accessing channel.${name}.${pname} from ${spec.exprPath}. This is discouraged as it circumvents the conflict resolution mechanism. Add ${pname} to the argument list directly instead."
                            ) perImportingChannel.${ownChannel}.outputs.${channel};
                          in x // {
                            ${packageSets.${setName}.callScopeAttr} = lib.getAttrFromPath versionInfo.canonicalPath x;
                          }
                        ) channelPackageSpecs;
                      in original // lib.mapAttrs' (name: lib.nameValuePair (lib.toLower name)) original;

                    result =
                      baseScope' // extraScope // lib.optionalAttrs isOwn {
                        ${pname} = superPackage;
                      } // {
                        # These attributes are reserved
                        inherit channels;
                        meta = createMeta {
                          inherit trace channels ownChannel importingChannel scope ownScope;
                          exprPath = spec.exprPath;
                        };
                        flox = channels.flox;
                        callPackage = lib.callPackageWith scope;
                      };
                  in result;

                ownScope = createScope true;
                scope = createScope false;

                ownOutput = {
                  # Allows getting back to the file that was used with e.g. `nix-instantiate --eval -A foo._floxPath`
                  # Note that we let the callPackage result override this because builders
                  # like flox.importNix are able to provide a more accurate file location
                  _floxPath = spec.exprPath;
                  # If we're evaluating for a _floxPath, only let the result of an
                  # package call influence the _floxPath with a _floxPathDepth
                  # greater or equal to 1
                } // lib.optionalAttrs (_floxPathDepth >= 1)
                  (lib.callPackageWith ownScope spec.exprPath { });

              in ownOutput
            ) packages
          ) packageSets.${setName}.versions
        )
      ) channelPackageSpecs;
    in {
      inherit called baseScope basePkgs outputs;
      pkgs = myPkgs;
    }
  ) channelPackageSpecs;


  # FIXME: Custom callPackageWith that ensures default arguments aren't autopassed
  callPackageWith = lib.callPackageWith;

  createMeta = pkgs.callPackage ./meta.nix {
    sourceOverrides = builtins.fromJSON sourceOverrideJson;
    inherit utils callPackageWith;
    floxPathDepth = _floxPathDepth;
  };

  # Evaluate name early so that name inference warnings get displayed at the start, and not just once we depend on another channel
in builtins.seq name {
  outputs = perImportingChannel.${rootChannel}.outputs.${rootChannel} // {
    pkgs = perImportingChannel.${rootChannel}.pkgs;
  };
  inherit packageRoots;
  inherit channelPackageSpecs;
  inherit perImportingChannel;
  inherit own;
  inherit packageChannels;
  inherit packageSets;
  inherit dependencyGraph;
}.${_return}
