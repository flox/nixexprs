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
  postCommands = [
    "grep Hello <(result/bin/python -c 'import example; example.hello()')"
    "${jq}/bin/jq . result/.flox.json"
  ];
}
