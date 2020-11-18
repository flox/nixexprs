{ floxChannelName }:
let
  channelRoot = builtins.findFile builtins.nixPath floxChannelName;
  channel = import channelRoot;
  releaseLib = import <nixpkgs/pkgs/top-level/release-lib.nix> {
    supportedSystems = [ "x86_64-linux" ];
    packageSet = channel;
  };
  channelOutputs = channel {};
in releaseLib.mapTestOn (releaseLib.packagePlatforms channelOutputs)
