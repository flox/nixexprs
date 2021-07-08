{ firstArgs
, channelName
, lib
, utils
, trace
, packageSets
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

    in lib.genAttrs allDeps (x: null);

  conflictResolution = firstArgs.conflictResolution or {};

  # Returns all the package specifications in our own channel
  packageSpecs = lib.mapAttrs (setName: _:
    utils.dirToAttrs (trace.setContext "dir" "${channelName}/${setName}") (topdir + "/${setName}")
  ) packageSets;

  rootFile = topdir + "/default.nix";

in {
  inherit dependencies packageSpecs conflictResolution rootFile;
}
