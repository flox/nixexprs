{ lib ? import <nixpkgs/lib> }: {
  # Turns a directory into an attribute set.
  # Files with a .nix suffix get turned into an attribute name without the
  # suffix. Directories get turned into an attribute of their name directly.
  # If there is both a .nix file and a directory with the same name, the file
  # takes precedence. The context argument is a string shown in trace messages
  # Each value in the resulting attribute sets has attributes
  # - value: The Nix value of the file or of the default.nix file in the directory
  # - deep: In case of directories, whether there is a deep-override file within it. For files always false
  # - file: The path to the Nix file that was imported
  # - type: The file type, either "regular" for files or "directory" for directories
  dirToAttrs = context: dir:
    let
      exists = builtins.pathExists dir;

      importPath = name: type:
        let path = dir + "/${name}";
        in {
          directory = lib.nameValuePair name {
            # TODO: Allow specified deepOverride = true in config.nix
            deep = builtins.pathExists (path + "/deep-override");
            config = if builtins.pathExists (path + "/config.nix") then import (path + "/config.nix") else {};
            inherit path type;
          };

          regular = if lib.hasSuffix ".nix" name then
            lib.nameValuePair (lib.removeSuffix ".nix" name) {
              deep = false;
              config = {};
              inherit path type;
            }
          else
            null;
        }.${type} or (throw "Can't auto-call file type ${type}");

      # Mapping from <package name> -> { value = <package fun>; deep = <bool>; }
      # This caches the imports of the auto-called package files, such that they don't need to be imported for every version separately
      entries = lib.filter (v: v != null)
        (lib.attrValues (lib.mapAttrs importPath (builtins.readDir dir)));

      # Regular files should be preferred over directories, so that e.g.
      # foo.nix can be used to declare a further import of the foo directory
      entryAttrs =
        lib.listToAttrs (lib.sort (a: b: a.value.type == "regular") entries);

      message = ''
        [channel ${myArgs.name}] [${context}] Importing all Nix expressions from directory "${
          toString dir
        }"'' + withVerbosity 6
        (_: ". Attributes: ${toString (lib.attrNames entryAttrs)}") "";

      result = if exists then
        withVerbosity 4 (builtins.trace message) entryAttrs
      else
        withVerbosity 5 (builtins.trace
          "[channel ${myArgs.name}] [${context}] Not importing any Nix expressions because `${
            toString dir
          }` does not exist") { };

    in result;
}
