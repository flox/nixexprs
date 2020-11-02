path:
self: super:
let
  inherit (super) lib;

  autoPkgs = import ./call.nix {
    inherit lib path;
    withVerbosity = self.floxInternal.withVerbosity;
    scope = self.floxInternal.mainScope;
    super = super;
  };

in {
  floxInternal = super.floxInternal // {
    outputs = super.floxInternal.outputs // autoPkgs;
  };
}
