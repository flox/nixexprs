{ repo }:
let
  channel = import <test> {
    sourceOverrideJson = builtins.toJSON {
      test.testPackage = toString repo;
    };
  };
  contents = builtins.readFile (channel.testPackage.result.src.src + "/file");
  result = {
    inherit (channel.testPackage.result.src) project src origversion autoversion version pname name src_json;
    inherit contents;
    inherit (channel.testPackage.result) result;
  };
in result
