# Arguments are described in ./default.nix
firstArgs: secondArgs:
let

  floxPathDepth = secondArgs._floxPathDepth or 2;

  # We allow passing through of nixpkgs arguments, but we don't want all the
  # flox-specific arguments to be passed
  nixpkgsArgs = removeAttrs secondArgs [
    "_isRoot"
    "_fromRoot"
    "name"
    "debugVerbosity"
    "subsystemVerbosities"
    "sourceOverrideJson"
    "_floxPathDepth"
  ];

  originalPkgs = import <nixpkgs> nixpkgsArgs;

  inherit (originalPkgs) lib;

  utils = import ./utils { inherit lib; };

  trace = utils.traceWith {
    defaultVerbosity = secondArgs.debugVerbosity or 0;
    subsystemVerbosities = secondArgs.subsystemVerbosities or { };
  };

  getChannelSource = originalPkgs.callPackage ./getSource.nix {
    inherit trace;
    sourceOverrides = if secondArgs ? sourceOverrideJson then
      builtins.fromJSON secondArgs.sourceOverrideJson
    else
      { };
  };

  packageSets = let
    pregenPath = toString (<nixpkgs-pregen> + "/package-sets.json");

    existingPregen = lib.importJSON pregenPath;
    existingVersion = existingPregen.version or 0;

    ownPregen = import ./package-sets.nix {
      inherit lib;
      pregenerate = true;
      nixpkgs = <nixpkgs>;
    };
    ownVersion = ownPregen.version;

    pregenResult = if !builtins.pathExists pregenPath then
      lib.warn
      "Path ${pregenPath} doesn't exist, won't be able to use precomputed result, evaluation will be slower"
      ownPregen
    else if existingVersion < ownVersion then
      lib.warn
      "Precomputed result exists, but was generated for an older floxpkgs package set version (version is ${
        toString existingVersion
      } but we want ${
        toString ownVersion
      }). Won't be able to use precomputed result, evaluation will be slower"
      ownPregen
    else if existingVersion > ownVersion then
      lib.warn
      "Precomputed result exists, but was generated for an newer floxpkgs package set version (version is ${
        toString existingVersion
      } but we want ${
        toString ownVersion
      }). Won't be able to use precomputed result, evaluation will be slower"
      ownPregen
    else
      trace "pregen" 1 "Reusing pregenerated ${pregenPath}" existingPregen;

    result = import ./package-sets.nix {
      inherit lib pregenResult;
      pregenerate = false;
    };
  in result.packageSets;

  rootChannelName =
    import ./name.nix { inherit lib firstArgs secondArgs trace utils; };

  # This is the result if we're not the root channel
  ownResult = import ./own.nix {
    inherit firstArgs lib utils trace packageSets;
    channelName = rootChannelName;
  };

  channelClosure = let
    sanitizeResult = name: result:
      result // {
        dependencies =
          removeAttrs (result.dependencies // { flox-lib = null; }) [ name ];
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
            inherit lib utils trace packageSets;
          };
        };
      in if !path.success then
        throw ''
          Channel "${name}" as declared as a dependency in channel "${origin}" can't found in NIX_PATH''
      else
        sanitizeResult name imported;

    operator = entry:
      map (name:
        trace "closure" 2 "Channel ${entry.key} depends on ${name}" {
          key = name;
          value = getChannel entry.key name;
        }) (lib.attrNames (removeAttrs entry.value.dependencies [ "nixpkgs" ]));

    result = builtins.genericClosure {
      startSet = [ root ];
      operator = operator;
    };
  in trace "closure" 1 "Determining channel closure" result;

  dependencyGraph =
    originalPkgs.runCommandNoCC "floxpkgs-${rootChannelName}-dependency-graph" {
      graph = ''
        digraph {
          "${rootChannelName}" [shape=box];
        ${
          lib.concatMapStrings (entry:
            lib.concatMapStrings (dep: "  \"${entry.key}\" -> \"${dep}\";\n")
            (lib.attrNames entry.value.dependencies)) channelClosure
        }}
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

  /* ## Package specifications

     A package specification is a structure containing most of the necessary
     information of a package for it to be usable by a dependent channel.

     It contains these fields

     {
       # Whether this package should be deeply overridden. If true, this
       # causes it to be injected into nixpkgs via an overlay
       deep = <bool>;

       # The path to the package expression
       path = <path>;
     }
  */

  /* Gives the values as returned by each channels own.nix calls

     {
       <channel> = {
         dependencies = [ ... ];
         packageSpecs.<packageSet>.<pname> = <package specification>;
         conflictResolution = { ... };
         rootFile = "...";
       };
     }
  */
  channelValues = lib.listToAttrs (map (entry: {
    name = entry.key;
    value = entry.value;
  }) channelClosure);

  /* Lists all channels (including nixpkgs) that contain a given package

     This value is used to construct the called versions of all packages later
     down below. It is also used for the conflict resolution to quickly know which
     channels provide a package and which don't.

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
        }) channelValues.${channel}.packageSpecs.${setName})
        (lib.attrNames channelValues);

      result = lib.mapAttrs (name: values:
        lib.listToAttrs values
        # Note that this relies on the fact that pkgs ? x == pkgs.pkgs ? x
        // lib.optionalAttrs (originalPkgs ? ${setName}.${name}) {
          nixpkgs = null;
        }) (lib.groupBy (p: p.pname) packages);
    in result) packageSets;

  /* Gives a mapping from package to the channel it should come from, for both
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
    trace.withContext "packageSet" setName (trace:
      lib.mapAttrs (pname: channels:
        trace.withContext "package" pname (trace:
          let
            # We're going to split the channels into ones that provide the deep
            # and non-deep version of the package. We need to split off nixpkgs
            # first though, since that's not a proper channel
            existsInNixpkgs = channels ? nixpkgs;

            # All channels providing this package as a list, and without nixpkgs
            channelList = lib.attrNames (removeAttrs channels [ "nixpkgs" ]);

            # Split the channels into deep (.right) and non-deep (.wrong)
            split = lib.partition (channel:
              channelValues.${channel}.packageSpecs.${setName}.${pname}.deep)
              channelList;

            root = deep: entries:
              trace.withContext "resolution"
              "root-${if deep then "deep" else "shallow"}" (trace:
                # Early exit in case there's no channel (needed to keep it lazy and fast)
                if entries == [ ] then
                  { }
                else {
                  channel =
                    # We don't allow deep overrides for packages that don't exist in
                    # nixpkgs already, because doing so would allow channels we
                    # depend on to change nixpkgs behavior without the user having
                    # to confirm it. This works by means of detecting _whether_
                    # package attributes are there or not, without evaluating them.
                    # This could allow a vulnerability in where upstream nixpkgs is
                    # injected with some code that only triggers when a certain
                    # attribute is there. But even without adversaries, we shouldn't
                    # allow changing nixpkgs behavior without a confirmation from
                    # the root channel
                    if deep && !existsInNixpkgs then
                      throw (''The package "${setName}.${pname}" in channel ''
                        + ''
                          "${
                            lib.head entries
                          }" is specified as `deep-override`-ing, ''
                        + "but this package doesn't exist in nixpkgs. Only packages "
                        + "that exist in nixpkgs can be deeply overridden.")

                      # If the root channel specifies this package, that takes precedence
                      # This allows the root channel to override any attribute of any
                      # other channel, without the user having to confirm it
                    else if lib.elem rootChannelName entries then
                      trace "resolution" 2 "Defined in root channel, using that"
                      rootChannelName

                    else
                      import ./resolve.nix {
                        inherit lib trace;
                        resolution =
                          firstArgs.conflictResolution.${setName}.${pname} or null;
                        channels = lib.mapAttrs (channel: _: {
                          invalid = "the package doesn't exist in this channel";
                        }) channelValues // lib.genAttrs entries (channel: {
                          valid = "the package exists in this channel";
                        }) // {
                          nixpkgs = if existsInNixpkgs then {
                            valid = "this package exists in nixpkgs";
                          } else {
                            invalid = "this package doesn't exist in nixpkgs";
                          };
                        };
                        rootFile = channelValues.${rootChannelName}.rootFile;
                        inherit setName pname;
                        resolutionNeededReason = "The ${
                            lib.optionalString deep "`deep-override` "
                          }package "
                          + "${lib.strings.escapeNixIdentifier setName}.${
                            lib.strings.escapeNixIdentifier pname
                          } is being used";
                      };
                });

          in {
            deep = root true split.right;
            shallow = root false split.wrong;
          })))) packageChannels;

  perImportingChannel = lib.mapAttrs (importingChannel: _:
    trace.withContext "importingChannel" importingChannel (trace:
      let
        pathsToModify = type:
          trace.withContext "pathsToModifyType" type (trace:
            lib.concatMap (setName:
              trace.withContext "packageSet" setName (trace:
                lib.concatMap (version:
                  trace.withContext "version" version (trace:
                    let
                      canonicalPath =
                        packageSets.${setName}.versions.${version}.canonicalPath;

                      existingRoots =
                        lib.filterAttrs (pname: spec: spec.${type} != { })
                        packageRoots.${setName};

                      canonical = {
                        path = canonicalPath;
                        mod = super:
                          let

                            overridingSet = lib.mapAttrs (pname: spec:
                              if spec.${type}.channel == "nixpkgs" then
                                super.${pname}
                              else
                                channelPackages.${
                                  spec.${type}.channel
                                }.perPackageSet.${setName}.${version}.${pname})
                              existingRoots;

                            tracingOverridingSet = trace "pathsToModify" 2
                              "Injecting attributes into path ${
                                trace.showValue canonicalPath
                              }: ${
                                trace.showValue (lib.attrNames overridingSet)
                              }" overridingSet;

                            result = if overridingSet == { } then
                              super
                            else if type == "deep" then
                              packageSets.${setName}.deepOverride super
                              tracingOverridingSet
                            else
                              super // tracingOverridingSet;

                          in result;
                      };

                      aliases = map (alias: {
                        path = alias;
                        mod = super:
                          trace "pathsToModify" 3
                          "Pointing alias ${trace.showValue alias} to ${
                            trace.showValue canonicalPath
                          }" (lib.getAttrFromPath canonicalPath
                            (if type == "deep" then
                              overlaidPkgs
                            else
                              finalPkgs));
                      }) packageSets.${setName}.versions.${version}.aliases;

                    in [ canonical ] ++ aliases))
                (lib.attrNames packageSets.${setName}.versions)))
            (lib.attrNames packageRoots));

        # Extend nixpkgs with an overlay that adds our deeply overridden packages
        overlaidPkgs =
          originalPkgs.extend (self: utils.modifyPaths (pathsToModify "deep"));

        # For shallow packages, just modify the attributes directly
        finalPkgs = utils.modifyPaths (pathsToModify "shallow") overlaidPkgs;

        /* Of the form
           {
             # Contains the called package for that channel, package set and version
             <channel>.perPackageSet.<packageSet>.<version>.<pname> = <derivation>;

             # The same as above, but turned into a nixpkgs-like attribute set
             <channel>.attributes = <derivations>;
           }
        */
        channelPackages = lib.mapAttrs (ownChannel: ownChannelValues:
          trace.withContext "channel" ownChannel (trace:
            import ./channel.nix {
              inherit lib utils trace packageSets originalPkgs floxPathDepth;
              inherit importingChannel ownChannel ownChannelValues overlaidPkgs
                finalPkgs packageChannels getChannelSource;
              dependencySet = perImportingChannel.${ownChannel};
            })) channelValues;
      in {
        baseScope = finalPkgs // finalPkgs.xorg;
        inherit overlaidPkgs finalPkgs channelPackages;
      })) channelValues;

  rootImported = perImportingChannel.${rootChannelName};

  result = rootImported.channelPackages.${rootChannelName}.attributes // {
    channelInfo = {
      # The original nixpkgs package set, no flox packages are included
      inherit originalPkgs;

      # The package set information, static over all channels, hopefully pregenerated
      inherit packageSets;

      # Non-processed information on each channel, including:
      # - dependencies: The immediate dependencies, including non-channel nixpkgs
      # - conflictResolution: The conflict resolution attribute set
      # - packageSpecs: The package set files this channel declares
      # - rootFile: The path to the channels default.nix file
      inherit channelValues;

      # A nice visualization of how channels depend on each other
      inherit dependencyGraph;

      # Gives the root channel for each package, as determined by the conflict resolution
      inherit packageRoots;

      # Fast lookup for Which channel defines a package
      inherit packageChannels;

      # Nixpkgs with the deeply overridden flox packages included
      inherit (rootImported) overlaidPkgs;

      # Nixpkgs with both the deep and shallow flox packages included
      inherit (rootImported) finalPkgs;

      # The base scope used for calling all packages
      inherit (rootImported) baseScope;

      # The packages for each channel
      inherit (rootImported) channelPackages;

      # Access to overlaidPkgs, finalPkgs, baseScope and channelPackages
      # but for a specific importing channel
      inherit perImportingChannel;
    };
  };

  resultWithWarning = if firstArgs ? extraOverlays then
    lib.warn "The `extraOverlays` argument defined in ${
      toString firstArgs.topdir
    }/default.nix is deprecated and has no effect anymore, it can be removed"
    result
  else
    result;

in resultWithWarning
