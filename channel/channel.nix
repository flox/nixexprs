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

        createChannels = file:
          let
            channelAttrsCased = lib.mapAttrs (channel: value:
              value.attributes // lib.optionalAttrs (callScopeAttr != null) {
                ${callScopeAttr} = lib.getAttrFromPath versionInfo.canonicalPath value.attributes;
              }
            ) dependencySet.channelPackages;

            channelAttrs = channelAttrsCased // lib.mapAttrs' (name: lib.nameValuePair (lib.toLower name)) channelAttrsCased;

            withWarningPrefix = prefix: lib.mapAttrs (attr:
              lib.warn (
                "In ${file}, `${lib.concatStringsSep "." prefix}.${attr}` is "
                + "accessed, which is discouraged because it circumvents "
                + "potential package conflicts between channels. Please use "
                + "`${attr}` directly by adding it to the argument list at "
                + "the top of the file if it doesn't exist already, and "
                + "remove the `${lib.head prefix}` argument. The `${attr}` "
                + "argument contains the definitions from all channels and "
                + "gives a conflict warning if multiple channels define the "
                + "same package.")
            );
          in {
            channels = lib.mapAttrs (name: withWarningPrefix [ "channels" name ]) channelAttrs;
            flox = withWarningPrefix [ "flox" ] channelAttrs.flox;
          };

        # Basically the same as accessing individual channels from
        # createChannels, except that this is safe, and we don't need to
        # mess with attribute names
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
          inherit createChannels;
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
