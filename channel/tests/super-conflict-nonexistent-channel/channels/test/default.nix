import <flox/channel> {
  topdir = ./.;
  dependencies = [ "other" ];
  conflictResolution.pkgs.testPackage = "florp";
}
