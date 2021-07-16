{ pkgs, nixpkgs, repo, nixpkgs-pregen }:
let
  testRepo = pkgs.runCommandNoCC "repo" { } ''
    mkdir $out
    echo 4 > $out/file
    cp -r ${./repoDotGit} $out/.git
  '';
in {
  type = "eval-strict";
  stringArgs.repo = testRepo;
  exitCode = 0;
  nixPath = [
    {
      prefix = "nixpkgs";
      path = nixpkgs;
    }
    {
      prefix = "flox-lib";
      path = repo;
    }
    {
      prefix = "";
      path = ./channels;
    }
    {
      prefix = "nixpkgs-pregen";
      path = nixpkgs-pregen;
    }
  ];
}
