{ pkgs, nixpkgs, repo, nixpkgs-pregen }:
let
  testRepo = pkgs.runCommandNoCC "repo" { } ''
    mkdir $out
    echo test > $out/file
    cp -r ${./repoDotGit} $out/.git
  '';
  otherRepo = pkgs.runCommandNoCC "other-repo" { } ''
    mkdir $out
    echo other > $out/file
    cp -r ${./repoDotGit} $out/.git
  '';
in {
  type = "eval-strict";
  stringArgs.testRepo = testRepo;
  stringArgs.otherRepo = otherRepo;
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
