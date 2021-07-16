{ jq, nixpkgs, repo, nixpkgs-pregen }: {
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
  postCommands = [
    "grep Hello <(result/bin/python -c 'import example; example.hello()')"
    "${jq}/bin/jq -e -n --argjson contents \"$(cat result/.flox.json)\" '$contents | .pname'"
  ];
}
