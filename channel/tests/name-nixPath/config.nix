{ nixpkgs, repo }: {
  type = "eval";
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
      prefix = "test";
      path = ./channels/test;
    }
  ];
}
