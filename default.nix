import <flox/channel> {
  topdir = ./.;
  #conflictResolution.pkgs.test = "infinisil";
  conflictResolution.pkgs.hello = "infinisil";
  conflictResolution.pkgs.gnupg = "infinisil";
  conflictResolution.pkgs.dotfiles = "flox-examples";
}
