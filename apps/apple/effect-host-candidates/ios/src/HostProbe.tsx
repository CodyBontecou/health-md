import React from "react";
import { NativeModules } from "react-native";
import { runHostProbe } from "../dist/probe";

// No AppRegistry registration, root view or React mount. Native starts the packaged engine.
const properties = typeof global.HermesInternal === "object" ? global.HermesInternal.getRuntimeProperties() : {};
void runHostProbe(NativeModules.NativeProbe, {
  react: React.version,
  hermes: typeof global.HermesInternal === "object",
  hermes_release: properties["OSS Release Version"],
  bytecode_version: properties["Bytecode Version"],
  engine_build: properties["Build"],
});
