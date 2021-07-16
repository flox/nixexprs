{ lib, utils, packageSets, dependencySet, originalPkgs, overlaidPkgs, finalPkgs
, trace, floxPathDepth, importingChannel, ownChannel, ownChannelValues
, packageChannels, getChannelSource }:
let

  perPackageSet = lib.mapAttrs (setName: packages:
    trace.withContext "packageSet" setName (trace:
      let callScopeAttr = packageSets.${setName}.callScopeAttr;
      in lib.mapAttrs (version: versionInfo:
        trace.withContext "version" version (trace:
          let
            finalSet = lib.getAttrFromPath versionInfo.canonicalPath finalPkgs;
            baseScope' = dependencySet.baseScope
              // lib.optionalAttrs (callScopeAttr != null)
              (finalSet // { ${callScopeAttr} = finalSet; });
          in lib.mapAttrs (pname: spec:
            trace.withContext "package" pname (trace:
              let
                floxFile = toString
                  (if builtins.pathExists (spec.path + "/default.nix") then
                    spec.path + "/default.nix"
                  else
                    spec.path);

                superChannel = import ./resolve.nix {
                  inherit lib;
                  trace = trace.setContext "resolution" "super";
                  resolution =
                    ownChannelValues.conflictResolution.${setName}.${pname} or null;
                  channels = lib.mapAttrs (channel: _:
                    if !packageChannels.${setName}.${pname} ? ${channel} then {
                      invalid = "the package doesn't exist in this channel";
                    } else if !ownChannelValues.dependencies ? ${channel} then {
                      invalid =
                        "the package exists in this channel, but it is not defined as a direct dependency";
                    } else {
                      valid =
                        "this channel is a direct dependency and the package exists in it";
                    }) dependencySet.channelPackages // {
                      nixpkgs =
                        if packageChannels.${setName}.${pname} ? nixpkgs then {
                          valid = "this package exists in nixpkgs";
                        } else {
                          invalid = "this package doesn't exist in nixpkgs";
                        };
                      ${ownChannel} = {
                        invalid =
                          "The super version can't come from its own channel";
                      };
                    };
                  rootFile = ownChannelValues.rootFile;
                  inherit setName pname;
                  resolutionNeededReason = "In the definition of the ${
                      lib.strings.escapeNixIdentifier setName
                    }.${lib.strings.escapeNixIdentifier pname} "
                    + "package in ${floxFile}, the argument ${pname} itself is being used, "
                    + "which points to the unoverridden version of the same package";
                };

                nixpkgsSet = lib.getAttrFromPath versionInfo.canonicalPath
                  (if spec.deep then originalPkgs else overlaidPkgs);

                superPackage = if superChannel == "nixpkgs" then
                  nixpkgsSet.${pname}
                else
                  dependencySet.channelPackages.${superChannel}.perPackageSet.${setName}.${version}.${pname};

                channelAttrsCased = lib.mapAttrs (channel: value:
                  value.attributes
                  // lib.optionalAttrs (callScopeAttr != null) {
                    ${callScopeAttr} =
                      lib.getAttrFromPath versionInfo.canonicalPath
                      value.attributes;
                  }) dependencySet.channelPackages;

                channelAttrs = channelAttrsCased
                  // lib.mapAttrs' (name: lib.nameValuePair (lib.toLower name))
                  channelAttrsCased;

                withWarningPrefix = prefix:
                  lib.mapAttrs (attr:
                    lib.warn ("In ${floxFile}, `${
                        lib.concatStringsSep "." prefix
                      }.${attr}` is "
                      + "accessed, which is discouraged because it circumvents "
                      + "potential package conflicts between channels. Please use "
                      + "`${attr}` directly by adding it to the argument list at "
                      + "the top of the file if it doesn't exist already, and "
                      + "remove the `${
                        lib.head prefix
                      }` argument. The `${attr}` "
                      + "argument contains the definitions from all channels and "
                      + "gives a conflict warning if multiple channels define the "
                      + "same package."));

              in import ./package.nix {
                inherit lib utils trace floxPathDepth importingChannel
                  ownChannel getChannelSource floxFile;
                channels =
                  lib.mapAttrs (name: withWarningPrefix [ "channels" name ])
                  channelAttrs;
                flox = withWarningPrefix [ "flox" ] channelAttrs.flox-lib;
                floxPath = spec.path;
                baseScope = baseScope';
                superScope.${pname} = superPackage;
              })) packages)) packageSets.${setName}.versions))
    ownChannelValues.packageSpecs;

  attributes = utils.nestedListToAttrs trace (lib.concatMap (setName:
    lib.concatMap (version:
      let
        value = perPackageSet.${setName}.${version};
        versionInfo = packageSets.${setName}.versions.${version};

        canonical = {
          path = versionInfo.canonicalPath;
          inherit value;
        };

        hydraRecurse = lib.imap1 (prefixLength: _: {
          path = lib.take prefixLength versionInfo.canonicalPath
            ++ [ "recurseForDerivations" ];
          value = true;
        }) versionInfo.canonicalPath;

        aliases = map (path: { inherit path value; }) versionInfo.aliases;

        all = [
          canonical
        ]
        # Only let hydra recurse if the package set is recursed into by nixpkgs too
          ++ lib.optionals versionInfo.recurse hydraRecurse ++ aliases;

      in lib.optionals (value != { }) all)
    (lib.attrNames packageSets.${setName}.versions))
    (lib.attrNames packageSets));

in { inherit perPackageSet attributes; }
