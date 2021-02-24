{ meta, channels }: {
  result = {
    source = meta.getSource "testPackage" { };
    other = channels.other.testDep.result;
  };
}
