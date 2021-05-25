{ flox, meta }:
let
  mockedGetSource =
    meta.getChannelSource.override { fetchgit = args: { result = "result"; }; }
    meta.ownChannel;
in { result = mockedGetSource "testDep" { }; }
