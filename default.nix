# Things that can get passed via --arg/--argstr
{ debugVerbosity ? 0
, srcpath ? ""
, manifest_json ? ""
, manifest ? ""
}@args:
{
  channel =
    { channelName
    , nixpkgsOverlays ? []
    , inputChannels ? []
    , channelConfig ? {}
    , outputOverlays ? []
    }:
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
        channelsJson = lib.importJSON (lookupNixPath "${channelName}-meta/channels.json");
        importFun = name: args:
          # For debugging, allow channel_json to specify paths directly
          if ! lib.isAttrs args then args
          else pkgs.fetchgit {
            inherit (args) url rev sha256 fetchSubmodules;
          };
      in lib.mapAttrs importFun channelsJson;

    # Want:
    # <channelName> -> { outputOverlays = ...; srcs = ...; }
    # For the current channel, get outputOverlays from the arguments
    #   -> allows testing things without committing
    # For the other channels, get outputOverlays by looking at <$currentChannel-meta>/channels.json
    # For all channels, get srcs from <$channel-meta>/srcs
    # Get the list of channels from <$currentChannel-meta>/channels.json


    # Imports the channel from a source, adding extra attributes to its scope
    importChannel = name: outputOverlays:
      let
        # Allow channels to add nixpkgs overlays to their base pkgs. This also
        # allows channels to override other channels since pkgs.channelPkgs can be
        # changed via overlays
        # TODO: nixpkgs overlays?
        #channelPkgs = pkgs.appendOverlays nixpkgsOverlays;
        channelPkgs = pkgs;

        channelPkgs' = withVerbosity 6
          (lib.mapAttrsRecursiveCond
            (value: ! lib.isDerivation value)
            (path: builtins.trace "Channel `${name}` is evaluating nixpkgs attribute ${lib.concatStringsSep "." path}"))
          # Remove floxChannels as we modify them slightly for access by other channels
          # Don't let nixpkgs override our own extend
          # Remove appendOverlays as it doesn't use the current overlay chain
          (removeAttrs channelPkgs [ "floxChannels" "extend" "appendOverlays" ]);

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
          subchannelTrace subname
          # Propagate the channel config down to all channels
          # And only expose the finalResult attribute so only the explicitly exposed attributes can be accessed
          (value.flox.withChannelConfig self.flox.channelConfig).flox.outputs
        ) floxChannels;

        # A custom lib.extends function that can emit debug information for what attributes each overlay adds
        extends = overlay: fun: self:
          let
            super = fun self;
            overlayResult = overlay self super;
          in super // withVerbosity 5
            (builtins.trace "Channel `${name}` applies an overlay with attributes: ${lib.concatStringsSep ", " (lib.attrNames overlayResult)}")
            (overlayResult // {
              flox = super.flox // {
                # TODO: Filter sub-attribute sets
                outputs = super.flox.outputs // builtins.intersectAttrs overlayResult self;
              };
            });

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
        withOverlays outputOverlays;

    importChannelSrc = name: src: withVerbosity 1
      (builtins.trace "Importing channel `${name}` from `${toString src}`")
      (importChannel name (import (src + "/channel.nix")).outputOverlays);

    # The channel mapping to be passed into nixpkgs. This also allows nixpkgs
    # overlays to deeply override packages with channel versions
    floxChannels = lib.mapAttrs importChannelSrc channelNixexprs // {

      # Override our own channel to the current directory
      ${channelName} = importChannel channelName outputOverlays;

    };


    outputs = floxChannels.${channelName}.flox.outputs // {
      unfiltered = floxChannels.${channelName};
    };

  in {
    # Should return:
    # - outputOverlays (so that other channels can import that)
    # - inputChannels (so that the transitive dependencies can be found)
    # - resultScope (so that the result can be evaluated)
    inherit inputChannels outputOverlays outputs floxChannels;
  };

  auto = let

    # Given a directory and self/super, generate an attribute set where every
    # attribute corresponds to a subdirectory, which is autocalled with the given callPackage
    genPackageDirAttrs = dir: self: super: callPackage:
      let
        inherit (super) lib;
        # TODO: Warn or error or do something else for non-directories?
        subdirs = lib.attrNames (lib.filterAttrs (name: type: type == "directory") (builtins.readDir dir));
        subdirPackage = name: self.flox.withVerbosity 4
          (builtins.trace "Auto-calling ${toString (dir + "/${name}")}")
          (callPackage (dir + "/${name}") {});
      in lib.genAttrs subdirs subdirPackage;

  in {
    python = dir: self: super:
      let
        autoPythonPackages = version:
          let
            pythonPackages = "python${toString version}Packages";
          in {
            ${pythonPackages} = super.${pythonPackages}
              # The callPackage within this package set should have the correct default python version
              # So instead of just using self directly, we use self with the channel config adjusted to what we need
              // { callPackage = super.lib.callPackageWith (self.flox.withChannelConfig { defaultPythonVersion = version; }); }
              // genPackageDirAttrs dir self super self.${pythonPackages}.callPackage;
          };
      in autoPythonPackages 2 // autoPythonPackages 3 // {
        python = self."python${toString self.flox.channelConfig.defaultPythonVersion}";
        pythonPackages = self."python${toString self.flox.channelConfig.defaultPythonVersion}Packages";
      };
  };

}

