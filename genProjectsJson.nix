#
# genProjectsJson.nix: generate project-to-attribute mappings in JSON
#
# This script is invoked with each update to the nixexprs repository in
# order to update the top-level projects.json file used by flox to
# identify which expressions are built from which project. Invoke with:
#
# % nix-instantiate -E --eval --strict "import ./genProjectsJson.nix { channel_json = ./path/to/channel.json; }" | jq -r . | jq .
#
# Souvik Sen, Michael Brantley
# Fri Aug  9 15:49:39 EDT 2019
#

{ lib ? import <nixpkgs/lib>
, channel_json
}:

let
  channel = ./.;
  attributes = import channel {
    inherit channel_json;
  };

  # Generate attrName/projectName tuples for top-level packages
  # containing "project" attribute.
  top_level_mappings = map (x: {
    attrName = x;
    projectName = attributes.${x}.project;
  }) (
    builtins.filter (x: builtins.hasAttr "project" attributes.${x}) (
      builtins.attrNames attributes
    )
  );

  # Function to generate attrName/projectName tuples for packages
  # of a sub-namespace (e.g. "perlPackages", "pythonPackages").
  genMapping = namespace:
    let
      pkglist = builtins.filter (x:
        builtins.hasAttr "project" attributes.${namespace}.${x}
      ) ( builtins.attrNames attributes.${namespace} );
    in
      map (x: {
        attrName = namespace + "." + x;
        projectName = attributes.${namespace}.${x}.project;
      }) pkglist;

  # Use above function to compute mapping of sub-namespace packages
  # containing "project" attribute.
  nested_mappings = map (x: genMapping x) [
    "perlPackages"
    "python2Packages"
    "python3Packages"
  ];

in
  # Print JSON output using the foldAttrs() method to merge the
  # projectName->attrName tuples rendered by map().
  builtins.toJSON (
    lib.attrsets.foldAttrs (n: a: [n] ++ a) [] (
      map (x: {
        ${x.projectName} = x.attrName;
      }) ( lib.lists.flatten(nested_mappings) ++ top_level_mappings )
    )
  )
