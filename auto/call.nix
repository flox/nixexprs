# Given a directory, generate an attribute set where every
# attribute corresponds to a subdirectory, which is autocalled with the given callPackage
{ lib
, path
, callPackage
, withVerbosity
}:
let
  # TODO: Warn or error or do something else for non-directories?
  subdirs = lib.attrNames (lib.filterAttrs (name: type: type == "directory") (builtins.readDir path));
  subdirPackage = name: withVerbosity 4
    (builtins.trace "Auto-calling ${toString (path + "/${name}")}")
    (callPackage (path + "/${name}") {});
in lib.genAttrs subdirs subdirPackage
