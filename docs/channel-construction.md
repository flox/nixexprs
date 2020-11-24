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

The result of this function call are the channel outputs, as determined by mainly `topdir`. See [channel structure](#topdirstructure) for details.

## `topdir` structure

The channel creation mechanism looks at a number of subdirectories of `topdir` to generate channel outputs from. Other than `pkgs`, all these subdirectories are determined by [`package-sets.nix`](../channel/package-sets.nix). Each subdirectory allows specifying a package set where each package has a <name> corresponding to the file it is defined in.

### Subdirectories

| Package set | Call scope attribute | Paths | Output attribute paths |
| --- | --- | --- | --- |
| Toplevel | - | `pkgs/<name>/default.nix` or `pkgs/<name>.nix` | `<name>` |
| Python | `pythonPackages` | `pythonPackages/<name>/default.nix` or `pythonPackages/<name>.nix` | `pythonPackages.<name>`, `python2Packages.<name>`, `python3Packages.<name>`, `python27Packages.<name>`, `python37Packages.<name>`, etc. |
| Perl | `perlPackages` | `perlPackages/<name>/default.nix` or `perlPackages/<name>.nix` | `perlPackages.<name>`, `perl530Packages.<name>`, `perl532Packages.<name>` |
| Haskell | `haskellPackages` | `haskellPackages/<name>/default.nix` or `haskellPackages/<name>.nix` | `haskellPackages.<name>`, `haskell.packages.ghc865.<name>`, `haskell.packages.ghc882.<name>`, etc. |
| Erlang | `beamPackages` | `beamPackages/<name>/default.nix` or `beamPackages/<name>.nix` | `beamPackages.<name>`, `beam.packages.erlangR18.<name>`, `beam.packages.erlangR19.<name>`, etc. |

All of these subdirectories also support declaring packages as deep overriding by creating `*/<name>/deep-override`, which only works for the `*/<name>/default.nix` forms, not `*/<name>.nix`.

### Call scope

All paths in `*/<name>/default.nix` and `*/<name>.nix` are auto-called with a scope containing these attributes in increasing priority:
- All attributes of nixpkgs and its `xorg` set, so `pkgs.*` and `pkgs.xorg.*`
- All of this channels output attributes, merged into the above set
- `meta`: An attribute set containing
  - `meta.getSource`: A function for getting sources of the current channel, see [`getSource`](get-source.md)
  - `meta.getBuilderSource`: A function for getting sources of the channel that imports the current channel, see [`getSource`](get-source.md). This is useful to define builders reusable by other channels.
  - `meta.withVerbosity`: A function that allows printing debug information based on verbosity level, see [debugging](#debugging) for details
- `channels`: An attribute set containing the outputs of all other available channels:
  - `channels.<channel>.<output>`: Output attribute `<output>` of channel `<channel>`
- `flox`: A convenience alias to `channels.flox` for accessing the Flox channels outputs
- `<name>`: The package in nixpkgs of the same name as the one defined. This allows package overriding without getting infinite recursion

In addition, for all package sets in [above table](#subdirectories) that have a call scope attribute `<attr>`, the following are in scope as well:
- `<attr>`: A version-agnostic package set consisting of:
  - The packages in nixpkgs
  - This channels packages
  - `<name>`: The package in nixpkgs of the same name as the one defined. This allows package overriding without getting infinite recursion
- All attributes of the above set
- `channels`: An attribute set containing the outputs of all other available channels:
  - `channels.<channel>.<output>`: Output attribute `<output>` of channel `<channel>`
  - `channels.<channel>.<attr>`: A version-agnostic package set for that channel

## Source overrides

TODO

## Name heuristics

TODO

## Debugging

TODO
