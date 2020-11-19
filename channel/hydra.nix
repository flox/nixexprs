{ floxChannelName
, supportedSystems ? [ "x86_64-linux" "aarch64-linux" ]
}:
let
  channelRoot = builtins.findFile builtins.nixPath floxChannelName;
  channel = import channelRoot;
  releaseLib = import <nixpkgs/pkgs/top-level/release-lib.nix> {
    inherit supportedSystems;
    packageSet = channel;
    nixpkgsArgs = {
      config.allowUnfree = false;
      config.inHydra = true;
      name = floxChannelName;
    };
  };
in releaseLib.mapTestOn (releaseLib.packagePlatforms releaseLib.pkgs)
