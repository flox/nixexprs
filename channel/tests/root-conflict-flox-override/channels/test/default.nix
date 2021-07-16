import <flox-lib/channel> {
  topdir = ./.;
  conflictResolution.pkgs.buildGoModule = "other";
}
