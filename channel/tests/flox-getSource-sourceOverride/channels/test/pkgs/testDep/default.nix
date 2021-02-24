{ flox, meta }:
let
  mockedGetSource =
    meta.getSource.override { fetchgit = args: { result = "result"; }; };
in { result = mockedGetSource "testDep" { }; }
