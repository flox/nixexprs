{ testRepo, otherRepo }:
let
  channel = import <test> {
    sourceOverrideJson = builtins.toJSON {
      test.testPackage = toString testRepo;
      other.testDep = toString otherRepo;
    };
  };
  testContents =
    builtins.readFile (channel.testPackage.result.source.src + "/file");
  otherContents =
    builtins.readFile (channel.testPackage.result.other.src + "/file");
  result = { inherit testContents otherContents; };
in result
