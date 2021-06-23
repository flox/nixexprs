{ lib ? import <nixpkgs/lib> }: {
  inherit (import ./callPackageList.nix { inherit lib; }) callPackageList;
  inherit (import ./memoizeFunctionParameters.nix { inherit lib; }) memoizeFunctionParameters;
  nameFromGit = import ./nameFromGit.nix { inherit lib; };
  attrs = (import ./attrs.nix { inherit lib; }).library;
  versionTreeLib = (import ./versionTree.nix { inherit lib; }).library;
  inherit (import ./dirToAttrs.nix { inherit lib; }) dirToAttrs;
  scopeList = import ./scopeList.nix { inherit lib; };
}
