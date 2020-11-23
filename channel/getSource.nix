{ sourceOverrideJson, channel, lib, fetchgit }:
# Set the src and version variables based on project.
# Recall that flox calls this expression with --argstr sourceOverrideJson '{ ... }',
# so that needs to take precedence over all other sources of src.
project:
override:
  let
    srcs =
      if channel == "_unknown"
      then throw "Could not find source for project \"${project}\" because the channel name is unknown."
      else builtins.findFile builtins.nixPath "${channel}-meta/srcs";

    sourceOverrides = builtins.fromJSON sourceOverrideJson;
    isOverridden = sourceOverrides ? ${project};
    overriddenSource = builtins.fetchGit sourceOverrides.${project};

    _srcs_json_ = srcs + "/${project}.json";
    revdata = if builtins.pathExists _srcs_json_ then lib.importJSON _srcs_json_
      else throw "Could not find source for project \"${project}\" in channel \"${channel}\". Are webhooks for that repository set up?";
    _latest_ = revdata.latest;
    _srcs_ = revdata.srcs;

    # XXX temporarily construct branches using _latest_ if the json
    # data doesn't already have a branches hash.
    # _branches_ = revdata.branches;
    _branches_ = revdata.branches or { master = "${_latest_}"; };

    # Choose the source for this derivation from the "srcs" hash found
    # in the json data. If the user has provided the "rev" keyword then
    # look for that revision either by explicit revision or branch name,
    # and default to falling back to the revision referred to by the master
    # branch.
    _src_rev_ = if builtins.hasAttr "rev" override then (
      _branches_.${override.rev} or override.rev
    ) else (
      _branches_.master
    );
    _src_ = _srcs_.${_src_rev_} or (
      throw "could not find \"${_src_rev_}\" revision in ${_srcs_json_}"
    );

    # Select the version from the src's json metadata, but also allow it
    # to be overridden (by flox).
    origversion = ( override.version or (
      if builtins.hasAttr "version" _src_ then
         _src_.version
      else
        # Let "unknown" versions be *numeric* to prevent "nix-env --upgrade"
        # from interpreting the version as part of the package name.
        "0"
    ) );
    autoversion = if builtins.hasAttr "revision" _src_
      then (origversion + "-r" + builtins.toString _src_.revision) else origversion;
    autosrc = fetchgit {
      url = _src_.url;
      rev = _src_.rev;
      sha256 = _src_.sha256;
    };

  in rec {
    inherit project origversion autoversion;
    _src = if isOverridden then overriddenSource else override.src or autosrc;
    src = if isOverridden then overriddenSource else _src;

    version = if isOverridden then "manual" else autoversion;
    pname = (override.pname or project);
    name = pname + "-" + version;
    src_json =
      if isOverridden then
        builtins.toJSON {
          inherit project src version pname name;
          system = builtins.currentSystem;
        }
      else
        # Redact the "path" attribute from the latest source data - we don't
        # need it, and it causes the source package to be included in the
        # closure of runtime dependencies.
        builtins.toJSON (
          lib.attrsets.filterAttrs ( n: v: n != "path" ) _src_
        );
  }
