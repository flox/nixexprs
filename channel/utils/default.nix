{ lib ? import <nixpkgs/lib> }: {
  traceWith = (import ./tracing.nix { inherit lib; }).traceWith;
  modifyPaths = (import ./modifyPaths.nix { inherit lib; }).modifyPaths;
  nestedListToAttrs =
    (import ./nestedListToAttrs.nix { inherit lib; }).nestedListToAttrs;
  callPackageWith =
    (import ./callPackageWith.nix { inherit lib; }).callPackageWith;
  nameFromGit = (import ./nameFromGit.nix { inherit lib; }).nameFromGit;
  dirToAttrs = (import ./dirToAttrs.nix { inherit lib; }).dirToAttrs;
}
