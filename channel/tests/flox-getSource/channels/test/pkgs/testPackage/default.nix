{ flox, meta }:
let
  mockedGetSource = meta.getChannelSource.override {
    fetchgit = args: builtins.trace "fetchgit called" args;
  } meta.ownChannel;
in { result = mockedGetSource "testPackage" { }; }
