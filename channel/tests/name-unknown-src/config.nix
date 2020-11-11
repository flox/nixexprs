{
  args = [ ./expression.nix "--arg" "dir" ./channels/test ];
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
  ];
}
