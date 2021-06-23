{ lib ? import <nixpkgs/lib> }:
let
  # Slighty broken
  #nestedListToAttrs =
  #  let
  #    prettyPath = el: lib.concatStringsSep "." el.path;

  #    go = index: list:
  #      let
  #        p = lib.partition (el: lib.length el.path <= index) list;
  #        rlen = lib.length p.right;
  #        nested = lib.mapAttrs (name: go (index + 1)) (lib.groupBy (el: lib.elemAt el.path index) list);

  #      in if rlen == 0 then nested
  #      else if rlen == 1 then
  #        let relem = lib.head p.right; in
  #        if p.wrong == [] then relem.value
  #        else if lib.isAttrs relem.value then
  #          let
  #            expandedRight = lib.mapAttrsToList (name: value: {
  #              path = relem.path ++ [ name ];
  #              value = value;
  #            }) relem.value;
  #          in go index (expandedRight ++ p.wrong)
  #        else
  #          throw "nestedListToAttrs: Conflict between ${prettyPath (lib.head p.wrong)} and ${prettyPath (lib.head p.right)}"
  #      else throw "nestedListToAttrs: Path ${prettyPath (lib.head p.right)} is set multiple times";
  #  in list: if list == []
  #    then throw "nestedListToAttrs: Empty input list"
  #    else go 0 list;

  # Not needed I think
  #getListAttr = attr: list:
  #  let attrs = lib.catAttrs attr list;
  #  in if attrs == []
  #  then throw "getListAttr: No such attribute ${attr}"
  #  else lib.last attrs;

  /* Sets a value at a specific attribute path, while merging the attributes along that path with the ones from super, suitable for overlays.

     Note: Because overlays implicitly use `super //` on the attributes, we don't want to have `super //` on the toplevel. We also don't want `super.<path> // <value>` on the lowest level, as we want to override the attribute path completely.

     Examples:
       overlaySet super [] value == value
       overlaySet super [ "foo" ] value == { foo = value; }
       overlaySet super [ "foo" "bar" ] value == { foo = super.foo // { bar = value; }; }
  */
  overlaySet = super: path: valueMod:
    let
      subname = lib.head path;
      subsuper = super.${subname};
      subvalue = subsuper // overlaySet subsuper (lib.tail path) valueMod;
    in if path == [ ] then valueMod super else { ${subname} = subvalue; };

  /* Same as setAttrByPath, except that lib.recurseIntoAttrs is applied to each path element, such that hydra recurses into the given value

     Examples:
       hydraSetAttrByPath recurse [] value = value
       hydraSetAttrByPath recurse [ "foo" ] value = { foo = value // { recurseIntoAttrs = recurse; }; }
       hydraSetAttrByPath recurse [ "foo" "bar" ] value = { foo = { recurseIntoAttrs = recurse; bar = value // { recurseIntoAttrs = recurse; }; }; }
  */
  hydraSetAttrByPath = recurse: attrPath: value:
    if attrPath == [ ] then
      value
    else {
      ${lib.head attrPath} =
        hydraSetAttrByPath recurse (lib.tail attrPath) value // {
          recurseForDerivations = recurse;
        };
      };

  updateAttrByPath = path: value:
    let
      go = index: set:
        let attr = lib.elemAt path index; in
        if lib.length path == index then value
        else set // {
          ${attr} = go (index + 1) (set.${attr} or {});
        };
    in go 0;

  updateAttrByPaths = list: set: lib.foldl' (acc: el: updateAttrByPath el.path el.value acc) set list;

  # Merges attribute sets recursively, but not recursing into derivations,
  # and error if a derivation is overridden with a non-derivation, or the other way around
  smartMerge = traceWithVerbosity: lib.recursiveUpdateUntil (path: l: r:
    let
      lDrv = lib.isDerivation l;
      rDrv = lib.isDerivation r;
      prettyPath = lib.concatStringsSep "." path;
      warning = "Overriding ${lib.optionalString (!lDrv) "non-"}derivation ${
          lib.concatStringsSep "." path
        } in nixpkgs"
        + " with a ${lib.optionalString (!rDrv) "non-"}derivation in channel";
    in if lDrv == rDrv then
    # If both sides are derivations, override completely
      if rDrv then
        traceWithVerbosity 7
          "[smartMergePath ${prettyPath}] Overriding because both sides are derivations"
        true
        # If both sides are attribute sets, merge recursively
      else if lib.isAttrs l && lib.isAttrs r then
        traceWithVerbosity 7
          "[smartMergePath ${prettyPath}] Recursing because both sides are attribute sets"
        false
        # Otherwise, override completely
      else
        traceWithVerbosity 7
          "[smartMergePath ${prettyPath}] Overriding because left is ${
            builtins.typeOf l
          } and right is ${builtins.typeOf r}" true
    else
      lib.warn warning true);

in {
  library = {
    inherit overlaySet hydraSetAttrByPath updateAttrByPath updateAttrByPaths smartMerge;
  };

  #test = nestedListToAttrs [
  #  { path = [ ]; value = { bar = 20; }; }
  #  { path = [ "bar" ]; value = 10; }
  #  { path = [ "baz" ]; value = 20; }
  #  { path = [ "qux" ]; value = 10; }
  #];
}
