# Flox channel docs

## Reference

The flox channel has two main uses:
- Calling `<flox/channel>` in the `default.nix` of each channel to allow it to be evaluated to the outputs it defines. See [here](channel-construction.md) for reference documentation on this.
- Defining the outputs of the flox channel itself, such as builders like `flox.mkDerivation` and others. See [here](flox-channel.md) for reference documentation on this.

## Explanation

In addition, there are a number of documents describing certain aspects of the implementation. See the [expl](./expl) folder for these.
