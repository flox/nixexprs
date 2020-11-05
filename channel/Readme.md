# Nixexprs Channel Creation

This document describes how nixexprs channels are created and evaluated, as implemented by this directory.

## What are nixexprs channels

A nixexprs channel is a nixexprs repository on GitHub that imports and calls this directory in its default.nix file. By default the resulting Nix expression is a recursive set of derivations that mirrors nixpkgs. The main way for channels to declare derivations in their result is to create files in a set of predefined directories. Channels can depend on derivations from nixpkgs, themselves, or other channels.

## Evaluation root

Even though evaluation is issued from a specific channel's nixexprs repository, that channel is treated pretty much* the same as any other channel. In fact, it would be possible to write a wrapper that evaluates a specific channel without requiring a default.nix in the channel's repository. The main purpose of keeping the default.nix is to allow evaluation similar to nixpkgs itself, with commands like `nix-build -A <package>` working in the repository root.
