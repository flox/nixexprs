# Call scope design

The call scope is the set of packages that are passed to the functions defined in the `<set>/<name>/default.nix` files. The exact contents of this set are described [here](../channel-construction.md#call-scope). This document gives some information on why this is designed the way it is.

There are a number of base requirements that the call scope is designed for:
- It should mirror nixpkgs as closely as possible, ideally allowing package definitions to be copy-pasted directly
- It needs to provide access to the packages of all dependent channels
- For package sets, it needs to be version-agnostic, so that packages can be defined for all supported versions with a single expression
- In case a package from nixpkgs is overridden, it needs to be possible to access the non-overridden package, such that only small modifications are possible
- It should minimize name clashes

Note that since channel package definitions are always auto-called, it's not possible to make any changes to the argument passing. This is in contrast to nixpkgs, where arbitrary changes can be made in e.g. `nixpkgs/pkgs/top-level/all-packages.nix`.

These requirements motivate the properties of the call scope:
- `pkgs.*` and `pkgs.xorg.*` are added since this is the default scope available to packages in nixpkgs, allowing most top-level package definitions to be copy-pasted directly
- A separate `channels` attribute is used for all channels, because channels can have arbitrary names. Other than nixpkgs potentially having a `channels` package, this ensures no name clashes. For convenience, `flox` is an alias to `channels.flox`.
- The name of the package itself is set to the non-overridden version of it, in order to allow overrides of the previous version.
- For package sets, the representative attribute name for that package set (such as `pythonPackages`, which is the same as the subdirectory name) is set to the correct version of the set. The same for `channels.<name>.pythonPackages`. This allows the expressions to be version-agnostic.
- For package sets, all of the package sets attributes are also added to the scope, because the same is done for all package set scopes in nixpkgs itself. This ensures that package set package definitions can by copy-pasted in most cases.

## A considered alternative

A straightforward simplification of the above is by using channel names themselves as the scope. So e.g. within channel `myChan` you could access a package from nixpkgs, your own channel, and another channel `otherChan` with

```nix
{ myChan, nixpkgs, otherChan }:
{ /* ... */ }
```

This is a very elegant solution that gets rid of name clashes and ambiguities. However:
- This wouldn't allow people to import packages from nixpkgs with copy-pasting
- Nixpkgs packages couldn't easily be overridden, since the dependency on either `nixpkgs` or `myChan` is explicit. This could be rectified by merging `myChan` into `nixpkgs`
- Depending on your own channels packages requires knowing its name. This could be rectified with a `self` alias to the current channel

