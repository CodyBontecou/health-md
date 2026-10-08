// Correctness checks only: suggestions about preferred syntax are not a development gate.
export const effectErrors = [
  "floatingEffect", "missingStarInYieldEffectGen", "missingEffectContext",
  "missingEffectError", "missingLayerContext", "unsafeEffectTypeAssertion",
  "promiseInEffectSuccess", "returnEffectInGen", "effectInVoidSuccess",
  "effectFnImplicitAny", "duplicatePackage", "outdatedApi",
];

export function effectPlugin(schema) {
  const rules = schema.definitions.effectLanguageServicePluginDiagnosticSeverityDefinition?.properties;
  if (!rules) throw new Error("Effect diagnostic schema changed; review the pinned tool");
  for (const name of effectErrors) if (!(name in rules)) throw new Error(`Unknown Effect rule: ${name}`);
  return {
    name: "@effect/language-service",
    diagnostics: true,
    includeSuggestionsInTsc: false,
    ignoreEffectSuggestionsInTscExitCode: true,
    ignoreEffectWarningsInTscExitCode: false,
    ignoreEffectErrorsInTscExitCode: false,
    noExternal: true,
    overrides: [],
    diagnosticSeverity: Object.fromEntries(Object.keys(rules).map(name => [name, effectErrors.includes(name) ? "error" : "off"])),
  };
}

// Each output's inputs are esbuild's transitive dependency closure, not filename guesses.
export function selectAffected(entries, graph, changed, componentPrefix) {
  if (changed.some(file => file.startsWith("packages/contracts/") || file.startsWith("scripts/typescript-dev/"))) return [...entries];
  const relevant = changed.filter(file => file.startsWith(`${componentPrefix}/`));
  if (componentPrefix === "apps/cli" && changed.some(file => file.startsWith("packages/healthmd-core-ts/"))) return [...entries];
  if (relevant.some(file => !file.startsWith(`${componentPrefix}/src/`) && !file.startsWith(`${componentPrefix}/tests/`))) return [...entries];
  const local = new Set(relevant.map(file => file.slice(componentPrefix.length + 1)));
  const known = new Set(Object.values(graph.outputs).flatMap(output => Object.keys(output.inputs)));
  // Deleted/new/otherwise unresolved code cannot safely narrow coverage.
  if ([...local].some(file => !known.has(file))) return [...entries];
  return entries.filter(entry => {
    const output = Object.values(graph.outputs).find(output => output.entryPoint === entry);
    if (!output) throw new Error(`Missing test dependency graph: ${entry}`);
    return Object.keys(output.inputs).some(file => local.has(file));
  });
}
