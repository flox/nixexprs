auto:
self: super:
let
  inherit (super) lib;

  autoPkgs = import ./call.nix {
    inherit lib;
    withVerbosity = self.floxInternal.withVerbosity;
    path = auto.path;
    callPackage = lib.callPackageWith self.floxInternal.mainScope;
  };

in {
  floxInternal = super.floxInternal // {
    outputs = super.floxInternal.outputs
      // lib.optionalAttrs (auto ? path) autoPkgs;
  };
}
