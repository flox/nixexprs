import <flox/channel> {
  topdir = ./.;
  dependencies = [ "bar" "test" ];
  conflictResolution.pkgs.testPackage = "bar";
}
