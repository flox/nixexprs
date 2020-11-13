import <flox/channel> {
  topdir = ./.;
  extraOverlays = [(self: super: {
    ncurses = throw "This is overlay!";
  })];
}
