{ flox, perlPackages }:
flox.perlPackages.buildPerlPackage {
  project = "testPackage";
  src = ./src;
  version = "1.0";
  buildInputs = [ perlPackages.ModuleInstall ];
  postBuild = "touch $devdoc";
}
