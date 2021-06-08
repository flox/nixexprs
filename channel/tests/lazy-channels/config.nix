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
      prefix = "multi";
      path = ./channels/multi-1;
    }
    {
      prefix = "multi";
      path = ./channels/multi-2;
    }
    {
      prefix = "root";
      path = ./channels/root;
    }
  ];
}
