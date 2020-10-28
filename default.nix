# Things that can get passed via --arg/--argstr
{
  channel =
    # Arguments for the channel file in nixexprs
    { name
    , channelConfig ? {}
    , outputOverlays ? []
    }:
    # Arguments for the command line
    { debugVerbosity ? 0
    , srcpath ? ""
    , manifest_json ? ""
    , manifest ? ""
    , getOutputs ? true
    }@args:
  let

    # Propagating arguments like this, because just using `@channelArguments`
    # above would not propagate defaults
    channelArguments = {
      inherit name channelConfig outputOverlays;
    };

    # We only import nixpkgs once with an overlay that adds all channels, which is
    # also used as a base set for all channels themselves
    pkgs = import <nixpkgs> {};
    inherit (pkgs) lib;

    withVerbosity = level: fun: val: if debugVerbosity >= level then fun val else val;

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
                  inherit lib floxChannels self args channelArguments withVerbosity;
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
      (importChannel name (import src { getOutputs = false; }).channelArguments);

    # All the channels
    floxChannels = lib.mapAttrs importChannelSrc channelNixexprs // {

      # Override our own channel to the current directory
      ${name} = importChannel name channelArguments;

    };

    # The final output attributes of this channel
    outputs = floxChannels.${name}.flox.outputs;

  in if getOutputs then outputs else {
    # This exposes both inputChannels, which exposes the dependencies of this channel
    # And outputOverlays, which is needed if this channel wants to be used as a dependency
    inherit channelArguments;

    # For debugging
    inherit floxChannels;
  };

  auto = import ./auto.nix;
}

