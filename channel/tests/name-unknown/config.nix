{ nixpkgs, repo, nixpkgs-pregen }: {
  type = "eval";
  stringArgs.dir = "${./channels/test}";
  exitCode = 0;
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
      prefix = "nixpkgs-pregen";
      path = nixpkgs-pregen;
    }
  ];
}
