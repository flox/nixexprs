{ lib ? import <nixpkgs/lib> }: {
  traceWith = (import ./tracing.nix { inherit lib; }).traceWith;
}
