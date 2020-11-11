{
  args = [ "--eval" ./expression.nix ];
  exitCode = 1;
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
