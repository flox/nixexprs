{ runCommandNoCC, which, runtimeShell }:
dir:
runCommandNoCC "setup-dotfiles" {
  script = ''
    #!${runtimeShell}
    if ! binPath=$(${which}/bin/which setup-dotfiles 2>/dev/null); then
      echo "setup-dotfiles needs to be available from PATH to work" >&2
      exit 1
    fi

    if [[ "$(realpath "$binPath")" != ${placeholder "out"}/bin/setup-dotfiles ]]; then
      echo "The setup-dotfiles found on PATH isn't the one that's called" >&2
      exit 1
    fi

    sourcePath=$(dirname "$(dirname "$binPath")")/share/dotfiles
    targetPath=''${1:-$HOME}

    echo "Establishing dotfile symlinks from $sourcePath in $targetPath"
    cp --recursive --no-clobber --verbose --dereference \
      --symbolic-link --no-target-directory --no-preserve=mode \
      "$sourcePath" "$targetPath"
  '';

  passAsFile = [ "script" ];
} ''
  mkdir -p $out/bin $out/share
  cp -r ${dir} $out/share/dotfiles
  mv "$scriptPath" $out/bin/setup-dotfiles
  chmod +x $out/bin/setup-dotfiles
''
