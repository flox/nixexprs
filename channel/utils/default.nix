{ lib ? import <nixpkgs/lib> }: {
  modifyPaths = (import ./modifyPaths.nix { inherit lib; }).modifyPaths;
  nestedListToAttrs = (import ./nestedListToAttrs.nix { inherit lib; }).nestedListToAttrs;
  nameFromGit = (import ./nameFromGit.nix { inherit lib; }).nameFromGit;
}
