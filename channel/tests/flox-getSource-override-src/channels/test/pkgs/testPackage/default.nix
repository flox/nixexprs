{ flox, meta }:
let
  mockedGetSource = meta.getSource.override {
    fetchgit = args: args;
  };
in {
  result = mockedGetSource "testPackage" {
    src = "/some/src/path";
    version = "1.0";
  };
}
