{ nixpkgs, repo, nixpkgs-pregen }: {
  type = "instantiate";
  stringArgs.dir = "${./channels/test}";
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
      prefix = "nixpkgs-pregen";
      path = nixpkgs-pregen;
    }
  ];
}
