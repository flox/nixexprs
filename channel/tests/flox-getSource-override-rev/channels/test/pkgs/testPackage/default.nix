{ flox, floxInternal }:
let
  mockedGetSource = flox.getSource.override {
    fetchgit = args: builtins.trace "fetchgit called" args;
  };
in mockedGetSource floxInternal.importingChannelArgs.name "testPackage" {
  rev = "783f71ba9565ed912473812c5781f0a623b22fa9";
  version = "1.2.3";
  pname = "some-name";
}
