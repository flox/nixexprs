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

  # We only import nixpkgs once with an overlay that adds all channels, which is
  # also used as a base set for all channels themselves
  pkgs = import <nixpkgs> {};
  inherit (pkgs) lib;

  withVerbosity = level: fun: val: if debugVerbosity >= level then fun val else val;

  myChannelArgs = {
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
        # TODO: Change flox wrapper to do this expansion
        else lib.mapAttrsToList (name: type: {
          inherit name;
          value = e.path + "/${name}";
        }) (builtins.readDir e.path);
    in lib.listToAttrs (lib.concatMap expandEntry builtins.nixPath);

  importChannelSrc = name: src: withVerbosity 1
    (builtins.trace "Importing channel `${name}` from `${toString src}`")
    (import src { return = "channelArguments"; });

  channelArgs = lib.mapAttrs importChannelSrc channelNixexprs // {
    ${name} = myChannelArgs;
  };


  # The pkgs set for a specific channel
  channelPkgs = parentChannel: { name, auto, extraOverlays, args }:
    let

      channels = lib.mapAttrs (name: value: value.floxInternal.outputs) channels.${name};

      channelOverlay = self: super: {
        floxInternal = {
          inherit parentChannel args withVerbosity;
          outputs = {};

          # Merges pkgs and own channel outputs recursively
          mainScope = lib.recursiveUpdateUntil (path: l: r:
            let
              lDrv = lib.isDerivation l;
              rDrv = lib.isDerivation r;
            in
              if lDrv == rDrv then rDrv
              else throw ("Trying to override ${lib.optionalString (!lDrv) "non-"}derivation in nixpkgs"
                + " with a ${lib.optionalString (!rDrv) "non-"}derivation in channel")
          ) self self.floxInternal.outputs // {
            inherit channels;
            flox = channels.flox;
          };
        };
      };
      overlays = [ channelOverlay ]
        ++ lib.optional (auto ? toplevel)
          (import ./auto/toplevel.nix auto.toplevel)
        ++ extraOverlays;
    in pkgs.appendOverlays overlays;


  channels = lib.mapAttrs (parent: _:
    lib.mapAttrs (_: args:
      channelPkgs parent args
    ) channelArgs
  ) channelArgs;

  outputs = channels.${name}.${name}.floxInternal.outputs;

in {
  inherit outputs;
  channelArguments = myChannelArgs;
}.${return}
