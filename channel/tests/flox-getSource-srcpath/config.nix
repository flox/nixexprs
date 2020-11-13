{ pkgs }:
let
  repo = pkgs.runCommandNoCC "repo" {} ''
    mkdir $out
    echo 4 > $out/file
    cp -r ${./repoDotGit} $out/.git
  '';
in {
  args = [ "--eval" "--strict" "--arg" "repo" repo ./expression.nix ];
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
