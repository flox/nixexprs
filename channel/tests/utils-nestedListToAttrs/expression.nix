let
  lib = import <nixpkgs/lib>;
  utils = import <flox/channel/utils> { inherit lib; };

  result = utils.nestedListToAttrs (utils.traceWith { }) [
    {
      path = [ ];
      value = { bar = 20; };
    }
    {
      path = [ "arch" "foo" "florp" ];
      value = 10;
    }
    {
      path = [ "qux" ];
      value = { foo = 10; };
    }
    {
      path = [ "qux" "florp" ];
      value = 10;
    }
  ];
in result
