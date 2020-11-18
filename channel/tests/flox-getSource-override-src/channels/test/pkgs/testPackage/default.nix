{ flox, meta }:
let
  mockedGetSource = meta.getSource.override {
    fetchgit = args: args;
  };
in mockedGetSource "testPackage" {
  src = "/some/src/path";
}
