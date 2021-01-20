{ nixpkgs, repo }: {
  type = "eval";
  stringArgs.dir = "${./channels/test}";
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
  ];
}
