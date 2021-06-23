{ lib ? import <nixpkgs/lib> }: {

  callPackageList = argsList: f: args:
    let
      funArgs = lib.functionArgs f;
      auto =
        lib.foldl' (args: elem:
          args // builtins.intersectAttrs funArgs elem
        ) {} argsList;
    in lib.makeOverridable f (auto // args);

}
