{ lib ? import <nixpkgs/lib> }: {
  modifyPaths = (import ./modifyPaths.nix { inherit lib; }).modifyPaths;
  nestedListToAttrs = (import ./nestedListToAttrs.nix { inherit lib; }).nestedListToAttrs;
  nameFromGit = (import ./nameFromGit.nix { inherit lib; }).nameFromGit;
  traceWith = (import ./tracing.nix { inherit lib; }).traceWith;
  dirToAttrs = (import ./dirToAttrs.nix { inherit lib; }).dirToAttrs;
}
