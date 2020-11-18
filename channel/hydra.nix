{ floxChannelName
, supportedSystems ? [ "x86_64-linux" "aarch64-linux" ]
}:
let
  channelRoot = builtins.findFile builtins.nixPath floxChannelName;
  channel = import channelRoot;
  releaseLib = import <nixpkgs/pkgs/top-level/release-lib.nix> {
    inherit supportedSystems;
    packageSet = channel;
  };
  channelOutputs = channel {};
in releaseLib.mapTestOn (releaseLib.packagePlatforms channelOutputs)
