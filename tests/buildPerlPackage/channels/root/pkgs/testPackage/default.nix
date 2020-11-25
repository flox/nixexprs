{ flox, perlPackages }:
flox.perlPackages.buildPerlPackage {
  project = "testPackage";
  src = ./src;
  buildInputs = [ perlPackages.ModuleInstall ];
  postBuild = "touch $devdoc";
}
