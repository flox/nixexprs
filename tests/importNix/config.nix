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
    "result/bin/hello"
    "${jq}/bin/jq -e -n --argjson contents \"$(cat result/.flox.json)\" '$contents | .pname'"
  ];
}
