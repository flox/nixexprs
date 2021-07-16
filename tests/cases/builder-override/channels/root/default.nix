import <flox-lib/channel> {
  topdir = ./.;
  conflictResolution.pkgs.mkDerivation = "builder";
}
