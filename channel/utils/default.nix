{ lib ? import <nixpkgs/lib> }: {
  traceWith = (import ./tracing.nix { inherit lib; }).traceWith;
  modifyPaths = (import ./modifyPaths.nix { inherit lib; }).modifyPaths;
  nestedListToAttrs =
    (import ./nestedListToAttrs.nix { inherit lib; }).nestedListToAttrs;
}
