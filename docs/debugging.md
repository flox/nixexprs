# Debugging

## Trace function

Throughout the codebase, the `trace` function, available to channels via `meta.trace`, is used to allow emitting debug information during evaluation. It takes the following arguments:

`trace <subsystem> <verbosity> <message> <result>`
- `<subsystem>` (string): An arbitrary chosen name of the subsystem/component that issues the trace in order to identify and be able to distinguish different parts of the code.
- `<verbosity>` (integer): The verbosity of this tracing message. The number can be arbitrary, but these rough levels are used throughout this codebase:
  - 0: Useful for temporary debugging, should normally not be used as they're printed by default
  - 1-3: For debug messages that are infrequent, only a handful of messages are printed
  - 4-7: For debug messages that are somewhat more frequent
  - 8-10: For debug messages that are very frequent, these can really litter the output
- `<message>` (value): The tracing message to print. Can be an arbitrary value
- `<result>` (value): The result of this function call

The printed format of such trace messages is as follows:
```
trace: <subsystem:verbosity> message
```

For example, an expression like
```nix
trace "mySubsystem" 0 "My message" null
```
would result in
```
trace: <mySubsystem:0> My message
```

### Adding context

The `trace` function also has some convenience utilities for creating a new `trace` which adds some context to the final trace output:

`trace.withContext <key> <value> (trace: <expression>)`:
- `<key>` (string): The name of this context entry. Should indicate what the `<value>` represents, such as the variable name
- `<value>` (value): The value of this context entry. This can be an arbitrary value
- `<expression>` (value): The nested expression to evaluate with the new context. Only the `trace` in the new scope of this expression will print messages with the given context. This is also the return value of this function

`trace.setContext <key> <value>`: Same as `trace.withContext`, but returns the new `trace` value directly

The printed format when context has been added is as follows:
```
trace: <subsystem:verbosity> [contextKey1=contextValue1] ... [contextKeyN=contextValueN] message
```

For example, an expression like
```nix
map (n: trace.withContext "n" n (trace:
  trace "mySubsystem" 0 "My message ${toString n}" n
)) [ 1 2 3 ]
```
would result in
```
trace: <mySubsystem:0> [n=1] My message 1
trace: <mySubsystem:0> [n=2] My message 2
trace: <mySubsystem:0> [n=3] My message 3
```

## Configuring tracing

### Default minimum verbosity

Tracing can be configured by setting a default minimum verbosity with the `--arg debugVerbosity <n>` CLI argument, meaning that only messages with a verbosity equal or above `<n>` are printed. For example, we can configure it to show a lot of tracing messages when building a package by setting a minimum verbosity of `9`:

```
$ nix-build -A testPackage --arg debugVerbosity 9
trace: <closure:1> Determining channel closure
trace: <name:2> Determined root channel name to be root with heuristic baseName
trace: <closure:2> Channel root depends on flox-lib
trace: <pregen:1> Reusing pregenerated /home/infinisil/nixpkgs-pregen/package-sets.json
trace: <dirToAttrs:5> [dir=root/beamPackages] Not importing any attributes because the directory doesn't exist
trace: <dirToAttrs:5> [dir=root/haskellPackages] Not importing any attributes because the directory doesn't exist
trace: <dirToAttrs:5> [dir=root/perlPackages] Not importing any attributes because the directory doesn't exist
trace: <dirToAttrs:4> [dir=root/pkgs] Importing these attributes from directory: other, testPackage
trace: <dirToAttrs:5> [dir=root/pythonPackages] Not importing any attributes because the directory doesn't exist
trace: <nestedListToAttrs:9> [importingChannel=root] [channel=root] Called with index 0 and list paths [ [ ] ]
trace: <callPackageWith:6> [importingChannel=root] [channel=root] [packageSet=pkgs] [version=none] [package=testPackage] Calling file /home/infinisil/.cache/floxpkgs/root/pkgs/testPackage.nix
trace: <dirToAttrs:4> [dir=flox/pkgs] Importing these attributes from directory: buildGoModule, buildGoPackage, buildRustPackage, linkDotfiles, mkDerivation, naersk, removePathDups
trace: <pathsToModify:2> [importingChannel=root] [pathsToModifyType=shallow] [packageSet=pkgs] [version=none] Injecting attributes into path [ ]: [ "buildGoModule" "buildGoPackage" "buildRustPackage" "linkDotfiles" "mkDerivation" "naersk" "other" "removePathDups" "testPackage" ]
/nix/store/apbhxds141wrib2yg53zg1njkryhfk0b-test
```

### Subsystem-specific minimum verbosity

In addition to setting a default verbosity, it's possible to override the verbosity for each individual subsystem with the `--arg subsystemVerbosities '{ <subsystem> = <n>; }'` CLI argument. For example, if we want to filter out the `dirToAttrs` traces from above, we can do so by setting that subsystem's verbosity to `0`:

```
$ nix-build -A testPackage --arg debugVerbosity 9 --arg subsystemVerbosities '{ dirToAttrs = 0; }'
trace: <closure:1> Determining channel closure
trace: <name:2> Determined root channel name to be root with heuristic baseName
trace: <closure:2> Channel root depends on flox-lib
trace: <pregen:1> Reusing pregenerated /home/infinisil/nixpkgs-pregen/package-sets.json
trace: <nestedListToAttrs:9> [importingChannel=root] [channel=root] Called with index 0 and list paths [ [ ] ]
trace: <callPackageWith:6> [importingChannel=root] [channel=root] [packageSet=pkgs] [version=none] [package=testPackage] Calling file /home/infinisil/.cache/floxpkgs/root/pkgs/testPackage.nix
trace: <pathsToModify:2> [importingChannel=root] [pathsToModifyType=shallow] [packageSet=pkgs] [version=none] Injecting attributes into path [ ]: [ "buildGoModule" "buildGoPackage" "buildRustPackage" "linkDotfiles" "mkDerivation" "naersk" "other" "removePathDups" "testPackage" ]
/nix/store/apbhxds141wrib2yg53zg1njkryhfk0b-test
```
