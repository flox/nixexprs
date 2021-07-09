{ nixpkgs, repo, nixpkgs-pregen }: {
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
      prefix = "nixpkgs-pregen";
      path = nixpkgs-pregen;
    }
  ];
}
