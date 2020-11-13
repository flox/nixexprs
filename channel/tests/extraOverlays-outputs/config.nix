{
  args = [ "--eval" ./expression.nix ];
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
