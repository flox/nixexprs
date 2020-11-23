{ pkgs }:
let
  testRepo = pkgs.runCommandNoCC "repo" {} ''
    mkdir $out
    echo test > $out/file
    cp -r ${./repoDotGit} $out/.git
  '';
  otherRepo = pkgs.runCommandNoCC "other-repo" {} ''
    mkdir $out
    echo other > $out/file
    cp -r ${./repoDotGit} $out/.git
  '';
in {
  args = [ "--eval" "--strict" "--arg" "testRepo" testRepo "--arg" "otherRepo" otherRepo ./expression.nix ];
  exitCode = 0;
  nixPath = { nixpkgs, flox }: [
    {
      prefix = "nixpkgs";
      path = nixpkgs;
    }
    {
      prefix = "flox";
      path = flox;
    }
    {
      prefix = "";
      path = ./channels;
    }
  ];
}
