{ flox, meta }:
let
  mockedGetSource = meta.getSource.override {
    fetchgit = args: builtins.trace "fetchgit called" args;
  };
in { result = mockedGetSource "testPackage" { }; }
