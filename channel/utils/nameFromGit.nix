# Infers the flox channel name by parsing .git/config in topdir
#
# Returns either { success = <string>; } if the channel name was uniquely identified
# Or { failure = <string>; } with a reason why it couldn't be determined
#
# It is important that this file never fails. Any error to during evaluation
# should make it return a failure
{ lib ? import <nixpkgs/lib> }:

let

  nameFromGit = topdir:
    let
      gitConfigPath = topdir + "/.git/config";
      exists = builtins.pathExists gitConfigPath;
      lines = lib.filter lib.isString
        (builtins.split "\n" (builtins.readFile gitConfigPath));

      parseHeader = line:
        let m = builtins.match ''\[([^ ]+)( "(.*)")?]'' line;
        in if m == null then
          m
        else if lib.elemAt m 2 == null then
          [ (lib.elemAt m 0) ]
        else [
          (lib.elemAt m 0)
          (lib.elemAt m 2)
        ];

      parseKeyValue = line:
        let m = builtins.match "[[:space:]]*([[:alnum:]-]+) = (.*)" line;
        in if m == null then m else { ${lib.elemAt m 0} = lib.elemAt m 1; };

      handleLine = { currentSection, result }:
        line:
        let
          header = parseHeader line;
          keyValue = parseKeyValue line;
        in if header != null then {
          currentSection = header;
          result = lib.recursiveUpdate result (lib.setAttrByPath header { });
        } else if keyValue != null then {
          inherit currentSection;
          result =
            lib.recursiveUpdate result (lib.setAttrByPath currentSection keyValue);
        } else {
          inherit currentSection result;
        };

      sections = (lib.foldl' handleLine {
        currentSection = [ ];
        result = { };
      } lines).result;

      floxpkgsRemotes = let
        remotes = lib.attrValues (sections.remote or { });

        parseFloxpkgsUrl = remote:
          let m = builtins.match ".*[:/](.*)/floxpkgs(\\.git)?" (remote.url or "");
          in if m == null then m else lib.elemAt m 0;

      in lib.unique (lib.filter (m: m != null) (map parseFloxpkgsUrl remotes));

      result = if lib.length floxpkgsRemotes == 0 then {
        failure = "No floxpkgs remotes found in Git config";
      } else if lib.length floxpkgsRemotes == 1 then {
        success = lib.elemAt floxpkgsRemotes 0;
      } else {
        failure = "Multiple floxpkgs remotes found in Git config";
      };

    in if exists then
      result
    else {
      failure = "Path ${toString gitConfigPath} does not exist";
    };
in {
  inherit nameFromGit;
}
