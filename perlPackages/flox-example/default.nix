{ flox, perlPackages }:

flox.builders.buildPerlPackage {
  project = "example-perl";
  buildInputs = [ perlPackages.ModuleInstall ];
  postBuild = "touch $devdoc";
}
