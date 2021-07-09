{ lib, trace, resolution, channels, rootFile, setName, pname
, resolutionNeededReason }:

let

  options = channels // {
    nixpkgs = if channels ? nixpkgs.valid && channels ? flox.valid then {
      invalid = "nixpkgs can't be selected for packages also provided by "
        + "the flox channel, since it provides a standard and "
        + "essential superset of nixpkgs functionality";
    } else
      channels.nixpkgs;
  };

  validOptions =
    lib.attrNames (lib.filterAttrs (option: result: result ? valid) options);

  inlineOptions = "[ "
    + lib.concatMapStringsSep ", " lib.strings.escapeNixString validOptions
    + " ]";

  multipleOptions =
    "However there are multiple channels which provide that package";

  invalidOption = "The conflict resolution is currently set to ${resolution}, "
    + "which is however not a valid option, because";

  lineOptions = lib.concatMapStrings (option: ''
    conflictResolution.${lib.strings.escapeNixIdentifier setName}.${
      lib.strings.escapeNixIdentifier pname
    } = ${lib.strings.escapeNixString option};
  '') validOptions;

  suggestion =
    "Valid options are ${inlineOptions}. Set the conflict resolution " + ''
      for this package in ${rootFile} by copying one of the following lines to it:
      ${lineOptions}'';

  invalidReasons = lib.concatStrings (lib.mapAttrsToList (channel: reason: ''
    - ${channel}: ${reason.invalid}
  '') options);

  result = if lib.length validOptions == 0 then
    throw ''
      ${resolutionNeededReason}. However, none of the channels are a valid option:
      ${invalidReasons}''

    # If a conflict resolution has been provided for this package,
    # use it, after ensuring it's a valid option
  else if resolution != null then
    if !options ? ${resolution} then
      throw
      "${resolutionNeededReason}. ${multipleOptions}. ${invalidOption} that channel doesn't exist. ${suggestion}"
    else if options.${resolution} ? invalid then
      throw "${resolutionNeededReason}. ${multipleOptions}. ${invalidOption} ${
        options.${resolution}.invalid
      }. ${suggestion}"
    else
      trace "resolution" 2
      "Resolving to ${resolution} because it was provided and ${
        options.${resolution}.valid
      }" resolution

      # If no conflict resolution has provided, but we only have a
      # single valid entry anyways, we can use that
  else if lib.length validOptions == 1 then
    trace "resolution" 2
    "We only have a single valid channel entry ${lib.head validOptions}"
    (lib.head validOptions)

    # Otherwise we throw an error that the conflict needs to be
    # resolved manually
  else
    throw
    "${resolutionNeededReason}. ${multipleOptions}. No conflict resolution is currently provided. ${suggestion}";

in trace "resolution" 1 "Valid options are ${inlineOptions}" result
