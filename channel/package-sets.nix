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

  versionTreeLib = (import ./defaultVersionTree.nix { inherit lib; }).library;

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
    { callScopeAttr, versionForPackageSet, attrPathForVersion, packageSetAttrPaths, extraNixpkgsAttrPaths, deepOverride }:
    let

      output = {
        inherit callScopeAttr deepOverride;
      };

      allVersions = lib.unique (map (el:
        versionForPackageSet (lib.getAttrFromPath el.path pkgs)
      ) packageSetAttrPaths);

      pregenOutput.versions = lib.genAttrs allVersions attrPathForVersion;

      pregenOutput.packageSetAttrPaths = map (el: el // {
        recurse = lib.attrByPath el.path { } releasePkgs != { };
      }) packageSetAttrPaths;

      pregenOutput.extraNixpkgsAttrPaths = extraNixpkgsAttrPaths;

      pregenOutput.versionTree =
        let
          baseTree = versionTreeLib.insertMultiple allVersions versionTreeLib.empty;
          final = lib.foldl' (acc: el:
            versionTreeLib.setDefault (lib.concatStringsSep "." el.versionPrefix) (versionForPackageSet (lib.getAttrFromPath el.path pkgs)) acc
          ) baseTree packageSetAttrPaths;
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

    packageSetAttrPaths = let
      packages = withMatchedAttrs [ "haskell" "packages" ] "ghc([0-9]+)" (el: {
        inherit (el) path;
        versionPrefix =
          let
            versionList = lib.versions.splitVersion el.value.ghc.version;
            go = list: if lib.hasPrefix (lib.concatStrings list) (lib.head el.matched) then list else go (lib.init list);
          in go versionList;
      });
    in packages;

    extraNixpkgsAttrPaths = let
      compilers = withMatchedAttrs [ "haskell" "compiler" ] "ghc([0-9]+)" (el: {
        inherit (el) path;
        versionPrefix =
          let
            versionList = lib.versions.splitVersion el.value.version;
            go = list: if lib.hasPrefix (lib.concatStrings list) (lib.head el.matched) then list else go (lib.init list);
          in go versionList;
        valueAttrPath = [ "ghc" ];
      });
    in compilers ++ [
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

    packageSetAttrPaths =
      let
        packages = withMatchedAttrs [ "beam" "packages" ] "erlangR([0-9]+)" (el: {
          inherit (el) path;
          versionPrefix = [ (lib.head el.matched) ];
        });
      in packages ++ [
        { path = [ "beam" "packages" "erlang" ]; versionPrefix = []; }
      ];

    extraNixpkgsAttrPaths =
      let
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

      in interpreters ++ [
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

    packageSetAttrPaths = withMatchedAttrs [] "python([0-9])([0-9]+?)Packages" (el: {
      inherit (el) path;
      versionPrefix = lib.filter (match: match != "") el.matched;
    });

    extraNixpkgsAttrPaths = withMatchedAttrs [] "python([0-9]?)([0-9]+?)" (el: {
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

    packageSetAttrPaths = withMatchedAttrs [] "perl([0-9])([0-9]+)Packages" (el: {
      inherit (el) path;
      versionPrefix = lib.filter (match: match != "") el.matched;
    });

    extraNixpkgsAttrPaths = withMatchedAttrs [] "perl([0-9]?)([0-9]+?)" (el: {
      inherit (el) path;
      versionPrefix = lib.filter (match: match != "") el.matched;
      valueAttrPath = [ "perl" ];
    });

    deepOverride = set: overrides:
      set.override
        (old: { overrides = pkgs: old.overrides pkgs // overrides; });

  };

}
