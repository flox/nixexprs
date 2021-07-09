import <flox/channel> {
  topdir = ./.;
  dependencies = [ "other" ];
  conflictResolution.pkgs.buildGoModule = "other";
}
