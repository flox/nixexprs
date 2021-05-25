{ flox, meta }:
let
  mockedGetSource = meta.getChannelSource.override {
    fetchgit = args: builtins.trace "fetchgit called" args;
  } meta.ownChannel;
in {
  result = mockedGetSource "testPackage" {
    rev = "783f71ba9565ed912473812c5781f0a623b22fa9";
    pname = "some-name";
  };
}
