# Flox builders

| Builder | Intended for channel files | Underlying nixpkgs function |
| --- | --- | --- |
| [`mkDerivation`](#mkderivation) | `pkgs/<name>/default.nix` | [`stdenv.mkDerivation`](https://nixos.org/manual/nixpkgs/stable/#chap-stdenv) |
| [`pythonPackages.buildPythonPackage`](#pythonpackagesbuildpythonpackage) | `pythonPackages/<name>/default.nix` | [`pythonPackages.buildPythonPackage`](https://nixos.org/manual/nixpkgs/stable/#buildpythonpackage-function) |
| [`pythonPackage.buildPythonApplication`](#pythonpackagesbuildpythonapplication) | `pkgs/<name>/default.nix` | [`pythonPackages.buildPythonApplication`](https://nixos.org/manual/nixpkgs/stable/#buildpythonapplication-function) |
| [`perlPackages.buildPerlPackage`](#perlpackagesbuildperlpackage) | `perlPackages/<name>/default.nix` or `pkgs/<name>/default.nix` | [`perlPackages.buildPerlPackage`](https://nixos.org/manual/nixpkgs/stable/#ssec-perl-packaging) |
| [`buildGoModule`](#buildgomodule) | `pkgs/<name>/default.nix` | [`buildGoModule`](https://nixos.org/manual/nixpkgs/stable/#ssec-go-modules) |
| [`buildGoPackage`](#buildgopackage) | `pkgs/<name>/default.nix` | [`buildGoPackage`](https://nixos.org/manual/nixpkgs/stable/#ssec-go-legacy) |
| [`buildRustPackage`](#buildrustpackage) | `pkgs/<name>/default.nix` | [`rustPlatform.buildRustPackage`](https://nixos.org/manual/nixpkgs/stable/#compiling-rust-applications-with-cargo) |
| [`naersk.buildRustPackage`](#naerskbuildrustpackage) | `pkgs/<name>/default.nix` | N/A |
| [`haskellPackages.mkDerivation`](#haskellpackagesmkderivation) | `haskellPackages/<name>/default.nix` or `pkgs/<name>/default.nix` | [`haskellPackages.mkDerivation`](https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/haskell-modules/generic-builder.nix) |
| [`beamPackages.buildErlangMk`](#beampackagesbuilderlangmk) | `beamPackages/<name>/default.nix` or `pkgs/<name>/default.nix` | [`beamPackages.buildErlangMk`](https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/beam-modules/build-erlang-mk.nix) |

## Common return attributes

All builders return these attributes:
- `project`: The `project` given in the input attributes, this corresponds to the GitHub repository the package is built from. If no `project` is given, the underlying nixpkgs builder is called with all arguments.
- `_floxPath`: The path this package was constructed from. Either a Nix file directly, or a directory containing a `default.nix` file. This is useful for the `flox` tool to know how to edit the expression for a package.

## `mkDerivation`

[(source)](../pkgs/mkDerivation.nix)

Creates a package using nixpkgs standard environment builder. Use this for C/C++ projects.

**For files:** `pkgs/<name>/default.nix`

#### Inputs
- `project` (string, optional, nixpkgs builder called if not passed): The name of the GitHub repository in your organization to use as the source of this package. This is passed as the [`<project>` argument](./channel-construction.md#argument-project-string) to `meta.getChannelSource`.
- `channel` (string, optional, default [`meta.importingChannel`](./channel-construction.md#importingchannel)): The name of the channel, aka GitHub user/organization to get the `<project>` from. Defaults to the channel that uses/imports this builder. This is passed as the [`<channel>` argument](./channel-construction.md#argument-channel-string) to `meta.getChannelSource`.
The name of the GitHub repository in your organization to use as the source of this package. This is passed as the [`<project>` argument](./channel-construction.md#argument-project-string) to `meta.getChannelSource`.
- All other arguments are passed as the [`<overrides>` argument](./channel-construction.md#argument-overrides-attribute-set) to `meta.getChannelSource`. See [its documentation](channel-construction.md#getchannelsource-channel-project-overrides) for how the source can be influenced with this.
- All other arguments are also passed to nixpkgs `stdenv.mkDerivation` function. Refer to the [standard environment documentation](https://nixos.org/manual/nixpkgs/stable/#chap-stdenv) for more information. The most important arguments are:
  - `buildInputs` (list of packages, default `[]`): Package dependencies, e.g. dynamic libraries
  - `nativeBuildInputs` (list of packages, default `[]`): Build-time dependencies, such as e.g. `cmake` or `pkg-config`
  - `configurePhase` (string, default ~`./configure`): Command to run for configuring the package
  - `buildPhase` (string, default ~`make`): Command to run for building the package
  - `installPhase` (string, default ~`make install`): Command to run for installing the package

#### Returns
A derivation containing whatever was installed with the standard phases.

It also returns the [common return attributes](#common-return-attributes).

## `pythonPackages.buildPythonPackage`

[(source)](../pythonPackages/buildPythonPackage.nix)

Creates a Python package from an auto-updating reference to a repository.

**For files:** `pythonPackages/<name>/default.nix`

#### Inputs
- `project` (string, optional, nixpkgs builder called if not passed): The name of the GitHub repository in your organization to use as the source of this package. This is passed as the [`<project>` argument](./channel-construction.md#argument-project-string) to `meta.getChannelSource`.
- `channel` (string, optional, default [`meta.importingChannel`](./channel-construction.md#importingchannel)): The name of the channel, aka GitHub user/organization to get the `<project>` from. Defaults to the channel that uses/imports this builder. This is passed as the [`<channel>` argument](./channel-construction.md#argument-channel-string) to `meta.getChannelSource`.
- All other arguments are passed as the [`<overrides>` argument](./channel-construction.md#argument-overrides-attribute-set) to `meta.getChannelSource`. See [its documentation](channel-construction.md#getchannelsource-channel-project-overrides) for how the source can be influenced with this.
- All other arguments are also passed to nixpkgs `pythonPackages.buildPythonPackage` function. Refer to [its full documentation](https://nixos.org/manual/nixpkgs/stable/#buildpythonpackage-function) for more information. The most important arguments are:
  - `propagatedBuildInputs` (list of Python package derivations, default `[]`): Python runtime dependencies
  - `checkInputs` (list of Python package derivations, default `[]`): Python test dependencies

#### Returns
A derivation containing:
- A Python package suitable for use as a dependency of other Python packages
- All binaries or other outputs declared by the Python package, e.g. by `entry_points` in `setup.py`

It also returns the [common return attributes](#common-return-attributes).

#### Versions
Python packages declared with this function in `./pythonPackages` are version-agnostic. See [package sets](package-sets.md) for more info on version-agnostic definitions. This means:
- The channel result will contain this package for all supported Python versions
- The builder automatically uses the correct Python version

## `pythonPackages.buildPythonApplication`

[(source)](../pythonPackages/buildPythonApplication.nix)

Creates a Python application from an auto-updating reference to a repository. Note that this function doesn't return any Python modules, making in unfit for use in `pythonPackages/<name>/default.nix`.

**For files:** `pkgs/<name>/default.nix`

#### Inputs
See [`pythonPackages.buildPythonPackage`](#floxpythonpackagesbuildpythonpackage) for documentation of this functions arguments, they take exactly the same inputs. See nixpkgs [`pythonPackages.buildPythonApplication` documentation](https://nixos.org/manual/nixpkgs/stable/#buildpythonapplication-function) for more info on the difference between the two.

#### Returns
A derivation containing:
- All binaries or other outputs declared by the Python package, e.g. by `entry_points` in `setup.py`

It also returns the [common return attributes](#common-return-attributes).

#### Versions
- `pythonPackages.buildPythonApplication`: Uses the default Python version of nixpkgs (currently 2.x.x)
- `python2Packages.buildPythonApplication`: Uses the default Python 2 version of nixpkgs (currently 2.7.x)
- `python3Packages.buildPythonApplication`: Uses the default Python 3 version of nixpkgs (currently 3.8.x)
- In addition, specific minor Python versions supported by nixpkgs can be used, such as `python37Packages`, `python39Packages`, etc. However support for these might disappear over time.

## `perlPackages.buildPerlPackage`

[(source)](../perlPackages/buildPerlPackage.nix)

Creates a Perl package or application from an auto-updating reference to a repository.

**For files:** `perlPackages/<name>/default.nix` for packages or `pkgs/<name>/default.nix` for applications

#### Inputs
- `project` (string, optional, nixpkgs builder called if not passed): The name of the GitHub repository in your organization to use as the source of this package. This is passed as the [`<project>` argument](./channel-construction.md#argument-project-string) to `meta.getChannelSource`.
- `channel` (string, optional, default [`meta.importingChannel`](./channel-construction.md#importingchannel)): The name of the channel, aka GitHub user/organization to get the `<project>` from. Defaults to the channel that uses/imports this builder. This is passed as the [`<channel>` argument](./channel-construction.md#argument-channel-string) to `meta.getChannelSource`.
- All other arguments are passed as the [`<overrides>` argument](./channel-construction.md#argument-overrides-attribute-set) to `meta.getChannelSource`. See [its documentation](channel-construction.md#getchannelsource-channel-project-overrides) for how the source can be influenced with this.
- All other arguments are also passed to nixpkgs `perlPackages.buildPerlPackage` function. Refer to [nixpkgs Perl packaging documentation](https://nixos.org/manual/nixpkgs/stable/#ssec-perl-packaging) for more information. The most important arguments are:
  - `propagatedBuildInputs` (list of Perl package derivations, default `[]`): Perl dependencies

#### Returns
A derivation containing:
- A Perl package suitable for use as a dependency of other Perl packages
- All binaries or other outputs declared by the Perl package, e.g. by `install_script` in `Makefile.PL`

It also returns the [common return attributes](#common-return-attributes).

#### Versions
Perl packages declared with this function in `./perlPackages` are version-agnostic. See [package sets](package-sets.md) for more info on version-agnostic definitions. This means:
- The channel result will contain this package for all supported Perl versions
- The builder automatically uses the correct Perl version

Perl applications declared with this function in `./pkgs` can choose the version:
- `perlPackages.buildPerlPackage`: Uses the default Perl version of nixpkgs (currently 5.32.x)
- In addition, specific minor Perl versions supported by nixpkgs can be used, which currently includes `perl530Packages` and `perl532Packages`. However support for these might disappear over time.

## `buildGoModule`

[(source)](../pkgs/buildGoModule.nix)

Creates a Go application from an auto-updating reference to a repository using Go modules (having a `go.mod` file).

**For files:** `pkgs/<name>/default.nix`

#### Inputs
- `project` (string, optional, nixpkgs builder called if not passed): The name of the GitHub repository in your organization to use as the source of this package. This is passed as the [`<project>` argument](./channel-construction.md#argument-project-string) to `meta.getChannelSource`.
  - The project version can be accessed from Go code by adding the following to the `main` package:
    ```go
    var nixVersion string
    ```
- `channel` (string, optional, default [`meta.importingChannel`](./channel-construction.md#importingchannel)): The name of the channel, aka GitHub user/organization to get the `<project>` from. Defaults to the channel that uses/imports this builder. This is passed as the [`<channel>` argument](./channel-construction.md#argument-channel-string) to `meta.getChannelSource`.
- All other arguments are passed as the [`<overrides>` argument](./channel-construction.md#argument-overrides-attribute-set) to `meta.getChannelSource`. See [its documentation](channel-construction.md#getchannelsource-channel-project-overrides) for how the source can be influenced with this.
- All other arguments are also passed to nixpkgs `buildGoModule` function. Refer to [its documentation](https://nixos.org/manual/nixpkgs/stable/#ssec-go-modules) for more information. The most important arguments are:
  - `vendorSha256` (string or null, mandatory): The hash of all the dependencies, or `null` if the package vendors dependencies. Since this hash is not known beforehand, a fake hash like `lib.fakeSha256` must be used at first to get the correct hash with the first failing build.

#### Returns
A derivation containing:
- The binaries declared by the Go package

It also returns the [common return attributes](#common-return-attributes).

#### Versions
This function is only available for the default Go version of nixpkgs `buildGoModule` function, which is currently Go 1.15.x

## `buildGoPackage`

[(source)](../pkgs/buildGoPackage.nix)

Creates a Go application from an auto-updating reference to a repository. Can be used for both projects using Go modules and ones that don't.

**For files:** `pkgs/<name>/default.nix`

#### Inputs
- `project` (string, optional, nixpkgs builder called if not passed): The name of the GitHub repository in your organization to use as the source of this package. This is passed as the [`<project>` argument](./channel-construction.md#argument-project-string) to `meta.getChannelSource`.
  - The project version can be accessed from Go code by adding the following to the `main` package:
    ```go
    var nixVersion string
    ```
- `channel` (string, optional, default [`meta.importingChannel`](./channel-construction.md#importingchannel)): The name of the channel, aka GitHub user/organization to get the `<project>` from. Defaults to the channel that uses/imports this builder. This is passed as the [`<channel>` argument](./channel-construction.md#argument-channel-string) to `meta.getChannelSource`.
- All other arguments are passed as the [`<overrides>` argument](./channel-construction.md#argument-overrides-attribute-set) to `meta.getChannelSource`. See [its documentation](channel-construction.md#getchannelsource-channel-project-overrides) for how the source can be influenced with this.
- All other arguments are also passed to nixpkgs `buildGoPackage` function. Refer to [its documentation](https://nixos.org/manual/nixpkgs/stable/#ssec-go-legacy) for more information. The most important arguments are:
  - `goPackagePath` (string, mandatory): The package's canonical Go import path.
  - `goDeps` (path, mandatory): Path to `deps.nix` file containing package dependencies. For a project using Go modules, this can be generated with [vgo2nix](https://github.com/nix-community/vgo2nix), for other projects [go2nix](https://github.com/kamilchm/go2nix) can be used.

#### Returns
A derivation containing:
- The binaries declared by the Go package

It also returns the [common return attributes](#common-return-attributes).

#### Versions
This function is only available for the default Go version of nixpkgs `buildGoPackage` function, which is currently Go 1.15.x

## `buildRustPackage`

[(source)](../pkgs/buildRustPackage.nix)

Creates a Rust application from an auto-updating reference to a repository.

**For files:** `pkgs/<name>/default.nix`

#### Inputs
- `project` (string, optional, nixpkgs builder called if not passed): The name of the GitHub repository in your organization to use as the source of this package. This is passed as the [`<project>` argument](./channel-construction.md#argument-project-string) to `meta.getChannelSource`.
- `channel` (string, optional, default [`meta.importingChannel`](./channel-construction.md#importingchannel)): The name of the channel, aka GitHub user/organization to get the `<project>` from. Defaults to the channel that uses/imports this builder. This is passed as the [`<channel>` argument](./channel-construction.md#argument-channel-string) to `meta.getChannelSource`.
- All other arguments are passed as the [`<overrides>` argument](./channel-construction.md#argument-overrides-attribute-set) to `meta.getChannelSource`. See [its documentation](channel-construction.md#getchannelsource-channel-project-overrides) for how the source can be influenced with this.
- All other arguments are also passed to nixpkgs `rustPlatform.buildRustPackage` function. Refer to [its documentation](https://nixos.org/manual/nixpkgs/stable/#compiling-rust-applications-with-cargo) for more information. One of the following arguments is needed for specifying the dependencies:
  - `cargoSha256` (string): The hash of all dependencies. Since this hash is not known beforehand, a fake hash like `lib.fakeSha256` must be used at first to get the correct hash with the first failing build.
  - `cargoVendorDir` (path): An alternative to `cargoSha256`, which can be used if dependencies are vendored with `cargo vendor`. Pass the path to the `vendor` directory with this option.

#### Returns
A derivation containing:
- The binaries declared by the Rust package

It also returns the [common return attributes](#common-return-attributes).

#### Versions
This function is only available for the default Rust version of nixpkgs, which is currently Rust 1.46.x

## `naersk.buildRustPackage`

[(source)](../pkgs/naersk/buildRustPackage.nix)

Creates a Rust application from an auto-updating reference to a repository. Similar to [buildRustPackage](#buildrustpackage) but built using the third-party [naersk](https://github.com/nmattia/naersk) tool.

**For files:** `pkgs/<name>/default.nix`

#### Inputs
- `project` (string, mandatory): The name of the GitHub repository in your organization to use as the source of this package. This is passed as the [`<project>` argument](./channel-construction.md#argument-project-string) to `meta.getChannelSource`.
- `channel` (string, optional, default [`meta.importingChannel`](./channel-construction.md#importingchannel)): The name of the channel, aka GitHub user/organization to get the `<project>` from. Defaults to the channel that uses/imports this builder. This is passed as the [`<channel>` argument](./channel-construction.md#argument-channel-string) to `meta.getChannelSource`.
- All other arguments are passed as the [`<overrides>` argument](./channel-construction.md#argument-overrides-attribute-set) to `meta.getChannelSource`. See [its documentation](channel-construction.md#getchannelsource-channel-project-overrides) for how the source can be influenced with this.
- All other arguments are also passed to naersk. Refer to [its documentation](https://github.com/nmattia/naersk#configuration) for more information.

Notice the lack of a mandatory `cargoSha256`-like argument. This is because naersk extracts the hash from your Cargo.lock file.

#### Returns
A derivation containing:
- The binaries declared by the Rust package

It also returns the [common return attributes](#common-return-attributes).

#### Versions
This function is only available for the default Rust version of nixpkgs, which is currently Rust 1.46.x

## `haskellPackages.mkDerivation`

[(source)](../haskellPackages/mkDerivation.nix)

Creates a Haskell package or application from an auto-updating reference to a repository.

**For files:** `haskellPackages/<name>/default.nix` for packages or `pkgs/<name>/default.nix` for applications

#### Inputs
- `project` (string, optional, nixpkgs builder called if not passed): The name of the GitHub repository in your organization to use as the source of this package. This is passed as the [`<project>` argument](./channel-construction.md#argument-project-string) to `meta.getChannelSource`.
- `channel` (string, optional, default [`meta.importingChannel`](./channel-construction.md#importingchannel)): The name of the channel, aka GitHub user/organization to get the `<project>` from. Defaults to the channel that uses/imports this builder. This is passed as the [`<channel>` argument](./channel-construction.md#argument-channel-string) to `meta.getChannelSource`.
- All other arguments are passed as the [`<overrides>` argument](./channel-construction.md#argument-overrides-attribute-set) to `meta.getChannelSource`. See [its documentation](channel-construction.md#getchannelsource-channel-project-overrides) for how the source can be influenced with this.
- All other arguments are also passed to nixpkgs `haskellPackages.mkDerivation` function. Refer to [its source](https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/haskell-modules/generic-builder.nix) for more information. The most important arguments are:
  - `isExecutable` (boolean, default `false`): Turn this on if the package is an application and lives in `pkgs/<name>/default.nix`.
  - `buildDepends` (list of Haskell packages, default `[]`): The dependencies of this package

#### Returns
A derivation containing:
- A Haskell package suitable for use as a dependency of other Haskell packages
- If `isExecutable = true`, all binaries specified by the Haskell package

It also returns the [common return attributes](#common-return-attributes).

#### Versions
Haskell packages declared with this function in `./haskellPackages` are version-agnostic. See [package sets](package-sets.md) for more info on version-agnostic definitions. This means:
- The channel result will contain this package for all supported Haskell versions
- The builder automatically uses the correct Haskell version

Haskell applications declared with this function in `./pkgs` can choose the version:
- `haskellPackages.mkDerivation`: Uses the default Haskell version of nixpkgs (currently Haskell GHC 8.8.x)
- `haskell.packages.ghcXXX.mkDerivation`: Uses GHC version XXX, e.g. `ghc865` for GHC 8.6.5 or `ghc882` for GHC 8.8.2. Only versions available in nixpkgs are supported, and this will change over time.

## `beamPackages.buildErlangMk`

[(source)](../beamPackages/buildErlangMk.nix)

Creates an Erlang package or application from an auto-updating reference to a repository.

**For files:** `beamPackages/<name>/default.nix` for packages or `pkgs/<name>/default.nix` for applications

#### Inputs
- `project` (string, optional, nixpkgs builder called if not passed): The name of the GitHub repository in your organization to use as the source of this package. This is passed as the [`<project>` argument](./channel-construction.md#argument-project-string) to `meta.getChannelSource`.
- `channel` (string, optional, default [`meta.importingChannel`](./channel-construction.md#importingchannel)): The name of the channel, aka GitHub user/organization to get the `<project>` from. Defaults to the channel that uses/imports this builder. This is passed as the [`<channel>` argument](./channel-construction.md#argument-channel-string) to `meta.getChannelSource`.
- All other arguments are passed as the [`<overrides>` argument](./channel-construction.md#argument-overrides-attribute-set) to `meta.getChannelSource`. See [its documentation](channel-construction.md#getchannelsource-channel-project-overrides) for how the source can be influenced with this.
- All other arguments are also passed to nixpkgs `beamPackages.buildErlangMk` function. Refer to [its source](https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/beam-modules/build-erlang-mk.nix) for more information. The most important arguments are:
  - `beamDeps` (list of beam packages, default `[]`): The Erlang dependencies of this package

#### Returns
A derivation containing:
- An Erlang package suitable for use as a dependency of other Erlang packages
- All binaries specified by the Erlang package

It also returns the [common return attributes](#common-return-attributes).

#### Versions
Erlang packages declared with this function in `./beamPackages` are version-agnostic. See [package sets](package-sets.md) for more info on version-agnostic definitions. This means:
- The channel result will contain this package for all supported Erlang versions
- The builder automatically uses the correct Erlang version

Erlang applications declared with this function in `./pkgs` can choose the version:
- `beamPackages.buildErlangMk`: Uses the default Erlang version of nixpkgs (currently Erlang 22.3)
- `beam.packages.erlangRXX.mkDerivation`: Uses Erlang version XX, e.g. `erlangR18` for Erlang 18.x or `erlangR23` for Erlang 23.x. Only versions available in nixpkgs are supported, and this will change over time.
