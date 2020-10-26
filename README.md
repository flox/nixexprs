nixexprs repo
=============

Contains nix expressions for packages found in the gitlab/gitserve group
of the same name. Automatically maintained by flox.

## Design

This section describes the design of this repository, in a tutorial-like style.

### How nixpkgs works

At the core, nixpkgs is a function declared like

```nix
{
  nixpkgsFun = self: {
    ncurses = derivation {
      name = "ncurses";
      src = self.fetchurl { /* ... */ };
      # ...
    };
    tmatrix = derivation {
      src = self.fetchurl { /* ... */ };
      buildInputs = [
        self.ncurses
      ];
      # ...
    };
    # ...
  };
}
```

This is a function that takes a package set `self` as input, and returns a package set that depends on packages from `self`. Now since Nix is lazy, we can pass the result of this function to itself:

```nix
let
  nixpkgsFun = self: { /* ... */ };
  self = nixpkgsFun self;
in self
```

This allows us to have a single namespace of packages that can depend on other packages from the same namespace.

### How nixpkgs overlays work

Now if you want to override some package in this package set, an overlay can be used. E.g. for changing the ncurses package, an overlay might look like
```nix
{
  overlay =
    # The final package set, after all overlays have been applied. Use this for dependencies
    self:
    # The package set before this overlay is applied, for things that should be overridden
    super: {
      ncurses = derivation {
        # Take ncurses from super, since we're overriding it (otherwise we get infinite recursion)
        name = super.ncurses.name + "-unstable";
        # Take fetchurl from self, such that further overlays can change fetchurl while still affecting the ncurses package
        src = self.fetchurl { /* ... */ };
      };
    };
}
```

Nixpkgs then applies this overlay with
```nix
let

  nixpkgsFun = self: { /* ... */ };

  overlay = self: super: { /* ... */ };

  # The super package set is the result of the final package set being applied to the original nixpkgs function
  super = nixpkgsFun self;

  # The final package set takes all attributes of the previous package set, and overrides them with the ones defined in the overlay
  # The overlay gets passed both the final and the previous package sets
  self = super // overlay self super;

in self
```

More overlays can be applied similarly, each additional one can override attributes of the previous ones, or define new attributes altogether. For more info on how this works, see [Data Flow of Overlays](https://nixos.wiki/wiki/Overlays#Data_flow_of_overlays).

#### Adding a nixpkgs overlay from this repository

This repository allows defining an overlay in the `nixpkgs-overlay.nix` file, which can look like
```nix
self:
super: {
  # ...
}
```

This is useful if some package in nixpkgs needs to be changed, such that all its reverse dependencies use the changed package.

### This repositories package set

The package set in this repository _could_ be added on top of the nixpkgs package set using overlays.
- The advantage of this would be that there's only a single set of packages: If this repository defines an `ncurses` package, all of the packages in nixpkgs that (recursively) depend on ncurses would use the version in this repository, and the old ncurses package wouldn't be a dependency of anything anymore.
- The disadvantage however is that any package defined in this repository could cause many rebuilds for nixpkgs packages, potentially causing breakages or other problems.

Since we can opt into nixpkgs overlays for when it's necessary using `nixpkgs-overlay.nix`, we will avoid using nixpkgs overlays for this repositories packages.

Instead we define our own package set with a fresh self-referencing function. In addition, since we will have to depend on nixpkgs for many dependencies, we use the final nixpkgs package set as a base for our own package set:
```nix
let
  # The final package set of nixpkgs with our ./nixpkgs-overlay.nix applied
  pkgs = import <nixpkgs> {
    overlays = [ (import ./nixpkgs-overlay.nix) ];
  };
in
self: pkgs // {
  myDep = derivation { /* ... */ };
  myPkg = derivation {
    buildInputs = [
      self.myDep
      self.ncurses
    ];
    # ...
  };
}
```

Now since `pkgs` doesn't reference the `self` from our own package set, any of our package definitions won't propagate back into nixpkgs. Doing this essentially establishes a one-directional package flow from nixpkgs to our own package set, without it going the other way.

In addition, since we structured our own package set using a self-referencing function, we can apply our own overlays the same as nixpkgs does. In fact, we're using such overlays to add all our own packages. See the [`./overlays.nix`](./overlays.nix) file for the base set of overlays for our own package set. This keeps our own set of packages consistent, even if more overlays are applied. It also allows splitting our package definitions into multiple files.


### Other channels

In addition to our own package set (aka channel), we also have other channels from other departments. We can structure this with an attribute set defining all these package sets:
```nix
{
  floxChannels = {
    systems = /* final result of all our overlays */;
    vendor = /* final result of all of vendor's overlays */;
    # ...
  };
}
```

We have two use cases this channel set is needed for:

#### Overriding a nixpkgs package using a channel package

As we learned before, we can override nixpkgs packages deeply using `./nixpkgs-overlay.nix`. But what if we want to override a nixpkgs package using a package from a channel? In order to allow this, we append another overlay to nixpkgs, one that brings `floxChannels` into the nixpkgs scope:
```nix
let
  # The final package set of nixpkgs with both our floxChannels overlay and ./nixpkgs-overlay.nix applied
  pkgs = import <nixpkgs> {
    overlays = [
      (self: super: {
        floxChannels = { /* ... */ };
      })
      (import ./nixpkgs-overlay.nix)
    ];
  };
in
self: pkgs // {
  # ...
}
```

Now we can use `./nixpkgs-overlay.nix` to e.g. deeply override the `ncurses` package in nixpkgs with our own ncurses from the systems channel:
```nix
self: super: {
  ncurses = self.floxChannels.systems.ncurses;
}
```

#### Having channels be able to depend on other channels

In order to allow channels to easily depend on other channels, we bring all the channels into our final package set, right next to nixpkgs itself:

```nix
let
  # The final package set of nixpkgs with both our floxChannels overlay and ./nixpkgs-overlay.nix applied
  pkgs = import <nixpkgs> { /* ... */ };
in
self: pkgs // pkgs.floxChannels // {
  myPkg = derivation {
    buildInputs = [
      vendor.someVendorPkg
    ];
    # ...
  };
  # ...
}
```

This allows the overlays that add packages to use `self.vendor.someVendorPkg` to refer another channels packages. The `callPackage` function also passes the `vendor` argument to package functions.

Take note of the recursive nature of this: All the channels packages are declared with above expression using `floxChannels`, while `floxChannels` itself is the final result of all the channels. This again only works due to Nix's laziness. In addition, this is what allows channels to cross-reference each other recursively: `channelPkgs.vendor.someVendorPkg` can depend on `channelPkgs.systems.someSystemsPkg`, which again can depend on `channelPkgs.vendor.someOtherVendorPkg`, etc.

### Auto-called package directories

For defining packages, this repository auto-calls package functions in the `./pkgs`, `./pythonPackages` and `./perlPackages` directories. All subdirectories in these directories can define a `default.nix` file for defining a package. The arguments for the function can include anything from nixpkgs, from the current channel, or from another channel. For example, `./pkgs/someSystemsPkg/default.nix` could look like:
```nix
{
# A nixpkgs package
stdenv,
# Another autocalled package in ./pkgs/kerberos/default.nix
kerberos,
# A lib function defined in ./lib, added by ./lib/overlay.nix
floxSetSrcVersion,
# Another channel
vendor
}: stdenv.mkDerivation {
  inherit (floxSetSrcVersion "myProject" {}) src name version;
  buildInputs = [
    kerberos
    vendor.someVendorPkg
  ];
}
```

This package is then available for building with
```bash
$ nix-build -A someSystemsPkg
```

Or is available to other channels as `systems.someSystemsPkg`

Packages defined in `./pythonPackages` are available under the `python2Packages` and `python3Packages` attributes, while ones defined in `./perlPackages` are available under the `perlPackages` attribute.

### Overlay-related functions/terms used in the implementation

Above sections explain the concept, but the implementation uses some overlay-related functions not explained:

- `.extend (self: super: ...)`: A package set function that applies another overlay on top of the existing overlays, returning the new modified package set
- `lib.extends (self: super: ...) (self: ...)`: A function that takes an overlay and a self-referential function, and combines them into a new self-referential function that has the overlay applied. This is how overlays are implemented.
- `lib.fix`: A function that takes a self-referential package set and passes its result to itself, returning the result. This only works due to laziness. This function is used to turn the result of `lib.extends` into a package set.
- `lib.composeExtensions (self: super: ...) (self: super: ...)`: A function that takes two overlays and combines them into a single overlay by applying them in sequence.
- `emptyScope`: An empty package set, with an attribute `.extends` for appending additional overlays.
- `.callPackage ./some/path {}`: A package set function that calls a function at a given path, passing any arguments it needs from the package set it's defined in

