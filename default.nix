# Things that can get passed via --arg/--argstr
{ debugVerbosity ? 0
, srcpath ? ""
, manifest_json ? ""
, manifest ? ""
}@args:
{
  channel =
    { name
    , nixpkgsOverlays ? []
    , inputChannels ? []
    , channelConfig ? {}
    , outputOverlays ? []
    }@channelArguments:
  let
    # We only import nixpkgs once with an overlay that adds all channels, which is
    # also used as a base set for all channels themselves
    pkgs = import <nixpkgs> {};
    inherit (pkgs) lib;

    lookupNixPath = path:
      let
        entry = lib.findFirst (e: lib.hasPrefix e.prefix path) (throw "No entry matching ${toString path} found in NIX_PATH") builtins.nixPath;
        suffix = lib.removePrefix entry.prefix path;
      in entry.path + suffix;

    withVerbosity = level: fun: val: if debugVerbosity >= level then fun val else val;

    # Mapping from channel name to a path to its nixexprs root
    channelNixexprs =
      let
        channelsJson = lib.importJSON (lookupNixPath "${name}-meta/channels.json");
        importFun = name: args:
          # For debugging, allow channel_json to specify paths directly
          if ! lib.isAttrs args then args
          else pkgs.fetchgit {
            inherit (args) url rev sha256 fetchSubmodules;
          };
      in lib.mapAttrs importFun channelsJson;

    # Imports a channel from a channel function call result
    importChannel = name: channelArguments:
      let
        channelPkgs' = withVerbosity 6
          (lib.mapAttrsRecursiveCond
            (value: ! lib.isDerivation value)
            (path: builtins.trace "Channel `${name}` is evaluating nixpkgs attribute ${lib.concatStringsSep "." path}"))
          # Don't let nixpkgs override our own extend
          # Remove appendOverlays as it doesn't use the current overlay chain
          # TODO: nixpkgs overlays?
          (removeAttrs pkgs [ "extend" "appendOverlays" ]);

        # A custom lib.extends function that can emit debug information for what attributes each overlay adds
        extends = overlay: fun: self:
          let
            super = fun self;
            overlayResult = overlay self super;
            result = super // withVerbosity 5
              (builtins.trace "Channel `${name}` applies an overlay with attributes: ${lib.concatStringsSep ", " (lib.attrNames overlayResult)}")
              overlayResult;
            finalResult = result // {
              flox = result.flox // {
                # TODO: Filter sub-attribute sets
                outputs = result.flox.outputs // builtins.intersectAttrs overlayResult self;
              };
            };
          in finalResult;

        # A function that returns the channel package set with the given overlays applied
        withOverlays = overlays:
          let
            # The main self-referential package set function
            baseFun = self:
              # Add all nixpkgs packages
              channelPkgs' // {
                flox = import ./floxlib.nix {
                  channelName = name;
                  inherit lib floxChannels self args channelArguments withVerbosity lookupNixPath;
                  channelMetas = lib.mapAttrs (name: value: lookupNixPath "${name}-meta") floxChannels;
                };

                callPackage = lib.callPackageWith self;

                # Try to avoid calling .extend because it's expensive
                extend = extraOverlays: withOverlays (overlays ++ lib.toList extraOverlays);
              };
          in lib.fix (lib.foldl' (lib.flip extends) baseFun overlays);

      in
        # Apply all the channels overlays to the scope
        withOverlays channelArguments.outputOverlays;

    importChannelSrc = name: src: withVerbosity 1
      (builtins.trace "Importing channel `${name}` from `${toString src}`")
      (importChannel name (import src).channelArguments);

    # All the channels
    floxChannels = lib.mapAttrs importChannelSrc channelNixexprs // {

      # Override our own channel to the current directory
      ${name} = importChannel name channelArguments;

    };
  in {
    # This exposes both inputChannels, which exposes the dependencies of this channel
    # And outputOverlays, which is needed if this channel wants to be used as a dependency
    inherit channelArguments;

    # The final output attributes of this channel
    outputs = floxChannels.${name}.flox.outputs;

    # For debugging
    inherit floxChannels;
  };

  auto = import ./auto.nix;
}

