{ repo }:
let
  channel = import <test> {
    sourceOverrideJson = builtins.toJSON { test.testPackage = toString repo; };
  };
  contents = builtins.readFile (channel.testPackage.result.src.src + "/file");
  result = {
    src = channel.testPackage.result.src;
    inherit contents;
    inherit (channel.testPackage.result) result;
  };
in result
