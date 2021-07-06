import <flox/channel> {
  topdir = ./.;
  dependencies = [ "builder" ];
  conflictResolution.pkgs.mkDerivation = "builder";
}
