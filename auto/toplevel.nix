self: super:
let
  inherit (super) lib;

  autoPkgs = import ./call.nix {
    inherit lib;
    withVerbosity = self.flox.withVerbosity;
    path = self.flox.auto.toplevel.path;
    callPackage = lib.callPackageWith self.flox.auto.toplevel.scope;
  };

in {
  flox = super.flox // {
    auto = super.flox.auto // {
      toplevel = super.flox.auto.toplevel // {
        # Merge the main scope and our own channels scope together recursively
        scope = lib.recursiveUpdateUntil (path: l: r: lib.isDerivation r) self self.flox.outputs;
      };
    };

    outputs = super.flox.outputs // lib.optionalAttrs (self.flox.auto ? toplevel.path) autoPkgs;
  };
}
