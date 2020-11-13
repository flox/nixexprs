let
  result = (import <test> {}).testPackage;
in {
  inherit (result) project src origversion autoversion version pname name src_json;
}
