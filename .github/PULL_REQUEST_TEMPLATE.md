<!--

Thank you for your contribution!

To keep this project of high quality, please make sure to tick all the
following boxes before sending your pull request.

Your pull request will automatically have its tests run and spelling checked,
but if you would like to run these checks locally, you can do so:

Run your tests locally with:

    nix-build channel/tests && ./result
    nix-build tests && ./result

Check the spelling of your documentation with codespell:

    git ls-files | nix-shell -p findutils codespell --run "xargs codespell -q 2"

Reformat your changes with nixfmt:

    git ls-files | grep '.nix$' | nix-shell -p findutils nixfmt --run "xargs nixfmt"

-->

- [ ] I have created a test to cover the new behavior.
- [ ] I have written and updated relevant documentation, including updating this
      pull request template if necessary. Note that we try to follow the
      [Divio documentation](https://documentation.divio.com/) of documentation.

