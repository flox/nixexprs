{ meta, callPackage }:

{ channel ? meta.importingChannel, project, path, ... }@args:
let
  source = meta.getChannelSource channel project args;
  fullPath = source.src + "/${path}";
  fullPathChecked = if builtins.pathExists fullPath then
    fullPath
  else
    throw
    "File ${path} doesn't exist in source for project ${project} in channel ${meta.importingChannel}";
in callPackage fullPathChecked { } // {
  # flox edit should edit the path specified here
  _floxPath = fullPath;
}
