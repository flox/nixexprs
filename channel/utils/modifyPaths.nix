{ lib ? import <nixpkgs/lib> }:
let

  # Takes a super set and a list of paths that should be modified, returns a
  # new attribute set with the modifications done
  # Note that this function is as lazy as can be: It won't evaluate any
  # attributes to be overridden in the input set, and it won't recurse into
  # attributes that don't need to be overridden
  #
  # ListOf { path : [ String ], mod : Any -> Any } -> Attrs -> Attrs
  modifyPaths = let
    go = index: list: original:
      let
        # Splits modifications into ones on this level (split.right)
        # and ones on levels further down (split.wrong)
        split = lib.partition (el: lib.length el.path <= index) list;

        # groups modifications on further down levels into the attributes they modify
        grouped = lib.groupBy (el: lib.elemAt el.path index) split.wrong;

        # Recurses into the attribute set, passing the modifications for each attribute respectively
        withNestedMods =
          # Return the original if we don't have any nested modifications
          if lib.length split.wrong == 0 then
            original
            # Otherwise, map over the attribute set. We can assume it is an attribute
            # set because a modification that requires recursing into one was provided
          else
            lib.mapAttrs (name: go (index + 1) (grouped.${name} or [ ]))
            original;

        # We get the final result by applying all the modifications on this
        # level after having applied all the nested modifications
        result = lib.foldl' (acc: el: el.mod acc) withNestedMods split.right;
      in result;

  in go 0;

in { inherit modifyPaths; }
