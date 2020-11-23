{ flox, meta, testDep }:
let
  mockedGetSource = meta.getSource.override {
    fetchgit = args: builtins.trace "fetchgit called" args;
  };
in
{
  result = {
    src = mockedGetSource "testPackage" {};
    result = testDep.result.src.result;
  };
}
