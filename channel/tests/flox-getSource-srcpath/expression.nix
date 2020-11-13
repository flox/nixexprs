{ repo }:
let
  channel = import <test> { srcpath = repo; };
  contents = builtins.readFile (channel.testPackage.src + "/file");
in {
  inherit (channel.testPackage) project src origversion autoversion version pname name src_json;
  inherit contents;
}
