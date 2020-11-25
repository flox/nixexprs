{ flox }:
flox.buildRustPackage {
  project = "testPackage";
  src = ./src;
  cargoSha256 = "0mq8zn9f2hm4kf0v3m789b1i6irfjs8hq84x3f3p74vqp70nxsv4";
}
