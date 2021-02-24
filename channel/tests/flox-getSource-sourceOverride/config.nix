{ pkgs, nixpkgs, repo }:
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
      prefix = "flox";
      path = repo;
    }
    {
      prefix = "";
      path = ./channels;
    }
  ];
}
