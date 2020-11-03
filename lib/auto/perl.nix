self: super:
let
  inherit (super) lib;

  autoPkgs = import ./call.nix {
    inherit lib;
    withVerbosity = self.flox.withVerbosity;
    path = self.flox.auto.perl.path;
    callPackage = lib.callPackageWith self.flox.auto.perl.scope;
  };

in {
  flox = super.flox // {
    auto = super.flox.auto // {
      perl = super.flox.auto.perl or {} // {
        scope = self.flox.auto.toplevel.scope // self.flox.auto.toplevel.scope.perlPackages;
      };
    };

    outputs = super.flox.outputs // lib.optionalAttrs (self.flox.auto ? perl.path) {
      perlPackages = autoPkgs;
    };
  };
}
