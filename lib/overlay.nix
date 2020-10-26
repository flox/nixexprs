self: super: {

  floxSetSrcVersion = self.callPackage ./floxSetSrcVersion.nix { };
  removePathDups = self.makeSetupHook {} ./setup-hooks/removePathDups.sh;

  # flox custom builders & stuff (in future).
  flox = {
    mkDerivation = self.callPackage ./mkDerivation.nix { };
    buildGoPackage = self.callPackage ./buildGoPackage.nix { };
    # Will deprecate buildGoPackage when everyone migrates to Go modules.
    buildGoModule = self.callPackage ./buildGoModule.nix { };
    buildErlangMk = self.callPackage ./buildErlangMk.nix { };
    buildPerlPackage = self.callPackage ./buildPerlPackage.nix { };

    buildPythonPackage = self.pythonPackages.callPackage ./buildPythonPackage.nix {};
    buildPythonApplication = self.flox."buildPython${toString self.channelConfig.defaultPythonVersion}Application";

    buildPython2Application = self.python2Packages.callPackage ./buildPythonApplication.nix {};
    buildPython3Application = self.python3Packages.callPackage ./buildPythonApplication.nix {};
  };

}
