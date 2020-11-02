auto:
self: super:
let
  inherit (super) lib;

  autoPkgs = import ./call.nix {
    inherit lib;
    withVerbosity = self.floxInternal.withVerbosity;
    path = auto.path;
    scope = self.floxInternal.mainScope;
    super = super;
  };

in {
  floxInternal = super.floxInternal // {
    outputs = super.floxInternal.outputs
      // lib.optionalAttrs (auto ? path) autoPkgs;
  };
}
