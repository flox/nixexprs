# Flox channel reference

The flox channel has two main uses:
- Calling `<flox/channel>` in the `default.nix` of each channel to construct a channel output set. See [here](channel-construction.md) for documentation on this.
- The outputs of the flox channel itself, such as builders like `flox.mkDerivation` and others. See [here](flox-channel.md) for documentation on this.
