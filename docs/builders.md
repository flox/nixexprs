# Flox builders

| Builder | Intended for channel files | Underlying nixpkgs function |
| --- | --- | --- |
| [`flox.mkDerivation`](#floxmkderivation) | `pkgs/<name>/default.nix` | [`stdenv.mkDerivation`](https://nixos.org/manual/nixpkgs/stable/#chap-stdenv) |
| [`flox.pythonPackages.buildPythonPackage`](#floxpythonpackagesbuildpythonpackage) | `pythonPackages/<name>/default.nix` | [`pythonPackages.buildPythonPackage`](https://nixos.org/manual/nixpkgs/stable/#buildpythonpackage-function) |
| [`flox.pythonPackage.buildPythonApplication`](#floxpythonpackagesbuildpythonapplication) | `pkgs/<name>/default.nix` | [`pythonPackages.buildPythonApplication`](https://nixos.org/manual/nixpkgs/stable/#buildpythonapplication-function) |
| [`flox.perlPackages.buildPerlPackage`](#floxperlpackagesbuildperlpackage) | `perlPackages/<name>/default.nix` or `pkgs/<name>/default.nix` | [`perlPackages.buildPerlPackage`](https://nixos.org/manual/nixpkgs/stable/#ssec-perl-packaging) |
| [`flox.buildGoModule`](#floxbuildgomodule) | `pkgs/<name>/default.nix` | [`buildGoModule`](https://nixos.org/manual/nixpkgs/stable/#ssec-go-modules) |
| [`flox.buildGoPackage`](#floxbuildgopackage) | `pkgs/<name>/default.nix` | [`buildGoPackage`](https://nixos.org/manual/nixpkgs/stable/#ssec-go-legacy) |
| [`flox.buildRustPackage`](#floxbuildrustpackage) | `pkgs/<name>/default.nix` | [`rustPlatform.buildRustPackage`](https://nixos.org/manual/nixpkgs/stable/#compiling-rust-applications-with-cargo) |
| [`flox.haskellPackages.mkDerivation`](#floxhaskellpackagesmkderivation) | `haskellPackages/<name>/default.nix` or `pkgs/<name>/default.nix` | [`haskellPackages.mkDerivation`](https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/haskell-modules/generic-builder.nix) |
| [`flox.beamPackages.buildErlangMk`](#floxbeampackagesbuilderlangmk) | `beamPackages/<name>/default.nix` or `pkgs/<name>/default.nix` | [`beamPackages.buildErlangMk`](https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/beam-modules/build-erlang-mk.nix) |

## `flox.mkDerivation`

Creates a package using nixpkgs standard environment builder. Use this for C/C++ projects.

**For files:** `pkgs/<name>/default.nix`

#### Inputs
- `project` (string, mandatory): The name of the GitHub repository in your organization to use as the source of this package. This is passed as the first argument to `meta.getSource`.
- All other arguments are passed as the second argument to `meta.getSource`. See [its documentation](channel-construction.md#getsource-project-overrides) for how the source can be influenced with this.
- All other arguments are also passed to nixpkgs `stdenv.mkDerivation` function. Refer to the [standard environment documentation](https://nixos.org/manual/nixpkgs/stable/#chap-stdenv) for more information. The most important arguments are:
  - `buildInputs` (list of packages, default `[]`): Package dependencies, e.g. dynamic libraries
  - `nativeBuildInputs` (list of packages, default `[]`): Build-time dependencies, such as e.g. `cmake` or `pkg-config`
  - `configurePhase` (string, default ~`./configure`): Command to run for configuring the package
  - `buildPhase` (string, default ~`make`): Command to run for building the package
  - `installPhase` (string, default ~`make install`): Command to run for installing the package

#### Returns
A derivation containing whatever was installed with the standard phases

## `flox.pythonPackages.buildPythonPackage`

Creates a Python package from an auto-updating reference to a repository.

**For files:** `pythonPackages/<name>/default.nix`

#### Inputs
- `project` (string, mandatory): The name of the GitHub repository in your organization to use as the source of this Python package. This is passed as the first argument to `meta.getSource`.
- All other arguments are passed as the second argument to `meta.getSource`. See [its documentation](channel-construction.md#getsource-project-overrides) for how the source can be influenced with this.
- All other arguments are also passed to nixpkgs `pythonPackages.buildPythonPackage` function. Refer to [its full documentation](https://nixos.org/manual/nixpkgs/stable/#buildpythonpackage-function) for more information. The most important arguments are:
  - `propagatedBuildInputs` (list of Python package derivations, default `[]`): Python runtime dependencies
  - `checkInputs` (list of Python package derivations, default `[]`): Python test dependencies

#### Returns
A derivation containing:
- A Python package suitable for use as a dependency of other Python packages
- All binaries or other outputs declared by the Python package, e.g. by `entry_points` in `setup.py`

#### Versions
Python packages declared with this function in `./pythonPackages` are version-agnostic. See [version agnosticism](version-agnosticism.md) for more info on version-agnostic definitions. This means:
- The channel result will contain this package for all supported Python versions
- The builder automatically uses the correct Python version

## `flox.pythonPackages.buildPythonApplication`

Creates a Python application from an auto-updating reference to a repository. Note that this function doesn't return any Python modules, making in unfit for use in `pythonPackages/<name>/default.nix`.

**For files:** `pkgs/<name>/default.nix`

#### Inputs
See [`flox.pythonPackages.buildPythonPackage`](#floxpythonpackagesbuildpythonpackage) for documentation of this functions arguments, they take exactly the same inputs. See nixpkgs [`pythonPackages.buildPythonApplication` documentation](https://nixos.org/manual/nixpkgs/stable/#buildpythonapplication-function) for more info on the difference between the two.

#### Returns
A derivation containing:
- All binaries or other outputs declared by the Python package, e.g. by `entry_points` in `setup.py`

#### Versions
- `flox.pythonPackages.buildPythonApplication`: Uses the default Python version of nixpkgs (currently 2.x.x)
- `flox.python2Packages.buildPythonApplication`: Uses the default Python 2 version of nixpkgs (currently 2.7.x)
- `flox.python3Packages.buildPythonApplication`: Uses the default Python 3 version of nixpkgs (currently 3.8.x)
- In addition, specific minor Python versions supported by nixpkgs can be used, such as `python37Packages`, `python39Packages`, etc. However support for these might disappear over time.

## `flox.perlPackages.buildPerlPackage`

Creates a Perl package or application from an auto-updating reference to a repository.

**For files:** `perlPackages/<name>/default.nix` for packages or `pkgs/<name>/default.nix` for applications

#### Inputs
- `project` (string, mandatory): The name of the GitHub repository in your organization to use as the source of this Perl package. This is passed as the first argument to `meta.getSource`.
- All other arguments are passed as the second argument to `meta.getSource`. See [its documentation](channel-construction.md#getsource-project-overrides) for how the source can be influenced with this.
- All other arguments are also passed to nixpkgs `perlPackages.buildPerlPackage` function. Refer to [nixpkgs Perl packaging documentation](https://nixos.org/manual/nixpkgs/stable/#ssec-perl-packaging) for more information. The most important arguments are:
  - `propagatedBuildInputs` (list of Perl package derivations, default `[]`): Perl dependencies

#### Returns
A derivation containing:
- A Perl package suitable for use as a dependency of other Perl packages
- All binaries or other outputs declared by the Perl package, e.g. by `install_script` in `Makefile.PL`

#### Versions
Perl packages declared with this function in `./perlPackages` are version-agnostic. See [version agnosticism](version-agnosticism.md) for more info on version-agnostic definitions. This means:
- The channel result will contain this package for all supported Perl versions
- The builder automatically uses the correct Perl version

Perl applications declared with this function in `./pkgs` can choose the version:
- `flox.perlPackages.buildPerlPackage`: Uses the default Perl version of nixpkgs (currently 5.32.x)
- In addition, specific minor Perl versions supported by nixpkgs can be used, which currently includes `perl530Packages` and `perl532Packages`. However support for these might disappear over time.

## `flox.buildGoModule`

Creates a Go application from an auto-updating reference to a repository using Go modules (having a `go.mod` file).

**For files:** `pkgs/<name>/default.nix`

#### Inputs
- `project` (string, mandatory): The name of the GitHub repository in your organization to use as the source of this Go application. This is passed as the first argument to `meta.getSource`.
- All other arguments are passed as the second argument to `meta.getSource`. See [its documentation](channel-construction.md#getsource-project-overrides) for how the source can be influenced with this.
- All other arguments are also passed to nixpkgs `buildGoModule` function. Refer to [its documentation](https://nixos.org/manual/nixpkgs/stable/#ssec-go-modules) for more information. The most important arguments are:
  - `vendorSha256` (string or null, mandatory): The hash of all the dependencies, or `null` if the package vendors dependencies. Since this hash is not known beforehand, a fake hash like `lib.fakeSha256` must be used at first to get the correct hash with the first failing build.

#### Returns
A derivation containing:
- The binaries declared by the Go package

#### Versions
This function is only available for the default Go version of nixpkgs `buildGoModule` function, which is currently Go 1.15.x

## `flox.buildGoPackage`

Creates a Go application from an auto-updating reference to a repository. Can be used for both projects using Go modules and ones that don't.

**For files:** `pkgs/<name>/default.nix`

#### Inputs
- `project` (string, mandatory): The name of the GitHub repository in your organization to use as the source of this Go application. This is passed as the first argument to `meta.getSource`.
- All other arguments are passed as the second argument to `meta.getSource`. See [its documentation](channel-construction.md#getsource-project-overrides) for how the source can be influenced with this.
- All other arguments are also passed to nixpkgs `buildGoPackage` function. Refer to [its documentation](https://nixos.org/manual/nixpkgs/stable/#ssec-go-legacy) for more information. The most important arguments are:
  - `goPackagePath` (string, mandatory): The package's canonical Go import path.
  - `goDeps` (path, mandatory): Path to `deps.nix` file containing package dependencies. For a project using Go modules, this can be generated with [vgo2nix](https://github.com/nix-community/vgo2nix), for other projects [go2nix](https://github.com/kamilchm/go2nix) can be used.

#### Returns
A derivation containing:
- The binaries declared by the Go package

#### Versions
This function is only available for the default Go version of nixpkgs `buildGoPackage` function, which is currently Go 1.15.x

## `flox.buildRustPackage`

Creates a Rust application from an auto-updating reference to a repository.

**For files:** `pkgs/<name>/default.nix`

#### Inputs
- `project` (string, mandatory): The name of the GitHub repository in your organization to use as the source of this Rust application. This is passed as the first argument to `meta.getSource`.
- All other arguments are passed as the second argument to `meta.getSource`. See [its documentation](channel-construction.md#getsource-project-overrides) for how the source can be influenced with this.
- All other arguments are also passed to nixpkgs `rustPlatform.buildRustPackage` function. Refer to [its documentation](https://nixos.org/manual/nixpkgs/stable/#compiling-rust-applications-with-cargo) for more information. One of the following arguments is needed for specifying the dependencies:
  - `cargoSha256` (string): The hash of all dependencies. Since this hash is not known beforehand, a fake hash like `lib.fakeSha256` must be used at first to get the correct hash with the first failing build.
  - `cargoVendorDir` (path): An alternative to `cargoSha256`, which can be used if dependencies are vendored with `cargo vendor`. Pass the path to the `vendor` directory with this option.

#### Returns
A derivation containing:
- The binaries declared by the Rust package

#### Versions
This function is only available for the default Rust version of nixpkgs, which is currently Rust 1.46.x

## `flox.haskellPackages.mkDerivation`

Creates a Haskell package or application from an auto-updating reference to a repository.

**For files:** `haskellPackages/<name>/default.nix` for packages or `pkgs/<name>/default.nix` for applications

#### Inputs
- `project` (string, mandatory): The name of the GitHub repository in your organization to use as the source of this Haskell package. This is passed as the first argument to `meta.getSource`.
- All other arguments are passed as the second argument to `meta.getSource`. See [its documentation](channel-construction.md#getsource-project-overrides) for how the source can be influenced with this.
- All other arguments are also passed to nixpkgs `haskellPackages.mkDerivation` function. Refer to [its source](https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/haskell-modules/generic-builder.nix) for more information. The most important arguments are:
  - `isExecutable` (boolean, default `false`): Turn this on if the package is an application and lives in `pkgs/<name>/default.nix`.
  - `buildDepends` (list of Haskell packages, default `[]`): The dependencies of this package

#### Returns
A derivation containing:
- A Haskell package suitable for use as a dependency of other Haskell packages
- If `isExecutable = true`, all binaries specified by the Haskell package

#### Versions
Haskell packages declared with this function in `./haskellPackages` are version-agnostic. See [version agnosticism](version-agnosticism.md) for more info on version-agnostic definitions. This means:
- The channel result will contain this package for all supported Haskell versions
- The builder automatically uses the correct Haskell version

Haskell applications declared with this function in `./pkgs` can choose the version:
- `flox.haskellPackages.mkDerivation`: Uses the default Haskell version of nixpkgs (currently Haskell GHC 8.8.x)
- `flox.haskell.packages.ghcXXX.mkDerivation`: Uses GHC version XXX, e.g. `ghc865` for GHC 8.6.5 or `ghc882` for GHC 8.8.2. Only versions available in nixpkgs are supported, and this will change over time.

## `flox.beamPackages.buildErlangMk`

Creates an Erlang package or application from an auto-updating reference to a repository.

**For files:** `beamPackages/<name>/default.nix` for packages or `pkgs/<name>/default.nix` for applications

#### Inputs
- `project` (string, mandatory): The name of the GitHub repository in your organization to use as the source of this Erlang package. This is passed as the first argument to `meta.getSource`.
- All other arguments are passed as the second argument to `meta.getSource`. See [its documentation](channel-construction.md#getsource-project-overrides) for how the source can be influenced with this.
- All other arguments are also passed to nixpkgs `beamPackages.buildErlangMk` function. Refer to [its source](https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/beam-modules/build-erlang-mk.nix) for more information. The most important arguments are:
  - `beamDeps` (list of beam packages, default `[]`): The Erlang dependencies of this package

#### Returns
A derivation containing:
- An Erlang package suitable for use as a dependency of other Erlang packages
- All binaries specified by the Erlang package

#### Versions
Erlang packages declared with this function in `./beamPackages` are version-agnostic. See [version agnosticism](version-agnosticism.md) for more info on version-agnostic definitions. This means:
- The channel result will contain this package for all supported Erlang versions
- The builder automatically uses the correct Erlang version

Erlang applications declared with this function in `./pkgs` can choose the version:
- `flox.beamPackages.buildErlangMk`: Uses the default Erlang version of nixpkgs (currently Erlang 22.3)
- `flox.beam.packages.erlangRXX.mkDerivation`: Uses Erlang version XX, e.g. `erlangR18` for Erlang 18.x or `erlangR23` for Erlang 23.x. Only versions available in nixpkgs are supported, and this will change over time.
