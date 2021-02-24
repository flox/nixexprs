{ nixpkgs, repo }: {
  type = "eval-strict";
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
      prefix = "foo";
      path = ./foo;
    }
    {
      prefix = "";
      path = ./channels;
    }
    {
      prefix = "bar";
      path = ./bar;
    }
    {
      prefix = "";
      path = ./channels-alt;
    }
  ];
}
