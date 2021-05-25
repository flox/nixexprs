{ flox, meta, testDep }:
let
  mockedGetSource = meta.getChannelSource.override {
    fetchgit = args: builtins.trace "fetchgit called" args;
  } meta.ownChannel;
in {
  result = {
    src = mockedGetSource "testPackage" { };
    result = testDep.result.src.result;
  };
}
