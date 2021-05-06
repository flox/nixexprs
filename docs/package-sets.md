# Package sets

Package sets are collections of packages/libraries for a specific programming language. E.g. a python package set defines a set of python packages that can be used to build python applications. These packages are often specific to a certain version of the language, meaning there are different package sets for different versions.

Floxpkgs channels however support defining packages for version-agnostic package sets. Declaring such packages defines them for all supported package set versions at once. A version is only supported if nixpkgs supports it. In such version-agnostic package declarations, you need to make sure to use version-agnostic references to other packages in the same package set in order to avoid mixing versions.

See [package-sets.nix](../channel/package-sets.nix) to see how package sets are defined to support this, or to see how more package sets can be added.

## Version-agnostic references

Each package set has a call scope attribute `<attr>` as described in [here](channel-construction.md#topdir-subdirectories). As listed [here](channel-construction.md#call-scope), this `<attr>` gives access to version-agnostic package sets of nixpkgs, the current channel, and other channels. This notably only works within declarations of that package set.

### Example
As an example, the following file in `pythonPackages/myPkg/default.nix` defines a version-agnostic Python package using the Python package builder from the flox package, which depends on nixpkgs `pythonPackages.appdirs`, a dependency from this channel in `pythonPackages/myDep/default.nix`, and a dependency from another channel:
```nix
{ appdirs, myDep, channels, flox }:
flox.pythonPackages.buildPythonPackage {
  project = "myPkg";
  propagatedBuildInputs = [
    appdirs
    myDep
    channels.other.pythonPackages.otherPkg
  ];
}
```

The `pythonPackages` attribute used in the `./pythonPackages` subdirectory essentially means "The Python packages of whichever version this result is used for".

Whereas outside of `./pythonPackages`, the same attribute means "The Python packages of the default Python version (currently 2.x)"

## Outputs

A package declaration for a given package set is auto-called once with each supported version. Each resulting version is returned as a channel output at the same attribute path that nixpkgs uses.

### Example
Reusing above example, the package defined there will be accessible for different Python versions in the channel output:
- `pythonPackages.myPkg`
- `python2Packages.myPkg`
- `python3Packages.myPkg`
- `python27Packages.myPkg`
- `python36Packages.myPkg`
- `python37Packages.myPkg`
- `python38Packages.myPkg`
- `python39Packages.myPkg`
- `python310Packages.myPkg`
