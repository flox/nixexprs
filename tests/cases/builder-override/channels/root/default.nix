import <flox/channel> {
  topdir = ./.;
  conflictResolution.pkgs.mkDerivation = "builder";
}
