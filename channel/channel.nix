{ lib
, utils
, packageSets
, dependencySet
, createMeta
, originalPkgs
, overlaidPkgs
, finalPkgs
, trace
, floxPathDepth
, ownChannel
, ownChannelSpecs
}:
let

  channels =
    let
      original = lib.mapAttrs (channel: value:
        lib.mapAttrs (pname:
          lib.warn "Accessing channel.${channel}.${pname} from channel ${ownChannel}. This is discouraged as it circumvents the conflict resolution mechanism. Add ${pname} to the argument list directly instead."
        ) value.attributes
      ) dependencySet.channelPackages;
      lowered = lib.mapAttrs' (name: lib.nameValuePair (lib.toLower name)) original;
    in original // lowered;

  perPackageSet = lib.mapAttrs (setName: packages:
    let
      callScopeAttr = packageSets.${setName}.callScopeAttr;
    in
    lib.mapAttrs (version: versionInfo:
      let
        originalSet = lib.getAttrFromPath versionInfo.canonicalPath originalPkgs;
        overlaidSet = lib.getAttrFromPath versionInfo.canonicalPath overlaidPkgs;
        finalSet = lib.getAttrFromPath versionInfo.canonicalPath finalPkgs;

        baseScope' = dependencySet.baseScope // lib.optionalAttrs (callScopeAttr != null) (finalSet // {
          ${callScopeAttr} = finalSet;
        });

        channels' =
          if callScopeAttr == null then channels
          else lib.mapAttrs (channel: value:
            value // {
              ${callScopeAttr} = lib.getAttrFromPath versionInfo.canonicalPath value;
            }
          ) channels;

        # TODO: Cover this with tests
        perChannelPackages = lib.mapAttrs (channel: value:
          value.${setName}.${version}.perPackageSet
        ) dependencySet.channelPackages;
      in
      lib.mapAttrs (pname: spec:
        import ./package.nix {
          inherit lib trace floxPathDepth;
          inherit spec pname perChannelPackages originalSet overlaidSet createMeta ownChannel;
          baseScope = baseScope';
          channels = channels';
        }
      ) packages
    ) packageSets.${setName}.versions
  ) ownChannelSpecs;

  attributes = utils.nestedListToAttrs (lib.concatMap (setName:
    lib.concatMap (version:
      let
        value = perPackageSet.${setName}.${version};

        versionInfo = packageSets.${setName}.versions.${version};
        paths = [ versionInfo.canonicalPath ] ++ versionInfo.aliases;

        result = map (path: {
          inherit path value;
        }) paths;

      in lib.optionals (value != {}) result
    ) (lib.attrNames packageSets.${setName}.versions)
  ) (lib.attrNames packageSets));

in {
  inherit perPackageSet attributes;
}
