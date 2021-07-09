import <flox/channel> {
  topdir = ./.;
  dependencies = [ "other" ];
  conflictResolution.pythonPackages.toml = "other";
}
