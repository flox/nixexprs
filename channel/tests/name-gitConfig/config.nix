{ pkgs, nixpkgs, repo }:
let
  channel = pkgs.runCommandNoCC "test-channel" {
    nativeBuildInputs = [ pkgs.gitMinimal ];
  } ''
    cp -r --no-preserve=mode ${./channels/test} $out
    git -C $out init
    git -C $out remote add real1 git@github.com:test/floxpkgs.git
    git -C $out remote add real2 https://github.com/test/floxpkgs.git
    git -C $out remote add real3 git@github.com:test/floxpkgs
    git -C $out remote add real4 https://github.com/test/floxpkgs
    git -C $out remote add fake1 git@github.com:foo/floxpkgs-not.git
    git -C $out remote add fake2 git@github.com:foo/not-floxpkgs.git
  '';
in {
  type = "eval";
  stringArgs.dir = channel;
  exitCode = 0;
  nixPath = [
    {
      prefix = "nixpkgs";
      path = nixpkgs;
    }
    {
      prefix = "flox";
      path = repo;
    }
    {
      prefix = "";
      path = ./channels;
    }
  ];
}
