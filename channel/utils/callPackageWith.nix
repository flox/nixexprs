{ lib ? import <nixpkgs/lib> }: {
  callPackageWith = trace: autoArgs: path:
    let
      fun = import path;
      file = if builtins.pathExists (path + "/default.nix") then path + "/default.nix" else path;
      funArgs = lib.functionArgs fun;
      auto = lib.mapAttrs (name: value:
        if funArgs.${name}
        then throw
          ("In ${toString file}, the argument \"${name}\" has a default value "
          + "(`${name} ? <default>`) which is not allowed because the attribute "
          + "\"${name}\" exists in the environment, therefore overriding the "
          + "default value.\nIf \"${name}\" should be a package configuration, "
          + "changeable via `.override { ${name} = <value>; }`, rename the "
          + "argument to something that doesn't already exist\nIf \"${name}\" "
          + "should be optional dependency (commonly done with "
          + "`${name} ? null`), remove the default value")
        else value
      ) (builtins.intersectAttrs funArgs autoArgs);
    in trace "callPackageWith" 6 "Calling file ${file}" (lib.makeOverridable fun auto);
}
