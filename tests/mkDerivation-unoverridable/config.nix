{ jq, nixpkgs, repo }: {
  type = "build";
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
      prefix = "";
      path = ./channels;
    }
  ];
  postCommands = [ "result/bin/hello" "${jq}/bin/jq . result/.flox.json" ];
}
