{
  args = [ "--eval" "--strict" ./expression.nix ];
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
      prefix = "foo";
      path = ./foo;
    }
    {
      prefix = "";
      path = ./channels;
    }
    {
      prefix = "bar";
      path = ./bar;
    }
    {
      prefix = "";
      path = ./channels-alt;
    }
  ];
}
