{ nixpkgs, repo, nixpkgs-pregen }: {
  type = "eval-strict";
  exitCode = 1;
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
      prefix = "file";
      path = ./file.nix;
    }
    {
      prefix = "nixpkgs-pregen";
      path = nixpkgs-pregen;
    }
  ];
}
