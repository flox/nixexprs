{ floxChannelName, supportedSystems ? [ "x86_64-linux" "aarch64-linux" ]
, nixpkgsArgs ? {
  config = {
    allowUnfree = false;
    inHydra = true;
  };
} }:
let
  channelRoot = builtins.findFile builtins.nixPath floxChannelName;
  channel = import channelRoot;
  releaseLib = import <nixpkgs/pkgs/top-level/release-lib.nix> {
    inherit supportedSystems;
    packageSet = channel;
    nixpkgsArgs = nixpkgsArgs // { name = floxChannelName; };
  };
in releaseLib.mapTestOn (releaseLib.packagePlatforms releaseLib.pkgs)
