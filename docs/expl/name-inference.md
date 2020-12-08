# Why channel name inference is needed and why it's so complicated

The `<flox/channel>` mechanism makes a big effort to infer the channel name that's being evaluated. A channel might be evaluated with `nix-build '<myChan>' -A foo`, where `<myChan/default.nix>` contains the expression
```nix
import <flox/channel> {
  topdir = ./.;
}
```

It is possible to specify the name explicitly with
```nix
import <flox/channel> {
  name = "myChan";
  topdir = ./.;
}
```

This is however not ideal for getting started, since the [nixexprs template](https://github.com/flox/nixexprs-template) won't be able to fill this out, meaning users would have to edit `default.nix` manually before starting. By inferring the name automatically, this initial step is not necessary anymore.

## Why it's so complicated

Channel name inference is not trivial however: The only information that the `<flox/channel>` function gets is the `topdir` value. Since there's a variety of ways in which the channel can be evaluated, a number of heuristics are used to try to infer the name:
- By looking at the base name of the topdir: This is the easiest way to infer the name in cases where the directory name is the same as the channel. This won't trigger when the base name is just "nixexprs" however, which is the standard name git would name it when cloning.
- By looking at the git remotes in the git config: In case the nixexprs repository is a git checkout, this is very reliable
- By trying to find `topdir` in `NIX_PATH`: Since all channels are passed via `NIX_PATH`, there's a good chance some entry in there points at it. The value of that entry is the channel name. There is a problem with this heuristic however: If a `NIX_PATH` entry points `<myChan>` to `/some/path`, and `/some/path` is a symlink, then `topdir` will point to the _target_ of the symlink, while the `NIX_PATH` entry points to the _source_ of it, so it can't match them together. And there is no way to resolve symlinks in Nix.

In addition, channel inference handles different casings: GitHub usernames, and therefore `NIX_PATH` channel entries, are case-insensitive, but case-preserving. So if any channel inference mechanism finds a match, it looks at all the entries in `NIX_PATH` to correct the casing if necessary.

## Why the channel name is needed at all

The channel name is needed in order for other channels to depend on the latest version of the current channel.


