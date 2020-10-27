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
    pkgs = import <nixpkgs> {};
    inherit (pkgs) lib;

    lookupNixPath = path:
      let
        entry = lib.findFirst (e: lib.hasPrefix e.prefix path) (throw "No entry matching ${toString path} found in NIX_PATH") builtins.nixPath;
        suffix = lib.removePrefix entry.prefix path;
      in entry.path + suffix;

    # We only import nixpkgs once with an overlay that adds all channels, which is
    # also used as a base set for all channels themselves

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

        # Traces evaluation of another channel accessed from this one
        subchannelTrace = subname:
          withVerbosity 2 (builtins.trace "Accessing channel `${subname}` from `${name}`")
            (withVerbosity 3
              (lib.mapAttrsRecursiveCond
                (value: ! lib.isDerivation value)
                (path: builtins.trace "Evaluating channel `${subname}` attribute `${lib.concatStringsSep "." path}` from channel `${name}`")));

        # Each channel can refer to other channels via their names. This defines
        # the name -> channel mapping
        floxChannels' = self: lib.mapAttrs (subname: value:
          if name == subname
            then throw "Channel ${name} tried to access itself through flox.channels.${name}, but that shouldn't be necessary"
          else if ! lib.elem subname channelArguments.inputChannels
            then throw "Channel ${name} tried to access channel ${subname}, but it doesn't specify it in inputChannels"
          else subchannelTrace subname
            # Propagate the channel config down to all channels
            # And only expose the finalResult attribute so only the explicitly exposed attributes can be accessed
            (value.flox.withChannelConfig self.flox.channelConfig).flox.outputs
        ) floxChannels;

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
              channelPkgs'
              // {
                flox = import ./lib self // {
                  # Expose all channels
                  # TODO: Maybe prevent access to any channels not declared in inputChannels
                  channelName = name;
                  channels = floxChannels' self;
                  inherit lookupNixPath channelConfig withVerbosity args;

                  # All attributes that the outputOverlays define get added to this
                  # But if the attribute they define also has a flox.outputs attribute, we only add those instead of the whole attribute
                  outputs = {};

                  # Returns self, but with some channelConfig properties adjusted
                  # E.g. `withChannelConfig { defaultPythonVersion = 3; }` makes sure the result refers has all python defaults set to 3
                  # TODO: This doesn't seem to override channelConfig
                  # TODO: The channelConfig's of dependencies need to be used as a default if it's not provided by the importing channel
                  withChannelConfig = config:
                    # If the given properties already match the current config, just return self
                    if builtins.intersectAttrs config self.flox.channelConfig == config then self
                    else
                      # Otherwise override the current config with the new properties
                      let newConfig = self.flox.channelConfig // config;
                      in self.flox.withVerbosity 2
                        (builtins.trace "Reevaluating channel `${self.flox.channelName}` with new channel config: ${lib.generators.toPretty {} newConfig}")
                        # And return self with an additional overlay that sets the new channelConfig
                        (self.extend (self: super: {
                          flox = super.flox // {
                            channelConfig = newConfig;
                          };
                        }));
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

