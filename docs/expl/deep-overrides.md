# How deep overrides work

Flox channels have support for [defining packages as deep-overriding](../channel-construction.md#shallow-vs-deep-overriding). While the interface to this feature is really simple, [the implementation](https://github.com/flox/floxpkgs/blob/staging/channel/output.nix) is very tricky.

The underlying mechanism that allows this feature to work are [nixpkgs overlays](https://nixos.org/manual/nixpkgs/stable/#sec-overlays-definition). Packages that specify themselves as deep-overriding are injected into nixpkgs with an overlay. For top-level packages in `pkgs/<name>` this is very easy with an overlay like

```nix
self: super: {
  myPkg = thePackage;
}
```

This then ensures that all nixpkgs packages have their dependency (transitively) replaced with the one we pass in the overlay. After the final package set is computed, these overlay-injected attributes are then "fished out" of the resulting nixpkgs set, so that they can be added to the final channel output (which notably only and exactly contains the packages defined within the channel).

There are however two complications for some other scenarios which are described in the following sections.

## Package sets

Channels can not only define top-level packages, but also specific package sets, e.g. with `pythonPackages/<name>/default.nix` for Python. Deep overrides are supported in the very same way as for top-level packages, but the implementation is trickier. One problem is that nixpkgs is very inconsistent and unintuitive with how package sets can be overridden (deeply) in overlays. Notably the following doesn't work:

```nix
self: super: {
  pythonPackages = super.pythonPackages // {
    myPkg = thePackage;
  };
}
```

This would only shallowly override the python package, and that only for the `pythonPackages` set, not `python37Packages`. In Python's case, a mostly working invocation is

```nix
self: super: {
  python27Packages = super.python27Packages.override (old: {
    overrides = super.lib.composeExtensions old.overrides (self: super: {
      myPkg = thePackage;
    });
  });
  python36Packages = super.python36Packages.override ...;
  # And so on for all package sets
}
```

And this is different for almost every package set. E.g. for Perl it's

```nix
self: super: {
  perl532Packages = super.perl532Packages.override (old: {
    overrides = pkgs: old.overrides pkgs // {
      myPkg = thePackage;
    };
  });
}
```

In order to provide a unified interface for all package sets, the information for how to deeply override each package set is recorded in the `deepOverride` fields in [package-sets.nix](../../channel/package-sets.nix). This is right next to some other fields that describe how all the different versions of package sets in nixpkgs are detected and propagated.

## Channel dependencies

Channels can not only depend on nixpkgs packages, but also on packages defined by other channels. And both our own channel and each dependent channel, and their dependent channels, etc., can have deep overrides. And each channel expects *their* overrides to apply to the whole channel closure.

We can think about this a bit more easily by realizing that each channel will have to get a nixpkgs set in the end, with a list of overlays applied. Let's visualize a dependency tree of channels `A`, `B` and `C`, which have a dependency chain among themselves:

```
A
|
+-B
  |
  +-C
```

Now say that each of these channels defines some deep overrides, so they each end up with an overlay, calling them `a`, `b` and `c` for channel `A`, `B` and `C`'s overlays respectively. For each channel we now need to find a list of overlays that includes their own and their parents overlays. We might be tempted to choose this mapping:

```
A       [ a ]
|
+-B     [ a b ]
  |
  +-C   [ a b c ]
```

However this causes a problem: For both channel `B` and `C`, the overlay from `A` is applied _last_. This means that e.g. in case both `a` and `b` define the same package to be deeply overridden, the version from `b` will be used for channels `B`, meaning you'll have different versions of these packages in channel `A` and `B` in the end!

In order to prevent this problem, we need to reverse the overlay order:

```
A       [ a ]
|
+-B     [ b a ]
  |
  +-C   [ c b a ]
```

This way, in case both `a` and `b` define the same package to be deeply overridden, the one from `a` takes precedence for both `A` and `B`, meaning we end up with a consistent package.

