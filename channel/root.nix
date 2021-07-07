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
              else if lib.elem rootChannelName entries then rootChannelName
              else if firstArgs ? conflictResolution.${setName}.${pname} then firstArgs.conflictResolution.${setName}.${pname} # TODO: Validate that this option exists
              # Only when we have a single entry and it doesn't exist in nixpkgs, we can have an automatic conflict-free resolution
              else if lib.length entries == 1 && (lib.head entries == "flox" || ! existsInNixpkgs) then lib.head entries
              else throw "conflictResolution needs to be provided for ${setName}.${pname} in channel ${rootChannelName}. Options are ${toString entries + lib.optionalString existsInNixpkgs " nixpkgs"}";
          };

      in {
        deep = root true split.right;
        shallow = root false split.wrong;
      }
    ) setValue
  ) packageChannels;

  # FIXME: Custom callPackageWith that ensures default arguments aren't autopassed
  callPackageWith = lib.callPackageWith;

  createMeta = originalPkgs.callPackage ./meta.nix {
    sourceOverrides =
      if secondArgs ? sourceOverrideJson
      then builtins.fromJSON secondArgs.sourceOverrideJson
      else {};
    inherit utils callPackageWith floxPathDepth;
  };

  perImportingChannel = lib.mapAttrs (importingChannel: _:
    let
      pathsToModify = type: lib.concatMap (setName:
        lib.concatMap (version:
          let
            canonicalPath = packageSets.${setName}.versions.${version}.canonicalPath;

            overridingSet = lib.mapAttrs (pname: spec:
              channelPackages.${spec.${type}.channel}.perPackageSet.${setName}.${version}.${pname}
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
              mod = super: lib.getAttrFromPath canonicalPath (if type == "deep" then overlaidPkgs else finalPkgs);
            }) packageSets.${setName}.versions.${version}.aliases;

          in [ canonical ] ++ aliases
        ) (lib.attrNames packageSets.${setName}.versions)
      ) (lib.attrNames packageRoots);

      # TODO: Make sure pathsToModify isn't evaluated multiple times
      overlaidPkgs = originalPkgs.extend (self: utils.modifyPaths (pathsToModify "deep"));

      finalPkgs = utils.modifyPaths (pathsToModify "shallow") overlaidPkgs;

      channelPackages = lib.mapAttrs (ownChannel: ownChannelSpecs:
        import ./channel.nix {
          inherit lib utils trace packageSets originalPkgs floxPathDepth;
          inherit ownChannel ownChannelSpecs overlaidPkgs finalPkgs;
          dependencySet = perImportingChannel.${ownChannel}.forDependents;
          createMeta = createMeta importingChannel;
        }
      ) channelPackageSpecs;
    in {
      forDependents = {
        baseScope = finalPkgs // finalPkgs.xorg;
        inherit channelPackages;
      };
      inherit overlaidPkgs finalPkgs;
    }
  ) channelPackageSpecs;

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

  # Evaluate name early so that name inference warnings get displayed at the start, and not just once we depend on another channel
in result
