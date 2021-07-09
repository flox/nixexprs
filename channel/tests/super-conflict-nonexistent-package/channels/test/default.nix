import <flox/channel> {
  topdir = ./.;
  dependencies = [ "florp" ];
  conflictResolution.pkgs.testPackage = "florp";
}
