{ flox }:
flox.buildRustPackage {
  project = "testPackage";
  src = ./src;
  version = "1.0";
  cargoSha256 = "12icc5mw4236dgfag5lrlgr8yjsv4a7sjpk23bh83py7wzyc8g4y";
}
