let
  lib = import <nixpkgs/lib>;
  utils = import <flox-lib/channel/utils> { inherit lib; };

  result = utils.modifyPaths [
    # Override with a throw
    {
      path = [ "y" ];
      mod = _: throw "nope";
    }
    # But also remove the attribute completely in the end
    {
      path = [ ];
      mod = x: removeAttrs x [ "y" ];
    }
    # Replacing a throwing value in the original set with a non-throwing one
    {
      path = [ "z" "y" ];
      mod = _: "10";
    }
    # Add an additional attribute without clearing existing ones along the path
    {
      path = [ "x" "y" ];
      mod = x: x // { baz = 10; };
    }
  ] {
    x.bar.z = 30;
    x.y.foo = 20;
    x.y.z = 10;
    y = 40;
    z.y = throw "nope";
  };

in result
