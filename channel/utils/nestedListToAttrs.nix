{ lib ? import <nixpkgs/lib> }:
let
  nestedListToAttrs =
    let
      prettyPath = el: "\"" + lib.concatStringsSep "." el.path + "\"";

      go = index: list:
        let
          split = lib.partition (el: lib.length el.path <= index) list;

          lowered = split.wrong ++ lib.concatMap (el:
            if ! lib.isAttrs el.value then throw "nestedListToAttrs: Conflict between paths ${prettyPath (lib.head split.wrong)} and ${prettyPath el}"
            else
            lib.mapAttrsToList (name: value: {
              path = el.path ++ [ name ];
              inherit value;
            }) el.value
          ) split.right;

          nested = lib.mapAttrs (name: go (index + 1)) (lib.groupBy (el: lib.elemAt el.path index) lowered);

        in
        if split.wrong != [] then nested
        else if lib.length split.right == 1 then (lib.head split.right).value
        else throw "nestedListToAttrs: Conflict between multiple values for path ${prettyPath (lib.head split.right)}";
    in list: if list == []
      then {}
      else go 0 list;


in {
  inherit nestedListToAttrs;

  test = nestedListToAttrs [
    { path = [ ]; value = { bar = 20; }; }
    { path = [ "arch" "foo" "florp" ]; value = 20; }
    { path = [ "arch" "foo" "florp" ]; value = 10; }
    { path = [ "qux" ]; value = 10; }
  ];
}
