import <flox/channel> {
  topdir = ./.;
  dependencies = [ "foo" "bar" ];
  conflictResolution.pkgs.testPackage = "foo";
}
