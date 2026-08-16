import type { PracticeRuntimeMode } from "./contracts/api";

export interface PracticeEnvironmentInput {
  PRACTICE_RUNTIME_MODE?: string | undefined;
}

export interface PracticeEnvironment {
  mode: PracticeRuntimeMode;
}

export class PracticeConfigurationError extends Error {
  constructor() {
    super("Practice runtime configuration is unavailable");
    this.name = "PracticeConfigurationError";
  }
}

export function parsePracticeEnvironment(input: PracticeEnvironmentInput): PracticeEnvironment {
  if (input.PRACTICE_RUNTIME_MODE !== "synthetic") {
    throw new PracticeConfigurationError();
  }
  return { mode: "synthetic" };
}
