{ meta }:
let
  mockedGetSource = meta.getChannelSource.override { fetchgit = args: args; }
    meta.importingChannel;
in { result = mockedGetSource "testPackage" { }; }
