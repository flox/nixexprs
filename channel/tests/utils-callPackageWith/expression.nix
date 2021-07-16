let
  lib = import <nixpkgs/lib>;
  utils = import <flox-lib/channel/utils> { inherit lib; };

  result = utils.callPackageWith (utils.traceWith { }) { foo = 10; } <file>;

in result.value
