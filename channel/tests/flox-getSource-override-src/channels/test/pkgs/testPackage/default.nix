{ flox, meta }:
let
  mockedGetSource =
    meta.getChannelSource.override { fetchgit = args: args; } meta.ownChannel;
in {
  result = mockedGetSource "testPackage" {
    src = "/some/src/path";
    version = "1.0";
  };
}
