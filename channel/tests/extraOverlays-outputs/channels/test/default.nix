import <flox/channel> {
  topdir = ./.;
  extraOverlays = [(self: super: {
    floxInternal = super.floxInternal // {
      outputs = super.floxInternal.outputs // {
        overlayOutput = "This is an overlay output, the testPackage result is ${self.floxInternal.outputs.testPackage.result}";
      };
    };
  })];
}
