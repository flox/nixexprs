# Flox channel outputs

## Builders

See [builders](builders.md)

## `linkDotfiles <dir>`

Creates a derivation containing a `setup-dotfiles` script that links the files declared in `<dir>` into the users home directory. Files linked like this update automatically when the Nix profile updates. The setup script doesn't override any existing files.

#### Argument `<dir>` (path)

The directory containing the files to link to from the user home directory. A file at `<dir>/.bashrc` would be linked to from `$HOME/.bashrc`

#### Returns
A derivation containing:
- `/bin/setup-dotfiles [HOME]`: The binary that installs the dotfiles from `<dir>` into the users home directory. No files are overwritten, and subdirectories are created as needed. If an argument `HOME` is passed, the files are installed into that directory, instead of the users home.

## `removePathDups`

A setup hook that removes duplicates entries from common `PATH`-like environment variables, currently `PATH`, `PYTHONPATH` and `PERL5LIB`. To run this hook for a package, include it in its `buildInputs`.
