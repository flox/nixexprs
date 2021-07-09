{ testPackage, channels }: {
  result = {
    own.testPackage.importingChannel = testPackage.result.importingChannel;
    other.rootPackage.importingChannel =
      channels.test.testRootPackage.importingChannel;
    other.testPackage.importingChannel =
      channels.test.testTestPackage.importingChannel;
  };
}
