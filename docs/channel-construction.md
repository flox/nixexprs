# Channel construction

The entry point for channel construction is `<flox/channel>`, corresponding to [`flox/channel/default.nix`](../channel/default.nix). This function takes a set of arguments intended to be passed via a channels `default.nix` file. These are:

- `name` (string, default inferred): The name of the channel. If not specified, the name is inferred from a number of heuristics. See [channel name heuristics](#nameheuristics) for details.
- `topdir` (path, required): The path to the channel root. Usually just `./.`, indicating that the channel lives in the same directory as the file importing `<flox/channel>`. This directory is used to determine all outputs of the channel. See [`topdir` structure](#topdirstructure) for details.
- `extraOverlays` (list of nixpkgs overlays, default `[]`): Extra [nixpkgs overlays](https://nixos.org/manual/nixpkgs/stable/#sec-overlays-definition) to apply to the channel and its dependent channels.

The result of this function call is _another_ function, with arguments that all have default values. This allows evaluation of the channels `default.nix` via `nix-build -A`, but also allows customizing the arguments if necessary. This function has these arguments:

- `name` (string, default inferred): Another way to pass the name of the channel. If not specified, the name is inferred from a number of heuristics. If `name` is passed in the previous function call, that takes precedence over this one. See [name heuristics](#nameheuristics) for details.
- `debugVerbosity` (integer, default 0): The level of debug information to display during evaluation. A value of 10 should display pretty much everything, while 0 should display nothing. Very useful for debugging infinite recursion errors. See [debugging](#debugging) for details.
- `sourceOverrideJson` (JSON string, default `{}`): A JSON string for specifying source overrides of projects. See [source overrides](#sourceoverrides) for details.
- `_return` (internal): Internal return value of the channel creation. Used to implement dependencies on other channels
- `_isFloxChannel` (internal): Unused argument that hints that this is a Flox channel. This is used to discover Flox channels from `NIX_PATH`

The result of this function call are the channel outputs, as determined by mainly `topdir`. See [channel structure](#channelstructure) for details.

## `topdir` structure

The channel creation mechanism looks at a number of subdirectories of `topdir` to generate channel outputs from. Other than `pkgs`, all these subdirectories are determined by [`package-sets.nix`](../channel/package-sets.nix). Each subdirectory allows specifying a package set where each package has a <name> corresponding to the file it is defined in.

### Subdirectories

| Package set | Paths | Output attribute paths |
| --- | --- | --- |
| Toplevel | `pkgs/<name>/default.nix` or `pkgs/<name>.nix` | `<name>` |
| Python | `pythonPackages/<name>/default.nix` or `pythonPackages/<name>.nix` | `pythonPackages.<name>`, `python2Packages.<name>`, `python3Packages.<name>`, `python27Packages.<name>`, `python37Packages.<name>`, etc. |
| Perl | `perlPackages/<name>/default.nix` or `perlPackages/<name>.nix` | `perlPackages.<name>`, `perl530Packages.<name>`, `perl532Packages.<name>` |
| Haskell | `haskellPackages/<name>/default.nix` or `haskellPackages/<name>.nix` | `haskellPackages.<name>`, `haskell.packages.ghc865.<name>`, `haskell.packages.ghc882.<name>`, etc. |
| Erlang | `beamPackages/<name>/default.nix` or `beamPackages/<name>.nix` | `beamPackages.<name>`, `beam.packages.erlangR18.<name>`, `beam.packages.erlangR19.<name>`, etc. |

### Deep overrides

TODO

## Source overrides

TODO

## Name heuristics

TODO

## Debugging

TODO
