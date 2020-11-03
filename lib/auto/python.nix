self: super:
let
  inherit (super) lib;

  pythonPackages = version: import ./call.nix {
    inherit lib;
    withVerbosity = self.flox.withVerbosity;
    path = self.flox.auto.python.path;
    callPackage =
      let scope = (self.flox.auto.python.withDefaultVersion version).flox.auto.python.scope;
      in lib.callPackageWith scope;
  };

in {
  flox = super.flox // {

    auto = super.flox.auto // {
      python = super.flox.auto.python or {} // {
        # A function to return the main scope, but with the default python version changed
        withDefaultVersion = newVersion:
          if self.flox.auto.python.defaultVersion or "" == newVersion then self
          else self.extend (self: super: lib.recursiveUpdate super {
            flox.auto.python.defaultVersion = newVersion;
          });

        scope = self.flox.auto.toplevel.scope // self.flox.auto.toplevel.scope.pythonPackages // {
          python = self."python${toString self.flox.auto.python.defaultVersion}";
          pythonPackages = self.flox.auto.toplevel.scope.pythonPackages;
        };
      };
    };

    outputs = super.flox.outputs // (lib.optionalAttrs (self.flox.auto ? python.path) {
      python2Packages = pythonPackages 2;
      python3Packages = pythonPackages 3;
    } // lib.optionalAttrs (self.flox.auto ? python.defaultVersion) {
      pythonPackages = self.flox.outputs."python${toString self.flox.auto.python.defaultVersion}Packages";
    });

    channels = lib.mapAttrs (name: channel:
      channel // lib.optionalAttrs (self.flox.auto ? python.defaultVersion && channel ? "python${toString self.flox.auto.python.defaultVersion}Packages") {
        # If we have a default python version set, and the channel has python${version}Packages, set pythonPackages to that
        pythonPackages = channel."python${toString self.flox.auto.python.defaultVersion}Packages";
      }
    ) super.flox.channels;
  };
}
