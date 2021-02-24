# Channel Discovery Mechanism and Motivation

Flox channels are discovered through `NIX_PATH` entries. While there are a number of alternatives, using `NIX_PATH` is perhaps the only way that satisfies all the conditions necessary for Flox to work the way it does.

The way Flox channels work is inherently impure: They are updated automatically, without any user interaction. Similarly, channel Nix expressions aren't pinned to a specific version of its dependent channels. While this means that channels aren't reproducible just on their own, this doesn't have a negative impact on end-users installing software with floxpm, because packages are only updated to versions that succeeded in CI.

This means that we need to rely on _some_ Nix impurity for passing channels around. We could use a number of impurities for this, but whichever we choose needs to be compatible with Hydra for building channels. One can pass impure inputs to Hydra in different ways:
- By using one of the input types that passes `--arg`/`--argstr` to the Nix file
- By using a path input type, which sets a `NIX_PATH` entry

The first option isn't viable however, because to provide a smooth user experience, the `nix-build` and co. commands would have to be wrapped to pass the channels with `--arg`/`--argstr` to the toplevel channel expression. While it might be possible to somehow detect whether a user is evaluating a flox channel and only add these arguments then, this would be a very brittle and inconsistent solution. And the same wouldn't be possible if users evaluate channels through e.g. `nix repl`.

So the only solution left is passing channels via `NIX_PATH`. This allows all of our requirements to be fulfilled:
- It's impure and allows automatic updates of channels
- It works in Hydra
- It allows a good user experience supporting `nix-build '<channel>' -A <pkg>` and `nix repl`
