{ nixpkgs, repo, nixpkgs-pregen }: {
  type = "eval";
  exitCode = 1;
  nixPath = [
    {
      prefix = "nixpkgs";
      path = nixpkgs;
    }
    {
      prefix = "flox-lib";
      path = repo;
    }
    {
      prefix = "";
      path = ./channels;
    }
    {
      prefix = "nixpkgs-pregen";
      path = nixpkgs-pregen;
    }
  ];
}
