{ flox, floxInternal }:
let
  mockedGetSource = flox.getSource.override {
    fetchgit = args: builtins.trace "fetchgit called" args;
  };
in
mockedGetSource floxInternal.importingChannelArgs.name "testPackage" {}
