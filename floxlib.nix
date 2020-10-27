{ lib
, channelName
, floxChannels
, channelArguments
, withVerbosity
, lookupNixPath
, channelMetas
, args
, self
}:
let


  # Traces evaluation of another channel accessed from this one
  subchannelTrace = subname:
    withVerbosity 2 (builtins.trace "Accessing channel `${subname}` from `${channelName}`")
      (withVerbosity 3
        (lib.mapAttrsRecursiveCond
          (value: ! lib.isDerivation value)
          (path: builtins.trace "Evaluating channel `${subname}` attribute `${lib.concatStringsSep "." path}` from channel `${channelName}`")));

  # Each channel can refer to other channels via their names. This defines
  # the name -> channel mapping
  floxChannels' = lib.mapAttrs (subname: value:
    if channelName == subname
      then throw "Channel ${channelName} tried to access itself through flox.channels.${channelName}, but that shouldn't be necessary"
    else if ! lib.elem subname channelArguments.inputChannels
      then throw "Channel ${channelName} tried to access channel ${subname}, but it doesn't specify it in inputChannels"
    else subchannelTrace subname
      # Propagate the channel config down to all channels
      # And only expose the finalResult attribute so only the explicitly exposed attributes can be accessed
      (value.flox.withChannelConfig self.flox.channelConfig).flox.outputs
      ) floxChannels;

in
{
  inherit channelName channelMetas args;
  # Expose all channels
  channels = floxChannels';
  channelConfig = channelArguments.channelConfig;

  # Returns self, but with some channelConfig properties adjusted
  # E.g. `withChannelConfig { defaultPythonVersion = 3; }` makes sure the result refers has all python defaults set to 3
  withChannelConfig = config:
    # If the given properties already match the current config, just return self
    if builtins.intersectAttrs config self.flox.channelConfig == config then self
    else
      # Otherwise override the current config with the new properties
      let newConfig = self.flox.channelConfig // config;
      in withVerbosity 2
        (builtins.trace "Reevaluating channel `${self.flox.channelName}` with new channel config: ${lib.generators.toPretty {} newConfig}")
        # And return self with an additional overlay that sets the new channelConfig
        (self.extend (self: super: {
          flox = super.flox // {
            channelConfig = newConfig;
          };
        }));

  # All attributes that the outputOverlays define get added to this
  # But if the attribute they define also has a flox.outputs attribute, we only add those instead of the whole attribute
  outputs = {};

  utils = {
    inherit withVerbosity lookupNixPath;
  };

} // import ./lib self
