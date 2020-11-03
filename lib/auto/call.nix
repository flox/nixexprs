# Given a directory, generate an attribute set where every
# attribute corresponds to a subdirectory, which is autocalled with the given callPackage
{ lib
, path
, scope
, super
, withVerbosity
}:
let
  subpaths = lib.mapAttrs' (name: type:
    {
      regular =
        if lib.hasSuffix ".nix" name
        then lib.nameValuePair (lib.removeSuffix ".nix" name) (path + "/${name}")
        else throw "Can't auto-call non-Nix file ${toString (path + "/${name}")}. "
          + "If non-Nix files are needed for a package, move the package into its own directory and use a default.nix file for the Nix expression";
      directory = lib.nameValuePair name (path + "/${name}");
    }.${type} or (throw "Can't auto-call file type ${type}")) (builtins.readDir path);
  subpathPackage = name: path: withVerbosity 4
    (builtins.trace "Auto-calling ${toString path}")
    (lib.callPackageWith (scope // {
      ${name} = super.${name};
    }) path {});
in lib.mapAttrs subpathPackage subpaths
