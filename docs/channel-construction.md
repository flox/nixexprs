# Channel construction

Each channel needs to have a `default.nix` in its root that calls the `<flox/channel>` function to construct a channel, which allows the user to run `nix-build` to build outputs, Hydra to find all outputs, and other channels to use this channel as a dependency. The entrypoint of this function is in [`flox/channel/default.nix`](../channel/default.nix). It takes a set of arguments intended to be passed via a channels `default.nix` file. These are:

- `name` (string, default inferred): The name of the channel. If not specified, the name is inferred from a number of heuristics.
- `topdir` (path, required): The path to the channel root. Usually just `./.`, indicating that the channel lives in the same directory as the file importing `<flox/channel>`. This directory is used to determine all outputs of the channel. See below section for details.
- `extraOverlays` (list of nixpkgs overlays, default `[]`): Extra [nixpkgs overlays](https://nixos.org/manual/nixpkgs/stable/#sec-overlays-definition) to apply to the channel and its dependent channels.

The result of this function call is _another_ function, with arguments that all have default values. This allows evaluation of the channels `default.nix` via `nix-build -A`, but also allows customizing the arguments if necessary. This function has these arguments:

- `name` (string, default inferred): Another way to pass the name of the channel. If not specified, the name is inferred from a number of heuristics. If `name` is passed in the previous function call, that takes precedence over this one.
- `debugVerbosity` (integer, default 0): The level of debug information to display during evaluation. A value of 10 should display everything, while 0 should display nothing. Very useful for debugging infinite recursion errors. See [`withVerbosity`](#withverbosity-verbosity-fun-arg) for more details.
- `sourceOverrideJson` (JSON string, default `{}`): A JSON string for specifying source overrides of projects.
  This is of the form
  ```json
  {
    "<githubUser>" : {
      "<githubRepo>" : "/path/to/overridden/source"
    }
  }
  ```
- `_return` (internal, unstable): Internal return value of the channel creation. Used to implement dependencies on other channels
- `_isFloxChannel` (internal, unstable): Unused argument that hints that this is a Flox channel. This is used to discover Flox channels from `NIX_PATH`

The result of this function call are the channel outputs, as determined by mainly `topdir`. See below section for details.

## `topdir` subdirectories

The channel creation mechanism looks at a number of subdirectories of `topdir` to generate channel outputs from. Other than `pkgs`, all these subdirectories are determined by [`package-sets.nix`](../channel/package-sets.nix). See [here](./package-sets.md) for more information on package sets. For each subdirectory, every file and directory within it specifies a package with the same name. E.g. `pythonPackages/myPkg/default.nix` defines the `myPkg` python package, accessible via the `pythonPackages.myPkg` attribute (among others). The following table specifies the properties of each supported subdirectory.

| Package set | Call scope attribute | Paths | Output attribute paths |
| --- | --- | --- | --- |
| Toplevel | - | `pkgs/<name>/default.nix` or `pkgs/<name>.nix` | `<name>` |
| Python | `pythonPackages` | `pythonPackages/<name>/default.nix` or `pythonPackages/<name>.nix` | `pythonPackages.<name>`, `python2Packages.<name>`, `python3Packages.<name>`, `python27Packages.<name>`, `python37Packages.<name>`, etc. |
| Perl | `perlPackages` | `perlPackages/<name>/default.nix` or `perlPackages/<name>.nix` | `perlPackages.<name>`, `perl530Packages.<name>`, `perl532Packages.<name>` |
| Haskell | `haskellPackages` | `haskellPackages/<name>/default.nix` or `haskellPackages/<name>.nix` | `haskellPackages.<name>`, `haskell.packages.ghc865.<name>`, `haskell.packages.ghc882.<name>`, etc. |
| Erlang | `beamPackages` | `beamPackages/<name>/default.nix` or `beamPackages/<name>.nix` | `beamPackages.<name>`, `beam.packages.erlangR18.<name>`, `beam.packages.erlangR19.<name>`, etc. |

### Shallow vs deep overriding

Packages declared with these files override/replace packages from nixpkgs for the current channel. There's different ways in how packages are overridden:

- Shallow overriding: Only immediate dependencies of your channel are replaced, not transitive dependencies. This is the default.
- Deep overriding: Replaces dependencies transitively in all dependencies, including other channels. This can be enabled by creating an empty file in `<set>/<name>/deep-override`

Shallow overriding allows using mostly precompiled dependencies, while deep overriding could rebuild many layers of dependencies, so shallow overriding is cheaper to build. Deep overriding however resolves version conflicts caused by multiple versions of the same dependency in a closure.

Check out [this document](expl/deep-overrides.md) to learn more about how deep overriding works under the hood.

| Type | Shallow | Deep |
| --- | --- | --- |
| To enable | (enabled by default) | Create `<set>/<name>/deep-override` |
| Cheap to build | Yes | No |
| Free of package conflicts | No | Yes |

## Call scope

All paths in `*/<name>/default.nix` and `*/<name>.nix` are auto-called with a scope containing these attributes in increasing priority:
- All attributes of nixpkgs and its `xorg` set, so `pkgs.*` and `pkgs.xorg.*`
- All of this channels output attributes, merged into the above set
- `meta`: An attribute set containing some utility functions. See [meta set](#meta-set) for more info.
- `channels`: An attribute set containing the outputs of all other available channels:
  - `channels.<channel>.<output>`: Output attribute `<output>` of channel `<channel>`
- `flox`: A convenience alias to `channels.flox` for accessing the Flox channels outputs
- `<name>`: The package in nixpkgs of the same name as the one defined. This allows package overriding without getting infinite recursion
- `callPackage`: A function like `pkgs.callPackage` but with the very scope described here (except `<name>`). This allows autocalling further files.

In addition, for all package sets in [above table](#subdirectories) that have a call scope attribute `<attr>`, the following version-agnostic attributes are in scope as well. See [package sets](package-sets.md) for more info.
- `<attr>`: A version-agnostic package set consisting of:
  - The packages in nixpkgs
  - This channels packages
  - `<name>`: The package in nixpkgs of the same name as the one defined. This allows package overriding without getting infinite recursion
- All attributes of the above set
- `channels`: An attribute set containing the outputs of all other available channels:
  - `channels.<channel>.<output>`: Output attribute `<output>` of channel `<channel>`
  - `channels.<channel>.<attr>`: A version-agnostic package set for that channel

### Meta set

#### `getChannelSource <channel> <project> <overrides>`

Gets an auto-updating reference to GitHub repository `<project>` of the channel `<channel>` (aka the GitHub owner/organization), allowing certain overrides of behavior with the `<overrides>` argument.

##### Argument `<channel>` (string)

The channel/owner to get the source for.

##### Argument `<project>` (string)

The project/repository to get the source for.

##### Argument `<overrides>` (attribute set)

- `rev` (string, default `"master"`): A Git hash or branch to use for the source, only used if `src` is unset
- `src` (string, default from GitHub): The path to the source, overrides the one from GitHu
- `version` (string, default from GitHub if no `src` passed, otherwise required): The version string to use for the source
- `pname` (string, default project name): The package name
- `versionSuffix` (string, default `""`): Additional suffix to append to the resulting version. Should be increased over time
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

#### `withVerbosity <verbosity> <fun> <arg>`

Applies `<fun>` to `<arg>` only if the configured `debugVerbosity` is equal or higher than `<verbosity>`. With `<fun>` doing tracing, this allows controlling the verbosity level of the traced value. Example: `withVerbosity 5 (builtins.trace "Some message") 1`

##### Argument `<verbosity>` (integer)

The minimum verbosity level to trigger for. The verbosity levels are roughly meant for:
- 0: The default level, should only be used for warnings, so that normal evaluation doesn't trigger it
- 1-3: For debug messages that are infrequent, such that if the user sets `debugVerbosity` to one of these, only a handful of messages are printed
- 4-7: For debug messages that are somewhat more frequent
- 8-10: For debug messages that are very frequent, these can really litter the output

##### Argument `<fun>` (function)

The function to call on `<arg>` if `debugVerbosity` is above or equal to the passed `<verbosity>`. For static debug messages this is usually `builtins.trace "some static message"`. Messages can also depend on the `<arg>` to do more complicated outputs like `arg: builtins.trace "Argument is ${arg}" arg`.

##### Argument `<arg>` (anything)

The argument to pass to `<fun>` if `debugVerbosity` is above or equal to the passed `<verbosity>`. Otherwise this is the return value of the function.

##### Returns
- If `debugVerbosity` is greater or equal than `<verbosity>`, returns `<arg>` applied to `<fun>`
- Otherwise returns `<arg>`

#### `mapDirectory <callPackage> <directory>`

Imports all Nix files and subdirectories of `<directory>`, importing them and turning them into Nix values by calling `<callPackage>` on them. This allows declaring local ad-hoc package sets. For example, with `pkgs/myPackages.nix` containing

```nix
{ meta, callPackage }: meta.mapDirectory callPackage ../myPackages`
```

any files in `myPackages` get turned into an attribute nested under the `myPackages` output attribute.

Note that unlike [built-in package](./package-sets.md) sets like `pythonPackages`, `perlPackages`, there's no special handling of scope and versions with `mapDirectory`. It's just a simple collection of nested attributes.

##### Argument `<callPackage>` (function)

The `callPackage` function to use for autocalling the imported files.

##### Argument `<directory>` (path)

The directory to import paths from.

##### Returns

An attribute set containing attributes for every `<directory>/<name>.nix` file and every `<directory>/<name>` subdirectory, the files are turned to values with `<callPackage>`.
