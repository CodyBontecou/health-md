import React from "react";
import { NativeModules } from "react-native";
import { runHostProbe } from "../dist/probe";

// The native ReactHost starts this packaged entry without AppRegistry or a surface.
const properties = typeof global.HermesInternal === "object" ? global.HermesInternal.getRuntimeProperties() : {};
void runHostProbe(NativeModules.NativeProbe, {
  react: React.version,
  hermes: typeof global.HermesInternal === "object",
  hermes_release: properties["OSS Release Version"],
  bytecode_version: properties["Bytecode Version"],
  engine_build: properties["Build"],
});
