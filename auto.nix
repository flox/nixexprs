let

  # Given a directory and self/super, generate an attribute set where every
  # attribute corresponds to a subdirectory, which is autocalled with the given callPackage
  genPackageDirAttrs = dir: self: super: callPackage:
    let
      inherit (super) lib;
      # TODO: Warn or error or do something else for non-directories?
      subdirs = lib.attrNames (lib.filterAttrs (name: type: type == "directory") (builtins.readDir dir));
      subdirPackage = name: self.flox.utils.withVerbosity 4
        (builtins.trace "Auto-calling ${toString (dir + "/${name}")}")
        (callPackage (dir + "/${name}") {});
    in lib.genAttrs subdirs subdirPackage;

in {
  python = dir: self: super:
    let
      autoPythonPackages = version:
        let
          pythonPackages = "python${toString version}Packages";
        in {
          ${pythonPackages} = super.${pythonPackages}
            // { callPackage = super.lib.callPackageWith (self.flox.withChannelConfig { defaultPythonVersion = version; }); }
            # The callPackage within this package set should have the correct default python version
            # So instead of just using self directly, we use self with the channel config adjusted to what we need
            // genPackageDirAttrs dir self super self.${pythonPackages}.callPackage;
        };
    in autoPythonPackages 2 // autoPythonPackages 3 // {
      python = if self.flox.channelConfig ? defaultPythonVersion
        then self."python${toString self.flox.channelConfig.defaultPythonVersion}"
        else throw "Trying to access `python`, but no default python version has been defined for channel ${self.flox.channelName} or the channel it gets imported from";
      pythonPackages = if self.flox.channelConfig ? defaultPythonVersion
        then self."python${toString self.flox.channelConfig.defaultPythonVersion}Packages"
        else throw "Trying to access `pythonPackages`, but no default python version has been defined for channel ${self.flox.channelName} or the channel it gets imported from";
    };

  perl = dir: self: super: {
    perlPackages = super.perlPackages
      // { callPackage = super.lib.callPackageWith self; }
      // genPackageDirAttrs dir self super self.perlPackages.callPackage;
  };

  pkgs = dir: self: super: genPackageDirAttrs dir self super self.callPackage;
}
