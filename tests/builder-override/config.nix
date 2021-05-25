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
    "result/bin/tetris --help"
    "${jq}/bin/jq -e -n --argjson contents \"$(cat result/info.json)\" '$contents | .rev'"
  ];
}
