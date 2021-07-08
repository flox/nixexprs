# Arguments are described in ./default.nix
firstArgs:
secondArgs:
let

  floxPathDepth = secondArgs._floxPathDepth or 2;

  # We allow passing through of nixpkgs arguments, but we don't want all the
  # flox-specific arguments to be passed
  nixpkgsArgs = removeAttrs secondArgs [
    "name"
    "debugVerbosity"
    "subsystemVerbosities"
    "sourceOverrideJson"
    "_isRoot"
    "_fromRoot"
    "_isFloxChannel"
  ];

  originalPkgs = import <nixpkgs> nixpkgsArgs;

  inherit (originalPkgs) lib;

  utils = import ./utils { inherit lib; };

  trace = utils.traceWith {
    defaultVerbosity = secondArgs.debugVerbosity or 0;
    subsystemVerbosities = secondArgs.subsystemVerbosities or {};
  };

  packageSets =
    let
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

      result = import ./package-sets.nix {
        inherit lib pregenResult;
        pregenerate = false;
      };
    in result;

  rootChannelName = import ./name.nix {
    inherit lib firstArgs secondArgs trace utils;
  };

  # This is the result if we're not the root channel
  ownResult = import ./own.nix {
    inherit firstArgs lib utils trace packageSets packageChannels;
    channelName = rootChannelName;
  };

  channelClosure =
    let
      sanitizeResult = name: result: {
        dependencies = lib.unique (lib.subtractLists [ "nixpkgs" name ] (result.dependencies ++ [ "flox" ]));
        packageSpecs = result.packageSpecs;
      };

      root = {
        key = rootChannelName;
        value = sanitizeResult rootChannelName ownResult;
      };

      getChannel = origin: name:
        let
          path = builtins.tryEval (builtins.findFile builtins.nixPath name);
          imported = import path.value {
            _isRoot = false;
            _fromRoot = {
              channelName = name;
              inherit lib utils trace packageSets packageChannels;
            };
          };
        in
        if ! path.success then throw "Channel \"${name}\" as declared as a dependency in channel \"${origin}\" can't found in NIX_PATH"
        else sanitizeResult name imported;

      operator = entry: map (name:
        trace "closure" 2 "Channel ${entry.key} depends on ${name}" {
          key = name;
          value = getChannel entry.key name;
        }
      ) entry.value.dependencies;

      result = builtins.genericClosure {
        startSet = [ root ];
        operator = operator;
      };
    in trace "closure" 1 "Determining channel closure" result;

  dependencyGraph = originalPkgs.runCommandNoCC "floxpkgs-${rootChannelName}-dependency-graph" {
    graph = ''
      digraph {
        "${rootChannelName}" [shape=box];
      ${lib.concatMapStrings (entry:
        lib.concatMapStrings (dep:
          "  \"${entry.key}\" -> \"${dep}\";\n"
        ) entry.value.dependencies
      ) channelClosure}}
    '';
    passAsFile = [ "graph" ];
    nativeBuildInputs = [ originalPkgs.graphviz ];
  } ''
    mkdir -p "$out"
    mv "$graphPath" "$out/graph.dot"
    dot -Tpng "$out/graph.dot" -Gdpi=250 -o "$out/graph.png"
    cat <<EOF > $out/view
    #!${originalPkgs.runtimeShell}
    export PATH=${lib.makeBinPath [ originalPkgs.xdot originalPkgs.graphviz ]}
    exec xdot $out/graph.dot
    EOF
    chmod +x $out/view
  '';

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


  /*
  Gives a package specification for each package in each channel.

  {
    <channel>.<packageSet>.<pname> = <package specification>;
  }
  */
  channelPackageSpecs = lib.listToAttrs (map (entry: {
    name = entry.key;
    value = entry.value.packageSpecs;
  }) channelClosure);

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
        // lib.optionalAttrs (originalPkgs ? ${setName}.${name}) {
          nixpkgs = null;
        }
      ) (lib.groupBy (p: p.pname) packages);
    in result
  ) packageSets;

  /*
  Gives a mapping from package to the channel it should come from, for both
  deep and shallow packages. Absence of a package is indicated by a `{}`,
  which is done in order to allow knowing whether it exists without having
  to know where it comes from. Not doing this slows down things considerably

  {
    <packageSet>.<pname> = {
      deep = {} | { channel = <channel>; };
      shallow = {} | { channel = <channel>; };
    };
  }
  */
  packageRoots = lib.mapAttrs (setName:
    lib.mapAttrs (pname: channels:
      let
        existsInNixpkgs = channels ? nixpkgs;

        # All the channels that define this package
        channelList = lib.attrNames (removeAttrs channels [ "nixpkgs" ]);

        # Split the channels into deep (.right) and non-deep (.wrong)
        split = lib.partition (channel: channelPackageSpecs.${channel}.${setName}.${pname}.deep) channelList;

        root = deep: entries:
          if entries == [] then {}
          else {
            channel =
              let
                options =
                  lib.optionalString existsInNixpkgs ''
                    conflictResolution.${lib.strings.escapeNixIdentifier setName}.${lib.strings.escapeNixIdentifier pname} = "nixpkgs";
                  ''
                  + lib.concatMapStrings (entry: ''
                    conflictResolution.${lib.strings.escapeNixIdentifier setName}.${lib.strings.escapeNixIdentifier pname} = "${entry}";
                  '') entries;

                resolution = firstArgs.conflictResolution.${setName}.${pname};
                invalidResolution = reason: throw
                  ("The conflict resolution for package \"${setName}.${pname}\" "
                  + "is set to \"${resolution}\", which is not a valid option "
                  + "because ${reason}. Change the conflict resolution for this "
                  + "package in ${toString firstArgs.topdir}/default.nix to be "
                  + "one of the following lines instead:\n${options}");
              in
              # We don't allow deep overrides for packages that don't exist in
              # nixpkgs already, because doing so would allow channels we
              # depend on to change nixpkgs behavior without the user having
              # to confirm it. This works by means of detecting _whether_
              # package attributes are there or not, without evaluating them,
              # which could allow a vulnerability in which upstream nixpkgs is
              # injected with some code that only triggers when a certain
              # attribute is there
              if deep && ! existsInNixpkgs then throw
                ("The package \"${setName}.${pname}\" in channel "
                + "\"${lib.head entries}\" is specified as `deep-override`-ing, "
                + "but this package doesn't exist in nixpkgs. Only packages "
                + "that exist in nixpkgs can be deeply overridden.")

              # If the root channel specifies this package, that takes precedence
              # This allows the root channel to override any attribute of any
              # other channel, without the user having to confirm this
              else if lib.elem rootChannelName entries then
                rootChannelName

              # If a conflict resolution has been provided for this package,
              # use it, after ensuring it's a valid option
              else if firstArgs ? conflictResolution.${setName}.${pname} then
                if resolution == "nixpkgs" then
                  if existsInNixpkgs then resolution
                  else invalidResolution "nixpkgs doesn't have this package"
                else if ! channelPackageSpecs ? ${resolution} then
                  invalidResolution "the channel \"${resolution}\" doesn't exist"
                else if lib.elem resolution entries then resolution
                else
                  invalidResolution "the channel \"${resolution}\" doesn't have this package"

              # If no conflict resolution has provided, but we only have a
              # single entry anyways, we can use that. However, if the
              # attribute also exists in nixpkgs, we essentially have two
              # entries then. We only allow this if the _flox_ channel is the
              # one channel, since we trust ourselves to override nixpkgs
              # attributes correctly
              else if lib.length entries == 1
                && (existsInNixpkgs -> lib.head entries == "flox") then
                lib.head entries

              # Otherwise we throw an error that the conflict needs to be
              # resolved manually
              else throw
                ("The package \"${setName}.${pname}\" is declared multiple "
                + "times ${lib.optionalString deep "as `deep-override`-ing "}"
                + "in channels ${lib.concatMapStringsSep ", "
                  lib.strings.escapeNixIdentifier entries}"
                + "${lib.optionalString existsInNixpkgs " and nixpkgs itself"}. "
                + "This conflict needs to be resolved by adding one of the "
                + "following lines to the passed attribute set in "
                + "${toString firstArgs.topdir}/default.nix:\n${options}");
          };

      in {
        deep = root true split.right;
        shallow = root false split.wrong;
      }
    )
  ) packageChannels;

  createMeta = originalPkgs.callPackage ./meta.nix {
    sourceOverrides =
      if secondArgs ? sourceOverrideJson
      then builtins.fromJSON secondArgs.sourceOverrideJson
      else {};
    inherit utils trace floxPathDepth;
  };

  perImportingChannel = lib.mapAttrs (importingChannel: _: trace.withContext "importingChannel" importingChannel (trace:
    let
      pathsToModify = type: trace.withContext "pathsToModifyType" type (trace:
        lib.concatMap (setName: trace.withContext "packageSet" setName (trace:
          lib.concatMap (version: trace.withContext "version" version (trace:
            let
              canonicalPath = packageSets.${setName}.versions.${version}.canonicalPath;

              existingRoots = lib.filterAttrs (pname: spec:
                spec.${type} != {}
              ) packageRoots.${setName};

              canonical = {
                path = canonicalPath;
                mod = super:
                  let
                    overridingSet = lib.mapAttrs (pname: spec:
                      if spec.${type}.channel == "nixpkgs" then super.${pname}
                      else channelPackages.${spec.${type}.channel}.perPackageSet.${setName}.${version}.${pname}
                    ) existingRoots;
                    message = "Injecting attributes into path ${trace.showValue canonicalPath}: ${trace.showValue (lib.attrNames overridingSet)}";
                    overridingSet' = trace "pathsToModify" 2 message overridingSet;
                    result =
                      if overridingSet == {} then super
                      else
                        if type == "deep"
                        then packageSets.${setName}.deepOverride super overridingSet
                        else super // overridingSet;
                  in result;
              };

              aliases = map (alias: {
                path = alias;
                mod = super:
                  trace "pathsToModify" 3 "Pointing alias ${trace.showValue alias} to ${trace.showValue canonicalPath}"
                  (lib.getAttrFromPath canonicalPath (if type == "deep" then overlaidPkgs else finalPkgs));
              }) packageSets.${setName}.versions.${version}.aliases;

            in [ canonical ] ++ aliases
          )) (lib.attrNames packageSets.${setName}.versions))
        ) (lib.attrNames packageRoots));

      overlaidPkgs = originalPkgs.extend (self: utils.modifyPaths (pathsToModify "deep"));

      finalPkgs = utils.modifyPaths (pathsToModify "shallow") overlaidPkgs;

      channelPackages = lib.mapAttrs (ownChannel: ownChannelSpecs: trace.withContext "channel" ownChannel (trace:
        import ./channel.nix {
          inherit lib utils trace packageSets originalPkgs floxPathDepth;
          inherit ownChannel ownChannelSpecs overlaidPkgs finalPkgs;
          dependencySet = perImportingChannel.${ownChannel}.forDependents;
          createMeta = createMeta importingChannel;
        }
      )) channelPackageSpecs;
    in {
      forDependents = {
        baseScope = finalPkgs // finalPkgs.xorg;
        inherit channelPackages;
      };
      inherit overlaidPkgs finalPkgs;
    }
  )) channelPackageSpecs;

  rootImported = perImportingChannel.${rootChannelName};

  result = rootImported.forDependents.channelPackages.${rootChannelName}.attributes // {
    channelInfo = {
      # The original nixpkgs package set
      inherit originalPkgs;
      # Nixpkgs with the deep overlays applied
      inherit (rootImported) overlaidPkgs;
      # And nixpkgs with the floxpkgs layer applied
      inherit (rootImported) finalPkgs;
      # The packages for each channel
      perChannelAttributes = lib.mapAttrs (channel: value: value.attributes) rootImported.forDependents.channelPackages;
      # Where packages come from
      inherit packageRoots;
      # The package specifications as declared by each channel
      inherit channelPackageSpecs;
      # A nice visualization of how channels depend on each other
      inherit dependencyGraph;
      # The package set information
      inherit packageSets;
    };
  };

  resultWithWarning = if firstArgs ? extraOverlays then lib.warn "The `extraOverlays` argument defined in ${toString firstArgs.topdir}/default.nix is deprecated and has no effect anymore, it can be removed" result else result;

in resultWithWarning
