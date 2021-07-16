# Channel construction

Each channel needs to have a `default.nix` in its root that calls the `<flox-lib/channel>` function to construct a channel, which allows the user to run `nix-build` to build outputs, Hydra to find all outputs, and other channels to use this channel as a dependency. The entrypoint of this function is in [`flox-lib/channel/default.nix`](../channel/default.nix).

## Channel file arguments

A call to `<flox-lib/channel>` in a channels root `default.nix` file usually looks like
```nix
import <flox-lib/channel> {
  topdir = ./.;
}
```

Available arguments are:
- `name` (string, default inferred): The name of the channel. If not specified, the name is inferred automatically if possible.
- `topdir` (path, required): The path to the channel root, which should be the directory of the `default.nix` itself, so `./.`. This directory is used to determine all outputs of the channel. See the [subdirectories](#topdir-subdirectories) section for details.
- `conflictResolution` (attribute set, default `{}`): How package conflicts for this channel should be resolved. See the [package conflict document](./conflicts.md) for how this is used.

## CLI arguments

The result of the above function call is _another_ function, but with all arguments defaulted. This allows building of packages with `nix-build -A <package>`, but also allows overriding the defaults with `--arg`/`--argstr`, such as
```
$ nix-build -A myPackage --arg debugVerbosity 4
```

Available arguments are:
- `name` (string, default inferred): Another way to pass the name of the channel. If not specified, the name is inferred automatically if possible. If `name` is passed in the channel file arguments, that takes precedence over this one.
- `debugVerbosity` (integer, default 0): The level of debug information to display during evaluation. See [the trace configuration docs](./debugging.md#configuring-tracing) for more details.
- `subsystemVerbosities` (attribute set of integers, default `{}`): Custom trace verbosities for specific subsystems. See [the trace configuration docs](./debugging.md#configuring-tracing) for more details.
- `sourceOverrideJson` (JSON string, default `{}`): A JSON string for specifying source overrides of projects. This allows changing the source of packages temporarily without having to rely on the auto-updating mechanism. Used by `flox build`
  This is of the form
  ```json
  {
    "<githubUser>" : {
      "<githubRepo>" : "/path/to/overridden/source"
    }
  }
  ```
- Any extra arguments are passed through to the underlying nixpkgs, the most useful ones being
  - `system` (string, default from `builtins.currentSystem`): The system the channel should be built for, e.g. `x86_64-linux`, `aarch64-linux` or `x86_64-darwin`
  - `config` (attribute set, default `{}`): The nixpkgs config, can be used to pass e.g. `allowUnfree = true` or `permittedInsecurePackages = [ "openssl-1.0.2u" ]`. See [the nixpkgs docs](https://nixos.org/manual/nixpkgs/stable/#chap-packageconfig) for more information.

The result of this function call are the channel outputs, as determined by mainly `topdir`. See below section for details.

## `topdir` subdirectories

The channel creation mechanism looks at a number of subdirectories of `topdir` to generate channel outputs from. All these subdirectories are determined by [`package-sets.nix`](../channel/package-sets.nix). See [here](./package-sets.md) for more information on package sets. For each subdirectory, every file and directory within it specifies a package with the same name. E.g. `pythonPackages/myPkg/default.nix` defines the `myPkg` python package, accessible via the `pythonPackages.myPkg` attribute (among others). The following table specifies the properties of each supported subdirectory.

| Package set | Call scope attribute | Paths | Output attribute paths |
| --- | --- | --- | --- |
| Toplevel | - | `pkgs/<name>/default.nix` or `pkgs/<name>.nix` | `<name>` |
| Python | `pythonPackages` | `pythonPackages/<name>/default.nix` or `pythonPackages/<name>.nix` | `pythonPackages.<name>`, `python2Packages.<name>`, `python3Packages.<name>`, `python27Packages.<name>`, `python37Packages.<name>`, etc. |
| Perl | `perlPackages` | `perlPackages/<name>/default.nix` or `perlPackages/<name>.nix` | `perlPackages.<name>`, `perl530Packages.<name>`, `perl532Packages.<name>` |
| Haskell | `haskellPackages` | `haskellPackages/<name>/default.nix` or `haskellPackages/<name>.nix` | `haskellPackages.<name>`, `haskell.packages.ghc865.<name>`, `haskell.packages.ghc882.<name>`, etc. |
| Erlang | `beamPackages` | `beamPackages/<name>/default.nix` or `beamPackages/<name>.nix` | `beamPackages.<name>`, `beam.packages.erlangR18.<name>`, `beam.packages.erlangR19.<name>`, etc. |

### Shallow vs deep overriding

Packages declared with these files override/replace packages from nixpkgs for the current channel. But there's different ways in how packages are overridden:

- Shallow overriding (default): Can be used to define arbitrary package attributes, but if a nixpkgs package is overridden, the new version won't be used by reverse dependencies in nixpkgs. This allows reusing the precompiled atrifacts from the NixOS cache, but can cause version conflicts when both the nixpkgs version and the overridden flox version is used.
- Deep overriding (when empty `<set>/<name>/deep-override` file exists): Restricted to only package attributes that exist in nixpkgs already, but makes reverse dependencies in nixpkgs also use the overridden version. This allows easily resolving package conflicts that could occur if both the nixpkgs and overridden flox version is used. However, this also requires other channels that depend on your channel to give permission to override a nixpkgs, as it causes changes to all channels packages that include yours.

Here is a comparison table between the two

| Type | Shallow | Deep |
| --- | --- | --- |
| To enable | (enabled by default) | Create `<set>/<name>/deep-override` |
| Can use nixpkgs binary caches | Yes | No |
| Generally free of package conflicts | No | Yes |
| Can define non-nixpkgs attributes | Yes | No |
| Requires permission when another channel depends on yours | No | Yes |

In general, shallow overrides should be preferred, but deep overrides can be used if needed.

## Call scope

All paths in `*/<name>/default.nix` and `*/<name>.nix` are auto-called with a scope containing these attributes in increasing priority:
- All nixpkgs attributes
- All attributes from all transitive channels
- All attributes from this channel
- `<name>`: The package in nixpkgs of the same name as the one defined. This allows package overriding without getting infinite recursion. See [override conflicts](./conflicts.md#override-conflicts) for more info.
- `meta`: An attribute set containing some utility functions. See [meta set](#meta-set) for more info.
- `callPackage`: A function like `pkgs.callPackage` but with the very scope described here (except `<name>`). This allows autocalling further files.

In addition, for all package sets in [above table](#subdirectories) that have a call scope attribute `<attr>`, the following version-agnostic attributes are in scope as well. See [package sets](package-sets.md) for more info.
- `<attr>`: A version-agnostic package set consisting of:
  - The packages in nixpkgs
  - This channels packages
- All attributes of the above set

### Meta set

#### `getChannelSource <channel> <project> <overrides>`

Gets an auto-updating reference to GitHub repository `<project>` of the channel `<channel>` (aka the GitHub owner/organization), allowing certain overrides of behavior with the `<overrides>` argument.

##### Argument `<channel>` (string)

The channel/owner to get the source for.

##### Argument `<project>` (string)

The project/repository to get the source for.

##### Argument `<overrides>` (attribute set)

- `src` (string, default from GitHub): The path to the source, overrides the automatically updated source
- `rev` (string, default `"master"`): A Git hash or branch to use for the source when it is automatically updated
- `name` (string, default `${pname}-${version}`): The name of the derivation
- `pname` (string, default project name): The package name
- `version` (string, default from GitHub if no `src` passed, otherwise required): The version string to use for the source
- `versionSuffix` (string, default when automatically updated `"r-${releaseNumber}"`): Additional suffix to append to the resulting version. Should be increased over time
- `extraInfo` (attribute set, default `{}`): Arbitrary additional info about the source, will be passed to the resulting `infoJson`

##### Returns
An attribute set with attributes:
- `project` (string): The project passed with the `<project>` argument. Intended to be used as a passthru of the derivation such that the projects can be inferred from channel outputs
- `pname` (string): The package name, intended to be passed to nixpkgs builders
- `version` (version string): The package version, intended to be passed to nixpkgs builders
- `name` (string): `pname + "-" + version`, intended to be passed to nixpkgs builders that don't support `pname` and `version` separately
- `src` (path): The path to the resulting source
- `origversion` (version string): The original version as specified by the GitHub source or with `<overrides>`. This string may not uniquely identify a revision
- `createInfoJson` (bash command): A bash command that outputs most of above properties as a JSON string, used by builders to generate `.flox.json`. Note that:
  - `src` is not included
  - `system` is an additional property, currently referring to the eval time system, such as `x86_64-linux`
  - `buildDate` is a ISO8601 date string of the time that the derivation was built

#### `ownChannel`

The name of the own channel. May be `_unknown` in case the channel name couldn't be determined, see [channel name inference](./expl/name-inference.md).

#### `importingChannel`

The channel from which this channel is accessed. In case this channel is accessed from itself, this is the same as [`ownChannel`](#ownChannel).

#### `getSource <project> <overrides>`

Like [`getChannelSource`](#getChannelSource-channel-project-overrides), but with [`ownChannel`](#ownChannel) passed as the `<channel>` argument.

#### `trace <subsystem> <verbosity> <message> <arg>`

Traces `<message>` if the verbosity of `<subsystem>` is equal or higher than `<verbosity>`, as configured with the `debugVerbosity` and `subsystemVerbosity` CLI arguments.

See [the debugging document](./debugging.md#trace-function) for more details.

#### `mapDirectory <directory> { call? }`

Imports all Nix files and subdirectories of `<directory>`, importing them and turning them into Nix values by auto-calling them. This allows declaring local ad-hoc package sets. For example, with `pkgs/myPackages.nix` containing

```nix
{ meta }: meta.mapDirectory ../myPackages {}
```

any files in `myPackages` get turned into an attribute nested under the `myPackages` output attribute.

Note that unlike [built-in package](./package-sets.md) sets like `pythonPackages`, `perlPackages`, there's no special handling of scope and versions with `mapDirectory`. It's just a simple collection of nested attributes.

##### Argument `<directory>` (path)

The directory to import paths from.

##### Argument `<call>` (function)

The function to call on each path to transform it to a value. Defaults to `path: callPackage path {}`.

##### Returns

An attribute set containing attributes for every `<directory>/<name>.nix` file and every `<directory>/<name>` subdirectory, the files are turned to values with `<callPackage>`.

## `importNix { path, project, channel?, ... }` (experimental)

An experimental convenience function for deferring a package definition to a Nix file in the project repository itself.

##### Inputs
- `path` (string, mandatory): The relative Nix file path within `<project>` to use for defining this package. If this is a directory, its `default.nix` file will be used. This file is then treated as if it stood in for the `importNix` definition, getting access to the [same call scope](./channel-construction.md#call-scope).
- `project` (string, mandatory): The name of the GitHub repository in your organization to use for getting the Nix file source of this package. This is passed as the [`<project>` argument](./channel-construction.md#argument-project-string) to `meta.getChannelSource`.
- `channel` (string, optional, default [`meta.importingChannel`](./channel-construction.md#importingchannel)): The name of the channel, aka GitHub user/organization to get the `<project>` from. Defaults to the channel that uses/imports this builder. This is passed as the [`<channel>` argument](./channel-construction.md#argument-channel-string) to `meta.getChannelSource`.
- All other arguments are passed as the [`<overrides>` argument](./channel-construction.md#argument-overrides-attribute-set) to `meta.getChannelSource`. See [its documentation](channel-construction.md#getchannelsource-channel-project-overrides) for how the source can be influenced with this.

##### Returns
The result of the Nix file specified in the arguments, as if that file were in this ones place.

Assuming it uses a flox builder, it also contains the [common return attributes](./builders.md#common-return-attributes).
