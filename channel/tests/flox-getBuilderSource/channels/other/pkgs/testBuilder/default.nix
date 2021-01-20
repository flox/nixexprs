{ meta }:
let mockedGetSource = meta.getBuilderSource.override { fetchgit = args: args; };
in { result = mockedGetSource "testPackage" { }; }
