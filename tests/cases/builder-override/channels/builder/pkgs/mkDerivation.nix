{ flox, meta }:
args:
flox.mkDerivation ({
  channel = meta.importingChannel;
} // args // {
  postInstall = args.postInstall or "" + ''
    ln -s .flox.json $out/info.json
  '';
})
