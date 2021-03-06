# Channel Name Inference Motivation and Complexities

An evaluation of `<flox-lib/channel>` for [constructing a flox channel](../channel-construction.md) makes a big effort to infer the channel name that's being evaluated. A channel might be evaluated with `nix-build '<myChan>' -A foo`, where `<myChan/default.nix>` contains the expression
```nix
import <flox-lib/channel> {
  topdir = ./.;
}
```

It is possible to specify the name explicitly with
```nix
import <flox-lib/channel> {
  name = "myChan";
  topdir = ./.;
}
```

This is however not ideal for getting started, since the [floxpkgs template](https://github.com/flox/floxpkgs-template) won't be able to fill this out, meaning users would have to edit `default.nix` manually before starting. By inferring the name automatically, this initial step is not necessary anymore.

## Why the channel name is needed at all

The channel name is needed for other channels to depend on the latest version of the current channel.

Imagine we have two channels `A` and `B`. A package from `A` depends on a package from `B`, which itself depends on another package from `A`. This is channel dependency cycle:

```
A------+
^      v
+------B
```

Now assuming we are evaluating within channel `A`, but don't _know_ that this is channel `A`, then we can change a package in `A` without that change propagating to `B`, since that just tries to get channel `A` from `NIX_PATH`, which notably can point to a different path than the path for `A` we're currently modifying.

```
unknown------+
             v
      A<-----B
```

By knowing that the channel we're evaluating is `A`, we can override the path for `A` on `NIX_PATH` with the one we're currently evaluating.

## Why it's so complicated

Channel name inference is not trivial however: The only information that the `<flox-lib/channel>` function gets is the `topdir` value. Since there's a variety of ways in which the channel can be evaluated, a number of heuristics are used to try to infer the name:
- By looking at the base name of the topdir: This is the easiest way to infer the name in cases where the directory name is the same as the channel. This won't trigger when the base name is just "floxpkgs" however, which is the standard name git would name it when cloning.
- By looking at the git remotes in the git config: In case the floxpkgs repository is a git checkout, this is very reliable

