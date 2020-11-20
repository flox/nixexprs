# Flox builders

## `flox.pythonPackages.buildPythonPackage`

Creates a Python package from an auto-updating reference to a repository. This function is intended to be used for the definitions of a channels `./pythonPackages/<name>/default.nix` files.

#### Inputs
- `project` (string, mandatory): The name of the GitHub repository in your organization to use as the source of this Python package.
- All other arguments are passed to `pythonPackages.buildPythonPackage`. Refer to [its full documentation](https://nixos.org/manual/nixpkgs/stable/#buildpythonpackage-function) for more information. The most important arguments are:
  - `propagatedBuildInputs` (list of Python package derivations, default `[]`): Python runtime dependencies
  - `checkInputs` (list of Python package derivations, default `[]`): Python test dependencies

#### Returns
A derivation containing:
- A Python package suitable for use as a dependency of other Python packages
- All binaries or other outputs declared by the Python package, e.g. by `entry_points` in `setup.py`

#### Versions
Python packages declared with this function in `./pythonPackages` are version-agnostic. See TODO for more info on version-agnostic definitions. This means:
- The channel result will contain this package for all supported Python versions
- The builder automatically uses the correct Python version

## `flox.pythonPackages.buildPythonApplication`

Creates a Python application from an auto-updating reference to a repository. Because this function doesn't return any Python modules, it is intended to be used for the definition of a channels `./pkgs/<name>/default.nix` files.

#### Inputs
See [`flox.pythonPackages.buildPythonPackage`](#floxpythonpackagesbuildpythonpackage) for documentation of this functions arguments, they take exactly the same inputs. See nixpkgs [`pythonPackages.buildPythonApplication` documentation](https://nixos.org/manual/nixpkgs/stable/#buildpythonapplication-function) for more info on the difference between the two.

#### Returns
A derivation containing:
- All binaries or other outputs declared by the Python package, e.g. by `entry_points` in `setup.py`

#### Versions
- `flox.pythonPackages.buildPythonApplication`: Uses the default Python version of nixpkgs (currently 2.x.x)
- `flox.python2Packages.buildPythonApplication`: Uses the default Python 2 version of nixpkgs (currently 2.7.x)
- `flox.python3Packages.buildPythonApplication`: Uses the default Python 3 version of nixpkgs (currently 3.8.x)

In addition, specific minor Python versions supported by nixpkgs can be used, such as `python37Packages`, `python39Packages`, etc. However support for these might disappear over time.
