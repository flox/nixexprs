# Things that can get passed via --arg/--argstr
{
  channel =
    # Arguments for the channel file in nixexprs
    { name
    # TODO: Make sure that you get an error if you set an unsupported auto
    , auto ? {}
    , extraOverlays ? []
    }:
    # Arguments for the command line
    { debugVerbosity ? 0
    , return ? "outputs"
    , srcpath ? ""
    , manifest_json ? ""
    , manifest ? ""
    }@args:
  let

    channelArguments = {
      inherit name auto extraOverlays args;
    };

    # Mapping from channel name to a path to its nixexprs root
    # Search through both prefixed and non-prefixed paths in NIX_PATH
    channelNixexprs =
      let
        expandEntry = e:
          if e.prefix != "" then [{
            name = e.prefix;
            value = e.path;
          }]
          else lib.mapAttrsToList (name: type: {
            inherit name;
            value = e.path + "/${name}";
          }) (builtins.readDir e.path);
      in lib.listToAttrs (lib.concatMap expandEntry builtins.nixPath);

    # Common to all channels
    baseOverlay = self: super: {
      flox = {
        channels = channelOutputs;
        inherit withVerbosity;
        outputs = {};
      };
    };

    # We only import nixpkgs once with an overlay that adds all channels, which is
    # also used as a base set for all channels themselves
    pkgs = import <nixpkgs> {
      overlays = [
        baseOverlay
        (import ./lib)
      ];
    };

    inherit (pkgs) lib;

    withVerbosity = level: fun: val: if debugVerbosity >= level then fun val else val;

    # The pkgs set for a specific channel
    channelPkgs = { name, auto, extraOverlays, args }:
      let
        channelOverlay = self: super: {
          flox = super.flox // {
            inherit name args auto;
          };
        };
        overlays = [
          channelOverlay
          (import ./auto/python.nix)
          (import ./auto/perl.nix)
          (import ./auto/toplevel.nix)
        ] ++ extraOverlays;
      in pkgs.appendOverlays overlays;

    importChannelSrc = name: src: withVerbosity 1
      (builtins.trace "Importing channel `${name}` from `${toString src}`")
      (channelPkgs (import src { return = "channelArguments"; }));

    floxChannels = lib.mapAttrs importChannelSrc channelNixexprs // {
      ${name} = channelPkgs channelArguments;
    };

    channelOutputs = lib.mapAttrs (subname: pkgs: pkgs.flox.outputs) floxChannels;

  in {
    inherit channelArguments;
    outputs = channelOutputs.${name};
  }.${return};
}

