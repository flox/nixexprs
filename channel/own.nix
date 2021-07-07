{ firstArgs
, channelName
, lib
, utils
, trace
, packageSets
, packageChannels
}:
let

  topdir = toString firstArgs.topdir;

  # Cleaned up dependency list
  dependencies =
    let
      dependencyFile = topdir + "/channels.json";

      fileDeps =
        if builtins.pathExists dependencyFile
        then lib.importJSON dependencyFile
        else [];

      argDeps = firstArgs.dependencies or [];

      # We need to be able to handle flox, nixpkgs and own channel entries here
      # even if provided by another flox channel provider
      # Also we want nixpkgs to be in the list for determining the extends
      allDeps = fileDeps ++ argDeps ++ [ "flox" "nixpkgs" channelName ];

    in allDeps;

  # Dependencies of this channel, but only ones where we could get the super
  # version of packages from
  # This notably means that nixpkgs _needs_ to be included, which it is from
  # the above dependencies declaration
  superDependencyAttrs = removeAttrs (lib.genAttrs dependencies (name: null)) [
    # This means that the channel itself can't be included here
    channelName
  ];

  conflictResolution = firstArgs.conflictResolution or {};

  # Returns all the package specifications in our own channel
  packageSpecs = lib.mapAttrs (setName: _:
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
          attrs = lib.attrNames (builtins.intersectAttrs superDependencyAttrs packageChannels.${setName}.${pname});

          inlineOptions =
            let
              existsInNixpkgs = lib.elem "nixpkgs" attrs;
              attrsWithoutNixpkgs = lib.remove "nixpkgs" attrs;
            in lib.concatMapStringsSep ", " lib.strings.escapeNixIdentifier attrsWithoutNixpkgs + lib.optionalString existsInNixpkgs " and nixpkgs itself";

          options = lib.concatMapStrings (entry: ''
            conflictResolution.${lib.strings.escapeNixIdentifier setName}.${lib.strings.escapeNixIdentifier pname} = "${entry}";
          '') attrs;

          result =
            # If this channel specifies a conflict resolution for this package, use that directly
            if conflictResolution ? ${setName}.${pname} then conflictResolution.${setName}.${pname}
            # Otherwise, if no channel (or nixpkgs) has this attribute, we can't extend from anywhere
            else if lib.length attrs == 0 then null
            # But if there's only a single channel (or nixpkgs) providing it, we use that directly, no need for conflict resolution
            else if lib.length attrs == 1 then lib.head attrs
            else throw "In channel ${channelName}, the package \"${setName}.${pname}\" declared in ${value.path} uses \"${pname}\" from its arguments, which refers to the same package from another channel. However, it is ambiguous which channel it should point to since the package exists in channels ${inlineOptions}. This conflict needs to be resolved by adding one of the following lines to the passed attribute set in ${toString firstArgs.topdir}/default.nix:\n${options}";
        in result;
    }) (utils.dirToAttrs (trace.setContext "dir" "${channelName}/${setName}") (topdir + "/${setName}"))
  ) packageSets;
in {
  inherit packageSpecs dependencies;
}
