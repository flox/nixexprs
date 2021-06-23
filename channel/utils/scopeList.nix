{ lib ? import <nixpkgs/lib> }: {

  callPackage = autoArgs: f: args:
    let
      funArgs = lib.functionArgs f;
      auto = lib.foldl' (scope: args: scope // builtins.intersectAttrs funArgs args) {} autoArgs;
    in lib.makeOverridable f (auto // args);

  #callPackage = scopes: resolve: f: args:
  #  let
  #    funArgs = lib.functionArgs f;

  #    values = lib.concatMap (name:
  #      lib.mapAttrsToList (attr: value: {
  #        inherit name attr value;
  #      }) (builtins.intersectAttrs funArgs scope.${name})
  #    ) (lib.attrNames scopes);

  #    auto = lib.mapAttrs (name: els:
  #      if lib.length els == 1
  #      then builtins.trace "callPackage: Source for attribute ${name} is ${(lib.head els).name}" (lib.head els).value
  #      else builtins.trace "callPackage: Conflicts between ${toString (lib.attrNames (lib.listToAttrs els))} for attribute ${name}, resolving it" resolve (lib.listToAttrs els)
  #    ) (lib.groupBy (el: el.attr) values);

  #  in lib.makeOverridable f (auto // args);

  #callPackage = scopes: f: args:
  #  let
  #    funArgs = lib.functionArgs f;

  #    auto = lib.foldl' (acc: el:
  #      if el.path == [] then
  #        acc // builtins.intersectAttrs funArgs el.value
  #      else let attr = lib.head el.path; in {
  #        ${attr} = el.value;
  #      }
  #    ) {} scopes;

  #  in lib.makeOverridable f (auto // args);

  #scopes = [
  #  {
  #    path = [];
  #    value = baseScope;
  #  }
  #  {
  #    path = [ "python2Packages" ];
  #    value = throw "Nope";
  #  }
  #];



}
