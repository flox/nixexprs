{}: {
  channel =
    { name
    , nixpkgsOverlays ? []
    , inputChannels ? []
    , outputOverlays ? []
    , debugVerbosity ? 0
    }:
  let
    channelName = name;

    /*

    - import global channels.json
    - Creates channel name -> channel expression mapping
      - Can include nixpkgs itself
    - Each channel is really just a set of overlays?
    - Can each channel choose its own nixpkgs version?
    Probably


    There's really only a couple things the flox nix exprs provide:
    - Tracking of a changing repository into a json file (each project)
    - Aggregation of these json files from all the users projects (each organization)
    - Aggretation of those json files from all the organizations (global json file)

    Each organization defines how each of their projects are built in a single repo
    CI that builds everything

    global.json:
    {
      <chan> = {
        nixexprs = <src-spec>;
        <project> = <src-spec>;
      };
    }

    Each channel declares the list of channels it depends on
    Any channel update of the transitive closure causes CI to run
    Only direct dependencies are available to use, all other channels are
      declared as an error that shows how to add that channel


    ## nixpkgs
    For a dependency tree, nixpkgs should be consistent
    But it should also not be treated any special

    There's already this channelConfig which can be set recursively over all dependencies
    Reuse this kind of mechanism for the nixpkgs base set as well.

    channels can

    What is different when a channel is used directly vs if it's a dependency?
    - For a dependency
    */

    stable = self.withChannelConfig { nixpkgs = self.flox.channels.nixpkgs.stable; };



    channels = self: {
      nixpkgs.stable = import <nixpkgs> {};
      myChan = self.nixpkgs.stable.appendOverlays [];
    };


    # We only import nixpkgs once with an overlay that adds all channels, which is
    # also used as a base set for all channels themselves
    pkgs = import <nixpkgs> {
      inherit system;
      overlays = [(self: super: {
        # TODO: This probably doesn't need to be set in the overlay
        inherit floxChannels;
      })];
    };

    inherit (pkgs) lib;

    withVerbosity = level: fun: val: if debugVerbosity >= level then fun val else val;

    # A mapping from channel name to channel source, as given by the channel_json
    channelSources = import <srcs> {};

    # Imports the channel from a source, adding extra attributes to its scope
    importChannel = name: src: extraAttrs:
      let
        # Allow channels to add nixpkgs overlays to their base pkgs. This also
        # allows channels to override other channels since pkgs.channelPkgs can be
        # changed via overlays
        channelPkgs = pkgs.appendOverlays nixpkgsOverlays;

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
          (value.withChannelConfig self.channelConfig).finalResult
        ) channelPkgs.floxChannels;

        # A custom lib.extends function that can emit debug information for what attributes each overlay adds
        extends = overlay: fun: self:
          let
            super = fun self;
            overlayResult = overlay self super;
          in super // withVerbosity 5
            (builtins.trace "Channel `${name}` applies an overlay with attributes: ${lib.concatStringsSep ", " (lib.attrNames overlayResult)}")
            overlayResult;

        # A function that returns the channel package set with the given overlays applied
        withOverlays = overlays:
          let
            # The main self-referential package set function
            baseFun = self:
              # Add all nixpkgs packages
              channelPkgs'
              # Expose all channels as attributes
              // floxChannels' self
              // {
                # The withVerbosity function for other overlays being able to emit debug traces
                inherit withVerbosity;
                # Channel name for debugging
                channelName = name;

                # Allow adding extra overlays on top
                # Note that this is an expensive operation and should be avoided using when possible
                extend = extraOverlays: withOverlays (overlays ++ lib.toList extraOverlays);
              }
              # Any extra attributes passed
              // extraAttrs;
          in lib.fix (lib.foldl' (lib.flip extends) baseFun overlays);

        # Apply all the channels overlays to the scope
        finalScope = withOverlays outputOverlays;

      in withVerbosity 1
        (builtins.trace "Importing channel `${name}` from `${toString src}`")
        finalScope;

    # The channel mapping to be passed into nixpkgs. This also allows nixpkgs
    # overlays to deeply override packages with channel versions
    floxChannels = lib.mapAttrs (name: src: importChannel name src {}) channelSources // {

      # Override our own channel to the current directory
      ${channelName} = importChannel channelName ./. {
        # Pass the arguments that were passed to this channel into the scope
        # These are used by floxSetSrcVersion.nix

        # TODO: Only the current channel would get the srcs like this
        # So all other channels won't work
        args = {
          inherit srcpath manifest manifest_json;
        };
      };

    };

  in pkgs.floxChannels.${channelName}.finalResult // {
    unfiltered = pkgs.floxChannels.${channelName};
  };

  auto = {
  };

}

