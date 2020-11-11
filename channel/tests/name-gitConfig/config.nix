{ pkgs }:
let
  channel = pkgs.runCommandNoCC "test-channel" {
    nativeBuildInputs = [ pkgs.gitMinimal ];
  } ''
    cp -r --no-preserve=mode ${./channels/test} $out
    git -C $out init
    git -C $out remote add real1 git@github.com:test/nixexprs.git
    git -C $out remote add real2 https://github.com/test/nixexprs.git
    git -C $out remote add real3 git@github.com:test/nixexprs
    git -C $out remote add real4 https://github.com/test/nixexprs
    git -C $out remote add fake1 git@github.com:foo/nixexprs-not.git
    git -C $out remote add fake2 git@github.com:foo/not-nixexprs.git
  '';
in {
  args = [ "--eval" ./expression.nix "--arg" "dir" channel ];
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
  ];
}
