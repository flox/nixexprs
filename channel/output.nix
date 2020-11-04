# Returns the auto-generated output of a channel
# TODO: Add debug logs
{ pkgs }:
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
      error = "Trying to override ${lib.optionalString (!lDrv) "non-"}derivation in nixpkgs"
        + " with a ${lib.optionalString (!rDrv) "non-"}derivation in channel";
    in
      if lDrv == rDrv then
        # If both sides are derivations, override completely
        if rDrv then true
        # If both sides are attribute sets, merge recursively
        else if lib.isAttrs l && lib.isAttrs r then false
        # Otherwise, override completely
        else true
      else throw error);

  # Imports all directories and files in a subpath and returns a mapping from <name> to <expression>
  packageSetFuns = subpath:
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
            else throw "Can't auto-call non-Nix file ${toString (dir + "/${name}")}. "
              + "If non-Nix files are needed for a package, move the package into its own directory and use a default.nix file for the Nix expression";
        }.${type} or (throw "Can't auto-call file type ${type}");

      # Mapping from <package name> -> <package fun>
      # This caches the imports of the auto-called package files, such that they don't need to be imported for every version separately
      result = lib.mapAttrs' importPath (builtins.readDir dir);
    in if exists then result else {};

  # TODO: Splicing for cross compilation?? Take inspiration from mkScope in pkgs/development/haskell-modules/make-package-set.nix
  baseScope = smartMerge (self // self.xorg) self.floxInternal.outputs;

  mergeSets = lib.foldl' lib.recursiveUpdate {};

  packageSetOutputs = spec:
    let

      funs = packageSetFuns spec.callScopeAttr;

      versionOutput = paths:
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

          scope = baseScope // lib.getAttrFromPath paths.canonicalPath baseScope // {
            inherit channels;
            flox = channels.flox or (throw "Attempted to access flox channel from channel ${name}, but no flox channel is present in NIX_PATH");
            ${spec.callScopeAttr} = lib.getAttrFromPath paths.canonicalPath baseScope;
          };

          superSet = lib.attrByPath paths.canonicalPath null super;

          # TODO: recurseIntoAttrs for hydra

          set = lib.mapAttrs (name: fun:
            let
              scope' = scope // {
                ${name} = superSet.${name};
              };
            in lib.callPackageWith scope' fun {}
          ) funs;

          canonical = lib.setAttrByPath paths.canonicalPath set;

          selfSet = lib.getAttrFromPath paths.canonicalPath self.floxInternal.outputs;
          aliases = map (path: lib.setAttrByPath path selfSet) paths.aliases;
        in [ canonical ] ++ aliases;

    in lib.optionalAttrs (funs != {}) (mergeSets (lib.concatMap versionOutput (lib.attrValues spec.versions)));


in {
  floxInternal = super.floxInternal // {
    outputs = mergeSets (map packageSetOutputs (lib.attrValues packageSets));
  };
}
