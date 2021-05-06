dir:
let

  repo = ../.;

  nixpkgs = fetchTarball {
    url =
      "https://github.com/NixOS/nixpkgs/archive/a52e974cff8fb80c427e0d55c01b3b8c770ccec4.tar.gz";
    sha256 = "0yhcnn435j9wfi1idxr57c990aihg0n8605566f2l8vfdrz7hl7d";
  };

  pkgs = import nixpkgs {
    config = { };
    overlays = [ ];
  };
  inherit (pkgs) lib;

  createNixPath = entries:
    lib.concatMapStringsSep ":"
    ({ prefix, path }: if prefix == "" then path else prefix + "=" + path)
    entries;

  /* - type (build | eval | eval-strict | eval-json, required): Type
     - exitCode (int, required): Expected exit code
     - nixPath (list of { prefix, path }, default []): NIX_PATH entries
     - file (path, default "${path}/expression.nix"): File to evaluate
     - stringArgs (attrs of strings, default {}): Arguments to pass with --argstr
     - stdoutMatchPath (path, default "${path}/stdout"): File that should match stdout
     - stderrMatchPath (path, default "${path}/stderr"): File that should match stderr
  */
  readConfig = path:
    let
      configValue = import (path + "/config.nix");
      unchecked = if lib.isFunction configValue then
        pkgs.callPackage configValue { inherit nixpkgs repo; }
      else
        configValue;
      checker = { type, exitCode, nixPath ? [ ], file ? path + "/expression.nix"
        , stringArgs ? { }, stdoutMatchPath ? path + "/stdout"
        , stderrMatchPath ? path + "/stderr", nixOptions ? { }
        , postCommands ? [ ], overrideDerivation ? null, override ? null }: {
          inherit type exitCode nixPath file stringArgs stdoutMatchPath
            stderrMatchPath nixOptions postCommands;
        };
    in checker unchecked;

  configCommand = config:
    let
      base = {
        build = "nix-build";
        instantiate = "nix-instantiate";
        eval = "nix-instantiate --eval";
        eval-strict = "nix-instantiate --eval --strict";
        eval-json = "nix-instantiate --eval --strict --json";
      }.${config.type} or (throw "No such type ${config.type}");

      binary = "${lib.getBin pkgs.nix}/bin/${base}";

      nixPath = "NIX_PATH=${lib.escapeShellArg (createNixPath config.nixPath)}";

      args = lib.mapAttrsToList (name: value:
        "--argstr ${lib.escapeShellArg name} ${lib.escapeShellArg value}")
        config.stringArgs;

      options = lib.mapAttrsToList (name: value:
        "--option ${lib.escapeShellArg name} ${lib.escapeShellArg value}")
        config.nixOptions;
      parts = [ nixPath binary config.file ] ++ args ++ options;
    in lib.concatStringsSep " " parts;

  # Returns a script that runs a test. Assumes a usable nix is in PATH
  testScript = name: path:
    let
      config = readConfig path;
      command = configCommand config;

      check = expected: file:
        lib.optionalString (builtins.pathExists expected) ''
          while IFS="" read -r line || [[ -n $line ]]; do
            if ! grep -xF -e "$line" ${file} >/dev/null && ! grep -x -e "$line" ${file} >/dev/null; then
              echo -e '\033[0;31m'
              echo "Expected ${file} to contain line"
              echo "$line"
              echo "But it doesn't"
              fail
            fi
          done < ${expected}
        '';

    in pkgs.writeShellScript "test-${name}" ''
      set -euo pipefail

      exec > >(sed "s/^/[${name}] /")
      exec 2> >(sed "s/^/[${name}] /" >&2)

      cd "$(mktemp -d)"

      fail() {
        echo "stdout is"
        cat stdout
        echo "stderr is"
        cat stderr
        echo "Directory is $PWD"
        echo -e "Test ${name} failed\033[0m"
        exit 1
      }

      echo ${lib.escapeShellArg command}
      set +e
      ${command} >stdout 2>stderr
      exitCode=$?
      set -e
      if [[ "$exitCode" -ne "${toString config.exitCode}" ]]; then
        echo -e '\033[0;31m'
        echo "Expected exit code ${toString config.exitCode} but got $exitCode"
        fail
      fi
      ${check config.stdoutMatchPath "stdout"}
      ${check config.stderrMatchPath "stderr"}

      ${lib.concatMapStringsSep "\n" (postCommand: ''
        echo ${lib.escapeShellArg postCommand}
        if ! ${postCommand} >stdout 2>stderr; then
          echo -e '\033[0;31m'
          echo "Post command failed"
          fail
        fi
      '') config.postCommands}
      echo "Test ${name} succeeded"
    '';

  testScripts = lib.mapAttrs (name: value: testScript name (dir + "/${name}"))
    (lib.filterAttrs (name: type: type == "directory") (builtins.readDir dir));

  singleScript = pkgs.writeShellScript "test-${baseNameOf dir}" ''
    echo "Testing directory ${toString dir}"
    count=0
    successCount=0

    ${lib.concatMapStringsSep "\n" (script: ''
      count=$(( count + 1 ))
      if ${script}; then
        successCount=$(( successCount + 1 ))
      fi
    '') (lib.attrValues testScripts)}

    echo "Successfully ran $successCount of $count tests"
    if [[ "$count" -ne "$successCount" ]]; then
      exit 1
    fi
  '';

in singleScript // { inherit testScripts; }
