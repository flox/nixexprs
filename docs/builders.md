# Flox builders

## `flox.pythonPackages.buildPythonPackage`

Creates a python package from an auto-updating reference to a repository. This function is intended to be used for the definitions of a channels `./pythonPackages/<name>/default.nix` files.

Input arguments:
- `project` (string, mandatory): The name of the GitHub repository in your organization to use as the source of this python package.
- All other arguments are passed to `pythonPackages.buildPythonPackage`. Refer to [its full documentation](https://nixos.org/manual/nixpkgs/stable/#buildpythonpackage-function) for more information. The most important arguments are:
  - `propagatedBuildInputs` (list of python package derivations, default `[]`): Python runtime dependencies
  - `checkInputs` (list of python package derivations, default `[]`): Python test dependencies

Returns a derivation containing:
- A python package suitable for use as a dependency of other python packages
- All binaries declared by the python package, e.g. by `entry_points` in `setup.py`

## `flox.pythonPackages.buildPythonApplication`

Creates a python application from an auto-updating reference to a repository. Because this function doesn't return any python modules, it is intended to be used for the definition of a channels `./pkgs/<name>/default.nix` files.

See [`flox.pythonPackages.buildPythonPackage`](#floxpythonpackagesbuildpythonpackage) for documentation of this functions arguments.

Returns a derivation containing:
- All binaries declared by the python package, e.g. by `entry_points` in `setup.py`
