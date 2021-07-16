{ nixpkgs, repo, nixpkgs-pregen }: {
  type = "build";
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
      prefix = "";
      path = ./channels;
    }
    {
      prefix = "nixpkgs-pregen";
      path = nixpkgs-pregen;
    }
  ];
  postCommands = [ "cat result/main.rs" ];
}
