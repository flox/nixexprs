{ firstArgs
, channelName
, lib
, utils
, trace
, packageSets
, packageChannels
}:
let

  topdir = toString (firstArgs.topdir or (throw "Channel ${channelName} provided no \"topdir\" argument in its default.nix file"));

  fileDeps =
    if builtins.pathExists (topdir + "/channels.json")
    then builtins.fromJSON (builtins.readFile (topdir + "/channels.json"))
    else [];

  argDeps = firstArgs.dependencies or [];

  conflictResolution = firstArgs.conflictResolution or {};

  dependencies = lib.unique (lib.subtractLists [ channelName "nixpkgs" ] (fileDeps ++ argDeps ++ [ "flox" ]));

  dependencyAttrs = removeAttrs (lib.genAttrs (dependencies ++ [ "nixpkgs" ]) (name: null)) [ channelName ];

  /*
  Returns all the package specifications in our own channel. To determine the
  `extends` fields for each package, it is necessary to know which other
  channels provide the same package, which is why this function takes a
  `packageChannels` argument. This argument is passed by the root channel, in
  order to not duplicate the work of determining its value.
  */
  packageSpecs = lib.mapAttrs (setName: packageSet:
    lib.mapAttrs (pname: value: {
      deep = value.deep;
      exprPath = value.path;
      extends =
        let
          # Since we got the packageChannels from the root channel to share
          # work, we will however also have a potential superset of only our
          # own dependencies. We don't want non-dependencies to influence
          # which channel we extend from though, so we limit the channels
          # that contain the same package to the ones we depend on
          # Note that we only allow immediate dependencies here because ideally
          # a channel would not depend on transitive attributes
          attrs = lib.attrNames (builtins.intersectAttrs dependencyAttrs packageChannels.${setName}.${pname});
          result =
            # If this channel specifies a conflict resolution for this package, use that directly
            if conflictResolution ? ${setName}.${pname} then conflictResolution.${setName}.${pname}
            # Otherwise, if no channel (or nixpkgs) has this attribute, we can't extend from anywhere
            else if lib.length attrs == 0 then null
            # But if there's only a single channel (or nixpkgs) providing it, we use that directly, no need for conflict resolution
            else if lib.length attrs == 1 then lib.head attrs
            else throw "Needs super conflict resolution for ${setName}.${pname} in channel ${channelName}, ${toString attrs}";
        in result;
    }) (utils.dirToAttrs (trace.setContext "dir" "${channelName}/${setName}") (topdir + "/${setName}"))
  ) packageSets;
in {
  inherit packageSpecs dependencies;
}
