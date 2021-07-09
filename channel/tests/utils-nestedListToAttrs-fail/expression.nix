let
  lib = import <nixpkgs/lib>;
  utils = import <flox/channel/utils> { inherit lib; };

  result = utils.nestedListToAttrs (utils.traceWith { }) [
    {
      path = [ "arch" "foo" "florp" ];
      value = 10;
    }
    {
      path = [ "arch" "foo" ];
      value = { florp = 20; };
    }
  ];
in result
