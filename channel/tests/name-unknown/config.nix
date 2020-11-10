{
  args = [ "--eval" ./expression.nix "--arg" "dir" ./channels/test ];
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
