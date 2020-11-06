# Returns the auto-generated output of a channel
# TODO: Add debug logs
{ pkgs, withVerbosity }:
let
  # TODO: Pregenerate a JSON from this
  packageSets = import ./package-sets.nix { inherit pkgs; };
in
{ topdir, channelOutputs, name }:
self: super:
let

  inherit (super) lib;

  # Merges attribute sets recursively, but not recursing into derivations,
  # and error if a derivation is overridden with a non-derivation, or the other way around
  smartMerge = lib.recursiveUpdateUntil (path: l: r:
    let
      lDrv = lib.isDerivation l;
      rDrv = lib.isDerivation r;
      prettyPath = lib.concatStringsSep "." path;
      error = "Trying to override ${lib.optionalString (!lDrv) "non-"}derivation in nixpkgs"
        + " with a ${lib.optionalString (!rDrv) "non-"}derivation in channel";
    in
      if lDrv == rDrv then
        # If both sides are derivations, override completely
        if rDrv then withVerbosity 7 (builtins.trace "[channel ${name}] [smartMergePath ${prettyPath}] Overriding because both sides are derivations") true
        # If both sides are attribute sets, merge recursively
        else if lib.isAttrs l && lib.isAttrs r then withVerbosity 7 (builtins.trace "[channel ${name}] [smartMergePath ${prettyPath}] Recursing because both sides are attribute sets") false
        # Otherwise, override completely
        else withVerbosity 7 (builtins.trace "[channel ${name}] [smartMergePath ${prettyPath}] Overriding because left is ${builtins.typeOf l} and right is ${builtins.typeOf r}") true
      else throw error);

  # Imports all directories and files in a subpath and returns a mapping from <name> to <expression>
  packageSetFuns = setName: subpath:
    let
      dir = topdir + "/${subpath}";
      exists = builtins.pathExists dir;

      importPath = name: type:
        {
          # TODO: Better error when there's no default.nix?
          directory = lib.nameValuePair name (import (dir + "/${name}"));

          regular =
            if lib.hasSuffix ".nix" name
            then lib.nameValuePair (lib.removeSuffix ".nix" name) (import (dir + "/${name}"))
            else null;
        }.${type} or (throw "Can't auto-call file type ${type}");

      # Mapping from <package name> -> <package fun>
      # This caches the imports of the auto-called package files, such that they don't need to be imported for every version separately
      result = lib.listToAttrs (lib.filter (v: v != null) (lib.attrValues (lib.mapAttrs importPath (builtins.readDir dir))));

      message = "[channel ${name}] [packageSet ${setName}] Importing all Nix expressions from directory \"${toString dir}\"" + withVerbosity 6 (_: ". Attributes: ${toString (lib.attrNames result)}") "";
    in
      if exists
      then withVerbosity 4 (builtins.trace message) result
      else withVerbosity 5 (builtins.trace "[channel ${name}] [packageSet ${setName}] Not importing any Nix expressions because `${toString dir}` does not exist") {};

  # TODO: Splicing for cross compilation?? Take inspiration from mkScope in pkgs/development/haskell-modules/make-package-set.nix
  baseScope = smartMerge (self // self.xorg) self.floxInternal.outputs;

  # TODO: Error if conflicting paths. Maybe on the package-sets.nix side already though
  mergeSets = lib.foldl' lib.recursiveUpdate {};

  packageSetOutputs = setName: spec:
    let

      funs = packageSetFuns setName spec.callScopeAttr;

      versionOutput = version: paths:
        let

          # This maps channels to e.g. have pythonPackages be the correct version
          channels = lib.mapAttrs (name: value:
            # If the dependent channel has the package set with the correct version,
            let set = lib.attrByPath paths.canonicalPath null value;
            in value // {
              ${spec.callScopeAttr} =
                if set != null then set
                # maybe TODO: Try out all aliases to see if any of them have a matching version
                else throw "Channel ${name} did not provide attribute path `${lib.concatStringsSep "." paths.canonicalPath}`";
            }
          ) channelOutputs;

          packageSetScope = lib.getAttrFromPath paths.canonicalPath baseScope;

          scope = baseScope // packageSetScope // {
            inherit channels;
            flox = channels.flox or (throw "Attempted to access flox channel from channel ${name}, but no flox channel is present in NIX_PATH");
          };

          superSet = lib.attrByPath paths.canonicalPath null super;

          # TODO: recurseIntoAttrs for hydra
          set = lib.mapAttrs (pname: fun:
            let
              scope' = scope // {
                ${pname} = superSet.${pname};
                ${spec.callScopeAttr} = packageSetScope // {
                  ${pname} = superSet.${pname};
                };
              };
            in withVerbosity 8 (builtins.trace "[channel ${name}] [packageSet ${setName}] [version ${version}] Auto-calling package ${pname}")
              (lib.callPackageWith scope' fun {})
          ) funs;

          canonical = lib.setAttrByPath paths.canonicalPath set;

          selfSet = lib.getAttrFromPath paths.canonicalPath self.floxInternal.outputs;
          aliases = map (path: lib.setAttrByPath path selfSet) paths.aliases;

          setHydraRecurse = attrPath:
            if attrPath == [] then {}
            else {
              ${lib.head attrPath} = lib.recurseIntoAttrs (setHydraRecurse (lib.tail attrPath));
            };

          hydraRecursion = setHydraRecurse paths.canonicalPath;

        in [ canonical ] ++ lib.optional paths.recurse hydraRecursion ++ aliases;

    in lib.optionalAttrs (funs != {}) (mergeSets (lib.concatLists (lib.attrValues (lib.mapAttrs versionOutput spec.versions))));

  toplevel =
    let
      funs = packageSetFuns "toplevel" "pkgs";
      scope = baseScope // {
        channels = channelOutputs;
        flox = channelOutputs.flox or (throw "Attempted to access flox channel from channel ${name}, but no flox channel is present in NIX_PATH");
      };
      set = lib.mapAttrs (pname: fun:
        let
          # TODO:
          scope' = scope // {
            ${pname} = super.${pname};
          };
        in withVerbosity 8 (builtins.trace "[channel ${name}] [packageSet toplevel] Auto-calling package ${pname}")
          (lib.callPackageWith scope' fun {})
      ) funs;
    in set;

in {
  floxInternal = super.floxInternal // {
    outputs = mergeSets ([ toplevel ] ++ lib.attrValues (lib.mapAttrs packageSetOutputs packageSets));
  };
}
