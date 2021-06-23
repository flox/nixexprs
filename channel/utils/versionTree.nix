{ lib ? import <nixpkgs/lib> }:
let

  # TODO: Better errors with more context

  /*

  Types:
  - FullVersion = NonEmptyListOf String
    Represents a fully resolved version
  - VersionPrefix = ListOf String
  - Subversion = String
  - Tree = Final | Branch (NullOr VersionSelector) (AttrsOf Tree)
  - InsertError = OverlySpecific | UnderlySpecific
  - SetError = NoSuchPrefix VersionPrefix | NoSuchSubversion
  - QueryError = NoSuchPrefix VersionPrefix | NoDefault VersionPrefix

  Functions:
  - empty :: Tree
    New empty tree
  - insert :: FullVersion -> Tree -> { success :: Tree | failure :: InsertError }
    Insert full version (idempotent)
  - remove :: FullVersion -> Tree -> Tree
    Delete full version (idempotent)
  - setDefault :: VersionPrefix -> NullOr Subversion -> Tree -> { success :: Tree | failure :: SetError }
    Set a default version prefix (idempotent)
  - queryDefault :: VersionPrefix -> Tree -> { success :: FullVersion | failure :: QueryError }
    Query the full version for a version prefix

  */


  core = {

    empty = {
      default = null;
      versions = {};
    };

    insert = version: tree:
      assert lib.length version > 0;
      let
        go = head: tail: tree:
          if tail == [] then
            if ! tree.versions ? ${head} then
              tree // {
                versions = tree.versions // {
                  ${head} = null;
                };
              }
            else if tree.versions.${head} == null then
              builtins.trace "Already exists" tree
            else
              throw "Can't insert version ${head} since a more specific version already exists"
          else
            if ! tree.versions ? ${head} then
              tree // {
                versions = tree.versions // {
                  ${head} = go (lib.head tail) (lib.tail tail) core.empty;
                };
              }
            else if tree.versions.${head} == null then
              throw "Can't insert version ${head} since a less specific version already exists"
            else tree // {
              versions = tree.versions // {
                ${head} = go (lib.head tail) (lib.tail tail) tree.versions.${head};
              };
            };
      in go (lib.head version) (lib.tail version) tree;

    setDefault =
      let
        go = prefix: subversion: tree:
          if tree == null then throw "Too specific prefix"
          else if prefix == [] then
            if ! tree.versions ? ${subversion} then
              throw "Can't set default to version that doesn't exist"
            else tree // {
              default = subversion;
            }
          else
            if ! tree.versions ? ${lib.head prefix} then
              throw "Can't set default to version prefix that doesn't exist"
            else tree // {
              versions = tree.versions // {
                ${lib.head prefix} = go (lib.tail prefix) subversion tree.versions.${lib.head prefix};
              };
            };
      in go;

    queryDefault = let
      go = path: prefix: tree:
        if tree == null then path
        else if prefix == [] then
          if tree.default == null then
            if lib.length (lib.attrNames tree.versions) == 1 then
              let version = lib.elemAt (lib.attrNames tree.versions) 0;
              in go (path ++ [ version ]) prefix tree.versions.${version}
            else
              throw "No default for version prefix \"${lib.concatStringsSep "." path}\". Available versions are ${lib.generators.toPretty { multiline = false; } (lib.attrNames tree.versions)}"
          else go (path ++ [ tree.default ]) prefix tree.versions.${tree.default}
        else
          let
            head = lib.head prefix;
            newPath = path ++ [ head ];
          in
          if ! tree.versions ? ${head} then throw "Version prefix \"${lib.concatStringsSep "." newPath}\" doesn't exist"
          else go newPath (lib.tail prefix) tree.versions.${head};
    in go [];

    hasPrefix = prefix: tree:
      if prefix == [] then true
      else if tree == null then false
      else tree.versions ? ${lib.head prefix}
        && core.hasPrefix (lib.tail prefix) tree.versions.${lib.head prefix};

  };

  library = {

    empty = core.empty;

    # insertMultiple :: [ String ] -> Tree -> Tree
    insertMultiple = versions: tree: lib.foldl' (acc: el:
      core.insert (lib.versions.splitVersion el) acc
    ) tree versions;

    setDefault = prefix: version: tree:
      let
        prefixList = lib.versions.splitVersion prefix;
        versionList = lib.versions.splitVersion version;
        suffixList =
          if lib.lists.take (lib.length prefixList) versionList != prefixList
          then throw "setDefault called with prefix \"${prefix}\" which is not a prefix of the given version \"${version}\""
          else lib.lists.drop (lib.length prefixList) versionList;
        f = acc: el: {
          prefix = acc.prefix ++ [ el ];
          tree = core.setDefault acc.prefix el acc.tree;
        };
        initial = {
          prefix = prefixList;
          tree = tree;
        };
      in (lib.foldl' f initial suffixList).tree;

    clearDefault = prefix: tree:
      core.setDefault (lib.versions.splitVersion prefix) null tree;

    queryDefault = prefix: tree: lib.concatStringsSep "." (core.queryDefault (lib.versions.splitVersion prefix) tree);

    isVersionPrefixOf = a: b:
      let
        aList = lib.versions.splitVersion a;
        bList = lib.versions.splitVersion b;
      in lib.take (lib.length aList) bList == aList;

    hasPrefix = prefix: tree: core.hasPrefix (lib.versions.splitVersion prefix) tree;

  };


  test =
    let
      testVersions = [ "8.6.5" "8.8.2" "8.8.3" "8.8.4" "8.10.1" "8.10.2" "9.0.0" ];
    in library.setDefault "" "" (library.insertMultiple testVersions library.empty);

in {
  inherit core library test;
}
