/*
This file defines a nixpkgs overlay that does:
- Generate packages from ./pkgs, ./pythonPackages and ./perlPackages, and adds
  those to the respective package sets (pkgs, pkgs.python{2,3}Packages and pkgs.perlPackages)
- Expose all the generated packages (without everything else from pkgs) as pkgs.finalResult
*/
self: super:
let

  # Take lib from super to avoid infinite recursion
  inherit (super) lib;

  # Given a directory and self/super, generate an attribute set where every
  # attribute corresponds to a subdirectory, which is autocalled with the given callPackage
  genPackageDirAttrs = dir: callPackage:
    let
      # TODO: Warn or error or do something else for non-directories?
      subdirs = lib.attrNames (lib.filterAttrs (name: type: type == "directory") (builtins.readDir dir));
      subdirPackage = name: self.withVerbosity 4
        (builtins.trace "Auto-calling ${toString (dir + "/${name}")}")
        (callPackage (dir + "/${name}") {});
      attrs = lib.genAttrs subdirs subdirPackage;
    in if builtins.pathExists dir then attrs else {};

  # In an overlay, this function propagates the given attributes under `result`,
  # but taking their values from the given self, such that changes in future
  # overlays affects the result
  propagateResult = self: attrs: attrs // { result = builtins.intersectAttrs attrs self; };

  autoPythonPackages = version:
    let
      pythonPackages = "python${toString version}Packages";
    in {
      ${pythonPackages} = super.${pythonPackages}
        # The callPackage within this package set should have the correct default python version
        # So instead of just using self directly, we use self with the channel config adjusted to what we need
        // { callPackage = lib.callPackageWith (self.withChannelConfig { defaultPythonVersion = version; }); }
        // propagateResult self.${pythonPackages}
          (genPackageDirAttrs ./pythonPackages self.${pythonPackages}.callPackage);
    };

in propagateResult self (genPackageDirAttrs ./pkgs self.callPackage)
// autoPythonPackages 2
// autoPythonPackages 3
// {


  # The config for this channel. This is propagated down into all dependent channels
  # This makes sure that e.g. self.pythonPackages and self.<someChannel>.pythonPackages
  # refer to python3Packages if self.defaultPythonVersion is 3
  #
  # All overlays can access the config with `self.channelConfig.<property>` and change their output based on it
  channelConfig = {
    defaultPythonVersion = 2;
  };

  # Returns self, but with some channelConfig properties adjusted
  # E.g. `withChannelConfig { defaultPythonVersion = 3; }` makes sure the result refers has all python defaults set to 3
  withChannelConfig = config:
    # If the given properties already match the current config, just return self
    if builtins.intersectAttrs config self.channelConfig == config then self
    else
      # Otherwise override the current config with the new properties
      let newConfig = self.channelConfig // config;
      in self.withVerbosity 2
        (builtins.trace "Reevaluating channel `${self.channelName}` with new channel config: ${lib.generators.toPretty {} newConfig}")
        # And return self with an additional overlay that sets the new channelConfig
        (self.extend (_: _: { channelConfig = newConfig; }));

  # Override the ones in nixpkgs
  python = self."python${toString self.channelConfig.defaultPythonVersion}";
  pythonPackages = self."python${toString self.channelConfig.defaultPythonVersion}Packages";
  callPackage = lib.callPackageWith self;

  perlPackages = super.perlPackages
    // { callPackage = lib.callPackageWith self; }
    // propagateResult self.perlPackages
      (genPackageDirAttrs ./perlPackages self.perlPackages.callPackage);

  finalResult = self.result // {
    pythonPackages = self.pythonPackages.result;
    python2Packages = self.python2Packages.result;
    python3Packages = self.python3Packages.result;
    perlPackages = self.perlPackages.result;
  };

}
