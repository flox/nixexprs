import <flox/channel> {
  topdir = ./.;
  dependencies = [ "other" ];
  conflictResolution.pkgs.gnupg20 = "other";
}
