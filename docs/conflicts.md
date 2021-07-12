# Package conflicts

## Dependency conflicts

When you depend on another flox channel, all of its packages are automatically brought into scope. For example, when in our own `root` channel we depend on another channel called `channel1` by adding its entry to our `<root>/channels.json` with
```json
[
  "channel1"
]
```


Then if `channel1` defines a package in `<channel1>/pkgs/otherPackage/default.nix`, we have access to that in our own `root` channel by just adding `otherPackage` to the expression arguments in our own packages, say `<root>/pkgs/ownPackage/default.nix`:
```nix
{ pythonPackages, lib, otherPackage }:
pythonPackages.buildPythonApplication {
  project = "ownPackage";

  buildInputs = [
    otherPackage
  ];
}
```

In addition to the entries specified in `channels.json`, every channel also implicitly depends on `nixpkgs` and the `flox` channel, which is why we have access to `pythonPackages.buildPythonApplication` (supporting the `project` argument) from the `flox` channel, and `lib` from `nixpkgs`.

However, what happens if there are multiple channels that define the same package? E.g. if we also depend on a channel `channel2`, which also provides a `<channel2>/pkgs/otherPackage/default.nix`, where should `otherPackage` come from?

Flox handles this by giving you a package conflict that needs to be resolved manually:
```
error: The package pkgs.otherPackage is being used. However there are multiple channels which provide that package.
No conflict resolution is currently provided. Valid options are [ "channel1", "channel2" ].
Set the conflict resolution for this package in <root>/default.nix by copying one of the following lines to it:
  conflictResolution.pkgs.otherPackage = "channel1";
  conflictResolution.pkgs.otherPackage = "channel2";
```

We can now choose where `otherPackage` should come from by following these instructions. E.g. if we want the package from `channel2`, we'd change `<root>/default.nix` to look like
```nix
import <flox/channel> {
  topdir = ./.;
  conflictResolution.pkgs.otherPackage = "channel2";
}
```

Since all channels share the same scope of packages, this conflict resolution means that not only our `root` channel will use `channel2`'s version of `otherPackage`, but in fact _all_ channels we depend on will use that version. This ensures a consistent package set without mismatched versions, assuming packages with the same name inherently conflict in some way.

From the above example, we saw that package conflict resolution is only necessary if more than one channel defines a package. However there are some exceptions in which conflicts can safely be resolved automatically even with multiple channels providing them:
- If the `root` channel (the channel we're evaluating from) specifies a package, that takes precedence over any other channels
- If only the `flox` and `nixpkgs` channel provide a package, conflict resolution chooses `flox` automatically, because all the packages it defines are essentially just an extension of the equivalent nixpkgs builders

Here is a list of examples of when conflict resolution is or is not necessary. A `o` indicates that a specific channel provides the given package, and a `(o)` indicates that the package from that channel was chosen

| packages \ channels | nixpkgs | flox | root | channel1 | channel2 | package comes from | reason |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A | (o) | | | | | nixpkgs | Only exists in nixpkgs |
| B | o | (o) | | | | flox | Flox safely overrides nixpkgs |
| C | o | o | (o) | o | | root | Root channel always takes precedence |
| D | | | | (o) | | channel1 | Only exists in one channel |
| F | o | | | o | | (conflict!) | Provided by both nixpkgs and a channel |
| E | | o | | o | | (conflict!) | Provided by both flox and another channel |
| G | | | | o | o | (conflict!) | Provided by multiple channels |

In the `root` channel, you can manually ask for where a package comes from. For above example with `pkgs/otherPackage` this can be done with

```
$ nix-instantiate --eval -A channelInfo.packageRoots.pkgs.otherPackage.shallow.channel
"channel2"
```

For a python package like `pythonPackages/otherPackage` it would be
```
$ nix-instantiate --eval -A channelInfo.packageRoots.pythonPackages.otherPackage.shallow.channel
"channel2"
```

## Override conflicts

There is one problem with above conflict resolution: What if `channel2` wants to _override_ `otherPackage` from `channel1`?

For example, `<channel1>/pkgs/otherPackage/default.nix` could provide the base package:
```nix
{ lib, enableGUI ? false }: {
  name = "otherPackage${lib.optionalString enableGUI "-gui"}";
}
```

while `<channel2>/pkgs/otherPackage/default.nix` overrides it
```nix
{ otherPackage }:
otherPackage.override {
  enableGUI = true;
}
```

If it is really the case that conflict resolutions from the root channel are applied to all the channels it depends on, and the root channel specifies that `otherPackage` should come from `channel2`, then even the `otherPackage` in above definition would point to `channel2`'s package itself, which is a case of infinite recursion!

To solve this, there is an exception to the package scoping: The package attribute with the same name as the one that is being defined (`otherPackage` in this case) will come from the _dependencies_ of the channel it is defined in, aka an unoverridden version.

After ensuring that `channel1` is specified as a dependency of `channel2` in `<channel2>/channels.json`:
```json
[
  "channel1"
]
```

We can now evaluate `otherPackage` in our root channel (which still specifies that the package should come from `channel2`) and confirm that it indeed contains the version from `channel1`, but overridden via `channel2`:
```
$ nix-instantiate --eval -A channelInfo.baseScope.otherPackage.name
"otherPackage-gui"
```

But what should happen if there is a third channel now, `channel3`, which _also_ defines a base package for `otherPackage`, and `channel2` depends on it? Where should `channel2` get the base package from?

```
error: In the definition of the pkgs.otherPackage package in <channel2>/pkgs/otherPackage/default.nix, the argument
otherPackage itself is being used, which points to the unoverridden version of the same package. However there
are multiple channels which provide that package.
No conflict resolution is currently provided. Valid options are [ "channel1", "channel3" ].
Set the conflict resolution for this package in <channel2>/default.nix by copying one of the following lines to it:
  conflictResolution.pkgs.otherPackage = "channel1";
  conflictResolution.pkgs.otherPackage = "channel3";
```

As you might expect, this is handled by requiring a manual conflict resolution again. This time however, it is _not_ the root channel which needs to specify the resolution, but rather the channel that doesn't know which version of `otherPackage` to override, `channel2` here. Following the instructions of the error message, we can specify that `channel2`'s `otherPackage` overrides the one from `channel1` by changing `<channel2>/default.nix` to
```nix
import <flox/channel> {
  topdir = ./.;
  conflictResolution.pkgs.otherPackage = "channel1";
}
```

The rules for automatic resolution of override conflicts are the same as the ones for dependency conflicts in the previous section, however only the _direct_ dependencies of the channel are available as options (which includes `nixpkgs` and `flox`, but excludes the channel itself).
