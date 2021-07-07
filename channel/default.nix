# Arguments for the channel file in floxpkgs
# FIXME: Deprecation warning for extraOverlays
firstArgs:

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
, ... }@secondArgs:
let

  nixpkgsArgs = removeAttrs secondArgs [
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

  name = import ./name.nix {
    inherit lib firstArgs secondArgs trace utils;
  };

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
    inherit firstArgs secondArgs lib utils trace name packageSets;
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
              else if firstArgs ? conflictResolution.${setName}.${pname} then firstArgs.conflictResolution.${setName}.${pname} # TODO: Validate that this option exists
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
            lib.mapAttrs (pname: spec:
              createPackage {
                inherit pkgs myPkgs versionInfo spec lib pname called setName;
                inherit version perImportingChannel ownChannel packageSets;
                inherit createMeta trace importingChannel name;
                inherit channelPackageSpecs _floxPathDepth;
              }
            ) packages
          ) packageSets.${setName}.versions
        )
      ) channelPackageSpecs;
    in {
      inherit called baseScope basePkgs outputs;
      pkgs = myPkgs;
    }
  ) channelPackageSpecs;

  createPackage = import ./package.nix;

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
