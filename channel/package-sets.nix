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

  utils = import ./utils { inherit lib; };

  withMatchedAttrs = path: regex: fun: lib.pipe (lib.getAttrFromPath path pkgs) [
    (lib.mapAttrsToList (name: value: {
      inherit name value;
      path = path ++ [ name ];
      matched = builtins.match regex name;
    }))
    (lib.filter (el: el.matched != null))
    (map fun)
  ];

  /* This function turns the attributes of each package set into a structure like

    {
      # Needed to know which channel directory to import, and for the default scope attribute
      callScopeAttr = ...;
      # Needed for knowing default versions
      versionTree = { ... };
      # These attributes are redacted for both the toplevel scope (overriding) and its channels (setting)
      packageSetAttrPaths = [ {
        # The path for this attribute
        path = [ ... ];
        # For which version prefix this attribute should be accessible
        versionPrefix = [ "3" "8" ];
        # Whether this version is recursed into
        recurse = <bool>;
      } ];
      # These attributes are additionally redacted for the toplevel scope
      extraNixpkgsAttrPaths = [ {
        # The path for this attribute
        path = [ ... ];
        # For which version prefix this attribute should be accessible
        versionPrefix = [ ... ];
        # What value this attribute path is set to
        valueAttrPath = [ ... ];
      } ];
      # How to deeply override this set
      deepOverride = ...;
      versions = {
        # How to get a nixpkgs package set for this version
        <version> = [ ... ];
          path = [ ... ];
          recurse = <bool>;
        };
      };
    }
  */
  packageSet = setName:
    { callScopeAttr, versionForPackageSet, attrPathForVersion, attrPaths, deepOverride }:
    let

      output = {
        inherit callScopeAttr deepOverride;
      };

      splitAttrPaths = lib.partition (el: el.valueAttrPath == []) attrPaths;

      processed = lib.pipe splitAttrPaths.right [
        (map (el: el // {
          version = versionForPackageSet (lib.getAttrFromPath el.path pkgs);
          recurse = lib.attrByPath el.path { } releasePkgs != { };
        }))
        (lib.groupBy (el: el.version))
        (lib.mapAttrs (version:
          lib.partition (el: el.path == attrPathForVersion version)
        ))
        (lib.filterAttrs (version: split: split.right != []))
        (lib.mapAttrs (version: split: {
          aliases = split.wrong;
          canonical = lib.head split.right;
        }))
      ];

      pregenOutput.versions = lib.mapAttrs (name: value: value.canonical.path) processed;

      packageAttrPaths = map (el: removeAttrs el [ "version" ]) (lib.concatLists (lib.mapAttrsToList (version: { aliases, canonical }: [ canonical ] ++ aliases) processed));
      nonPackageAttrPaths = lib.filter (el: utils.versionTreeLib.core.hasPrefix el.versionPrefix pregenOutput.versionTree) splitAttrPaths.wrong;

      pregenOutput.attrPaths = packageAttrPaths ++ nonPackageAttrPaths;

      pregenOutput.versionTree =
        let
          baseTree = utils.versionTreeLib.library.insertMultiple (lib.attrNames processed) utils.versionTreeLib.library.empty;
          final = lib.foldl' (acc: version:
            lib.foldl' (acc: el:
              utils.versionTreeLib.library.setDefault (lib.concatStringsSep "." el.versionPrefix) el.version acc
            ) acc processed.${version}.aliases
          ) baseTree (lib.attrNames processed);
        in final;

      #pregenAttrs = map (x: removeAttrs x [ "value" ]) nixpkgsAttrs;

      #final = lib.zipWith (a: b: a // b) nixpkgsAttrs pregenResult.${setName}.pregenAttrs;

    in if pregenerate then pregenOutput else pregenResult.${setName} // output;

in lib.mapAttrs packageSet {

  /* FIXME: Update this comment
    Each entry here needs these attributes:
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

  haskell = {

    callScopeAttr = "haskellPackages";

    versionForPackageSet = set: set.ghc.version or null;

    attrPathForVersion = version:
      let
        parts = lib.versions.splitVersion version;
        attribute =
          "ghc${lib.elemAt parts 0}${lib.elemAt parts 1}${lib.elemAt parts 2}";
      in [ "haskell" "packages" attribute ];

    attrPaths =
      let
        longestPrefix = list: match: if lib.hasPrefix (lib.concatStrings list) match then list else longestPrefix (lib.init list) match;

        packageSets = withMatchedAttrs [ "haskell" "packages" ] "ghc([0-9]+)" (el: {
          inherit (el) path;
          versionPrefix = longestPrefix (lib.versions.splitVersion el.value.ghc.version) (lib.head el.matched);
          valueAttrPath = [];
        });

        compilers = withMatchedAttrs [ "haskell" "compiler" ] "ghc([0-9]+)" (el: {
          inherit (el) path;
          versionPrefix = longestPrefix (lib.versions.splitVersion el.value.version) (lib.head el.matched);
          valueAttrPath = [ "ghc" ];
        });

      in packageSets ++ compilers ++ [
        {
          path = [ "haskellPackages" ];
          versionPrefix = [ ];
          valueAttrPath = [ ];
        }
        {
          path = [ "ghc" ];
          versionPrefix = [ ];
          valueAttrPath = [ "ghc" ];
        }
      ];

    deepOverride = set: overrides:
      set.override (old: {
        overrides =
          lib.composeExtensions old.overrides (self: super: overrides);
      });

  };

  erlang = {

    callScopeAttr = "beamPackages";

    versionForPackageSet = set: set.erlang.version or null;

    attrPathForVersion = version:
      let
        parts = lib.versions.splitVersion version;
        attribute = "erlangR${lib.elemAt parts 0}";
      in [ "beam" "packages" attribute ];

    attrPaths =
      let
        packageSets = withMatchedAttrs [ "beam" "packages" ] "erlangR([0-9]+)" (el: {
          inherit (el) path;
          versionPrefix = [ (lib.head el.matched) ];
          valueAttrPath = [];
        });

        interpreters = lib.concatLists (withMatchedAttrs [ "beam" "interpreters" ] "erlangR([0-9]+)" (el: [
          {
            inherit (el) path;
            versionPrefix = [ (lib.head el.matched) ];
            valueAttrPath = [ "erlang" ];
          }
          {
            path = [ el.name ];
            versionPrefix = [ (lib.head el.matched) ];
            valueAttrPath = [ "erlang" ];
          }
        ]));
      in packageSets ++ interpreters ++ [
        { path = [ "beamPackages" ]; versionPrefix = []; valueAttrPath = []; }
        { path = [ "beam" "packages" "erlang" ]; versionPrefix = []; valueAttrPath = []; }
        { path = [ "beam" "interpreters" "erlang" ]; versionPrefix = [ ]; valueAttrPath = [ "erlang" ]; }
        { path = [ "erlang" ]; versionPrefix = [ ]; valueAttrPath = [ "erlang" ]; }
        { path = [ "rebar" ]; versionPrefix = [ ]; valueAttrPath = [ "rebar" ]; }
        { path = [ "rebar3" ]; versionPrefix = [ ]; valueAttrPath = [ "rebar3" ]; }
      ];

    deepOverride = set: overrides: set.extend (self: super: overrides);

  };

  python = {

    callScopeAttr = "pythonPackages";

    versionForPackageSet = set: set.python.version or null;

    attrPathForVersion = version:
      let
        parts = lib.versions.splitVersion version;
        attribute = "python${lib.elemAt parts 0}${lib.elemAt parts 1}Packages";
      in [ attribute ];

    attrPaths = withMatchedAttrs [] "python([0-9]?)([0-9]+?)Packages" (el: {
      inherit (el) path;
      versionPrefix = lib.filter (match: match != "") el.matched;
      valueAttrPath = [];
    }) ++ withMatchedAttrs [] "python([0-9]?)([0-9]+?)" (el: {
      inherit (el) path;
      versionPrefix = lib.filter (match: match != "") el.matched;
      valueAttrPath = [ "python" ];
    });

    deepOverride = set: overrides:
      set.override (old: {
        overrides =
          lib.composeExtensions old.overrides (self: super: overrides);
      });

  };

  perl = {

    callScopeAttr = "perlPackages";

    versionForPackageSet = set: set.perl.version or null;

    attrPathForVersion = version:
      let
        parts = lib.versions.splitVersion version;
        attribute = "perl${lib.elemAt parts 0}${lib.elemAt parts 1}Packages";
      in [ attribute ];

    attrPaths = withMatchedAttrs [] "perl([0-9]?)([0-9]+?)Packages" (el: {
      inherit (el) path;
      versionPrefix = lib.filter (match: match != "") el.matched;
      valueAttrPath = [];
    }) ++ withMatchedAttrs [] "perl([0-9]?)([0-9]+?)" (el: {
      inherit (el) path;
      versionPrefix = lib.filter (match: match != "") el.matched;
      valueAttrPath = [ "perl" ];
    });

    deepOverride = set: overrides:
      set.override
        (old: { overrides = pkgs: old.overrides pkgs // overrides; });

  };

}
