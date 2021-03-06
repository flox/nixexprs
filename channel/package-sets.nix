{ lib ? import <nixpkgs/lib>, pregenerate ? true
  # Should only be used during pregeneration
, nixpkgs ? throw "No nixpkgs passed"
, pregenResult ? throw "No pregenResult passed" }:
/* If pregenerate, returns only the fields which can be serialized to json
   Otherwise, checks if the serializable parts are already pregenerated and merges them with the non-serializable ones
*/

let
  nixpkgs' = assert pregenerate; nixpkgs;

  pkgs = import nixpkgs' {
    config = { };
    overlays = [ ];
  };

  # This is used to determine whether nixpkgs hydra builds certain package sets
  releasePkgs = import (nixpkgs' + "/pkgs/top-level/release.nix") { };

  /* This function turns the attributes of each package set into a structure like

     {
       callScopeAttr = <call scope attr>;
       deepOverride = <overrideFun>;
       versions = {
         <version> = {
           recurse = <bool>;
           canonicalPath = [ <package> <set> <path> ];
           aliases = [
             [ <alias> <one> ]
             [ <alias> <two> ]
           ];
         };
       };
     }
  */
  packageSet = setName:
    { versionForPackageSet, attrPathForVersion, packageSetAttrPaths
    , callScopeAttr, deepOverride }:
    let

      addVersion = path:
        let set = lib.attrByPath path null pkgs;
        in {
          inherit path;
          version = lib.mapNullable versionForPackageSet set;
        };

      # Mapping from version to list of paths it can be found in
      versionPaths = lib.pipe packageSetAttrPaths [
        (map addVersion)
        (lib.filter (pv: pv.version != null))
        (lib.groupBy (pv: pv.version))
        (lib.mapAttrs (version: pvs: map (pv: pv.path) pvs))
      ];

      annotateVersionPaths = version: paths:
        let
          canonicalPath = attrPathForVersion version;
          valid = lib.elem canonicalPath paths;
          aliases = lib.remove canonicalPath paths;
          result = {
            # If this package set is built in nixpkgs hydra, also build it ourselves
            recurse = lib.any (p: lib.attrByPath p { } releasePkgs != { })
              ([ canonicalPath ] ++ aliases);
            inherit canonicalPath aliases;
          };
        in if valid then result else null;

      versions = lib.filterAttrs (version: res: res != null)
        (lib.mapAttrs annotateVersionPaths versionPaths);

    in if pregenerate then {
      inherit versions;
    } else {
      inherit (pregenResult.packageSets.${setName}) versions;
      inherit callScopeAttr deepOverride;
    };

  packageSets = lib.mapAttrs packageSet {

    /* Each entry here needs these attributes:
       - versionForPackageSet :: PackageSet -> Version
         Returns the version for a package set, or null if no version could be determined
       - attrPathForVersion :: Version -> [String]
         Returns a nixpkgs attribute path at which the given version should be found
       - packageSetAttrPaths :: Attrs -> [[String]]
         Given a nixpkgs set, return all attribute paths that refer to a package set
       - callScopeAttr :: String
         The standard attribute that callPackage passes the package files as an argument for finding the package set
       - deepOverride :: PackageSet -> PackageSet
         Takes two package sets and deeply overrides the former to use all dependencies from the latter
         See https://github.com/flox/floxpkgs/blob/staging/docs/expl/deep-overrides.md#package-sets for why this is needed
    */

    pkgs = {

      versionForPackageSet = set: "none";

      attrPathForVersion = version: [ ];

      packageSetAttrPaths = [ [ ] ];

      callScopeAttr = null;

      deepOverride = set: overrides: set // overrides;
    };

    haskellPackages = {

      versionForPackageSet = set: set.ghc.version or null;

      attrPathForVersion = version:
        let
          parts = lib.versions.splitVersion version;
          attribute = "ghc${lib.elemAt parts 0}${lib.elemAt parts 1}${
              lib.elemAt parts 2
            }";
        in [ "haskell" "packages" attribute ];

      packageSetAttrPaths = let
        matches = name: builtins.match "ghc[0-9]*" name != null;
        names =
          lib.filter matches (lib.attrNames (pkgs.haskell.packages or { }));
        canonicalPaths = map (name: [ "haskell" "packages" name ]) names;
        aliases = [ [ "haskellPackages" ] ];
      in aliases ++ canonicalPaths;

      callScopeAttr = "haskellPackages";

      deepOverride = set: overrides:
        set.override (old: {
          overrides =
            lib.composeExtensions old.overrides (self: super: overrides);
        });

    };

    beamPackages = {

      versionForPackageSet = set: set.erlang.version or null;

      attrPathForVersion = version:
        let
          parts = lib.versions.splitVersion version;
          attribute = "erlangR${lib.elemAt parts 0}";
        in [ "beam" "packages" attribute ];

      packageSetAttrPaths = let
        matches = name: builtins.match "erlangR[0-9]*" name != null;
        names = lib.filter matches (lib.attrNames (pkgs.beam.packages or { }));
        paths = map (name: [ "beam" "packages" name ]) names;
        aliases = [ [ "beamPackages" ] ];
      in aliases ++ paths;

      callScopeAttr = "beamPackages";

      deepOverride = set: overrides: set.extend (self: super: overrides);

    };

    pythonPackages = {

      versionForPackageSet = set: set.python.version or null;

      attrPathForVersion = version:
        let
          parts = lib.versions.splitVersion version;
          attribute =
            "python${lib.elemAt parts 0}${lib.elemAt parts 1}Packages";
        in [ attribute ];

      packageSetAttrPaths = let
        matches = name: builtins.match "python[0-9]*Packages" name != null;
        names = lib.filter matches (lib.attrNames pkgs);
      in map lib.singleton names;

      callScopeAttr = "pythonPackages";

      deepOverride = set: overrides:
        set.override (old: {
          overrides =
            lib.composeExtensions old.overrides (self: super: overrides);
        });

    };

    perlPackages = {

      versionForPackageSet = set: set.perl.version or null;

      attrPathForVersion = version:
        let
          parts = lib.versions.splitVersion version;
          attribute = "perl${lib.elemAt parts 0}${lib.elemAt parts 1}Packages";
        in [ attribute ];

      packageSetAttrPaths = let
        matches = name: builtins.match "perl[0-9]*Packages" name != null;
        names = lib.filter matches (lib.attrNames pkgs);
      in map lib.singleton names;

      callScopeAttr = "perlPackages";

      deepOverride = set: overrides:
        set.override
        (old: { overrides = pkgs: old.overrides pkgs // overrides; });

    };
  };

in {
  inherit packageSets;
  version = 1;
}
