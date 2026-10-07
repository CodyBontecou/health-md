import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {createRequire} from "node:module";
import {mkdir, readFile, writeFile, rename, realpath} from "node:fs/promises";
import {resolve, relative} from "node:path";
import {build} from "esbuild";
import Metro from "metro";
const root = resolve(import.meta.dirname, "..");
const repo = resolve(root, "../../../..");
const require = createRequire(resolve(root, "package.json"));
const out = resolve(root, "ios/build/cold-intent");
const sha = (bytes) => createHash("sha256").update(bytes).digest("hex");
assert.equal(process.version, "v24.21.0");
assert.equal(process.env.HEALTHMD_COLD_SUPERVISED, "1", "bounded_runner_required_for_bundle");
const fixture = await readFile(resolve(root, "fixtures/cold-intent-v1.json"));
assert.equal(sha(fixture), "9bbb60feafff21385987fe01b1605aa5674507d207d689dd1cfac0dede8e9064");
const core = resolve(repo, "packages/healthmd-core-ts/dist/core/host-interfaces/capabilities.js");
const coreFaults = resolve(repo, "packages/healthmd-core-ts/dist/core/host-interfaces/faults.js");
const accepted = new Map([[core,"ae1516fb397db074c95fc14214b3a48f99192daa16f1d7ac00f047d9b1ed94ef"], [coreFaults,"662d61db6a41fcfa2fcc25c42c51a756bbedb7d1c06371832a191f853995b4a0"]]);
// The capabilities module is the only common operation used; no inherited autorun entry.
assert.equal(sha(await readFile(core)), accepted.get(core), "accepted_core_operation_drift");
const effectRoot = await realpath(resolve(root,"node_modules/effect"));
const reactRoot = await realpath(resolve(root,"node_modules/react"));
const inputs = [];
async function pin(path) {
  const physical = await realpath(path);
  if (physical.includes("/node_modules/effect/")) assert.ok(physical.startsWith(effectRoot+"/"),"duplicate_effect_root");
  if (physical.includes("/node_modules/react/")) assert.ok(physical.startsWith(reactRoot+"/"),"duplicate_react_root");
  assert.ok(!physical.endsWith("/HostProbe.tsx") && !physical.endsWith("/src/probe.ts"), "old_autorun_forbidden");
  if (!physical.startsWith(root+"/")) assert.ok(accepted.has(physical), "unadmitted_external_source");
  const hash=sha(await readFile(physical));
  if (accepted.has(physical)) assert.equal(hash,accepted.get(physical),"accepted_common_artifact_drift");
  return {path:relative(repo,physical),sha256:hash};
}
await mkdir(out,{recursive:true});
const portable = await build({absWorkingDir:root,entryPoints:["src/cold-intent-probe.ts"],outfile:resolve(out,"portable-audit.js"),bundle:true,format:"cjs",platform:"neutral",target:"es2022",metafile:true,external:["react","react-native"],plugins:[{name:"cold-explicit-common",setup(builder){
  builder.onResolve({filter:/^healthmd-candidate-capabilities$/},()=>({path:core}));
  builder.onResolve({filter:/^effect(?:\/|$)/},({path})=>({path:require.resolve(path)}));
}}]});
for (const path of Object.keys(portable.metafile.inputs).sort()) inputs.push(await pin(resolve(root,path)));
await writeFile(resolve(out,"esbuild-metafile.json"),JSON.stringify(portable.metafile,null,2)+"\n");
await writeFile(resolve(out,"source-inputs.json"),JSON.stringify(inputs,null,2)+"\n");
const config = await Metro.loadConfig({cwd:root,config:resolve(root,"metro.config.cjs")});
config.watchFolders=[...new Set([...config.watchFolders,resolve(repo,"packages/healthmd-core-ts/dist/core")])];
config.resolver.resolveRequest=(context,name,platform)=>name==="healthmd-candidate-capabilities" ? {type:"sourceFile",filePath:core} : name==="effect" || name.startsWith("effect/") ? {type:"sourceFile",filePath:require.resolve(name)} : context.resolveRequest(context,name,platform);
const base=require("metro/private/DeltaBundler/Serializers/baseJSBundle").default;
const stringify=require("metro/private/lib/bundleToString").default;
config.serializer.customSerializer=async (entry,prepend,graph,options)=>{
  assert.equal(options.dev,false,"production_prelude_required");
  const sdkPins=[];
  for (const [name,expected] of [
    ["getPreludeCode.js","9f1d9bdc49529b24329164ea7c83e985dcc45ebc587528f5bd99cbbd5ee0e10a"],
    ["getPrependedScripts.js","087a6f30ca2d8411d98de75feaabf27d34ec09266932dc8cadfd1bfeba8cd633"],
  ]) {
    const sdkPin=await pin(resolve(root,"node_modules/metro/src/lib",name));
    assert.equal(sdkPin.sha256,expected,"prelude_generator_drift");
    sdkPins.push(sdkPin);
  }
  const generatorOptions={isDev:false,globalPrefix:config.transformer.globalPrefix,
    requireCycleIgnorePatterns:config.resolver.requireCycleIgnorePatterns,
    unstable_forceFullRefreshPatterns:config.resolver.unstable_forceFullRefreshPatterns};
  const expectedPrelude=require(resolve(root,"node_modules/metro/src/lib/getPreludeCode.js")).default(generatorOptions);
  const virtual=prepend.filter((module)=>module.path==="__prelude__");
  assert.equal(virtual.length,1,"exactly_one_prelude_required");
  assert.ok(!graph.dependencies.has("__prelude__"),"prelude_must_be_prepend_only");
  const prelude=virtual[0];
  assert.equal(prelude.dependencies.size,0,"prelude_dependencies_forbidden");
  assert.equal(prelude.output.length,1,"prelude_output_count");
  assert.equal(prelude.output[0].type,"js/script/virtual","prelude_output_type");
  assert.equal(prelude.output[0].data.code,expectedPrelude,"prelude_code_drift");
  const preludeSource=prelude.getSource();
  assert.ok(Buffer.isBuffer(preludeSource) && preludeSource.equals(Buffer.from(expectedPrelude)),"prelude_source_drift");
  for (const module of [...prepend,...graph.dependencies.values()]) {
    if (module===prelude) continue;
    assert.ok(!module.output.some((output)=>output.type==="js/script/virtual"),"unknown_virtual_module");
  }
  const paths=[...new Set([...prepend.filter((module)=>module!==prelude).map((module)=>module.path),...graph.dependencies.keys()])].sort();
  const graphPins=[];
  for (const path of paths) graphPins.push(await pin(path));
  assert.ok(paths.some((p)=>p.startsWith(reactRoot+"/")),"missing_physical_react");
  assert.ok(paths.some((p)=>p.startsWith(effectRoot+"/")),"missing_physical_effect");
  await writeFile(resolve(out,"metro-inputs.json"),JSON.stringify({physical_inputs:graphPins,virtual_inputs:[{path:"__prelude__",type:"js/script/virtual",bytes:preludeSource.length,sha256:sha(preludeSource),generator_options:{...generatorOptions,extraVars:"omitted_by_getPrependedScripts",requireCycleIgnorePatterns:generatorOptions.requireCycleIgnorePatterns.map(String),unstable_forceFullRefreshPatterns:generatorOptions.unstable_forceFullRefreshPatterns.map(String)},generator_physical_inputs:sdkPins}]},null,2)+"\n");
  return stringify(base(entry,prepend,graph,options)).code;
};
await Metro.runBuild(config,{entry:"src/cold-intent-probe.ts",out:resolve(out,"main.jsbundle"),dev:false,minify:true,platform:"ios"});
await rename(resolve(out,"main.jsbundle.js"),resolve(out,"main.jsbundle"));
await writeFile(resolve(out,"asset-sha256.json"),JSON.stringify({fixture:sha(fixture),metro_asset:sha(await readFile(resolve(out,"main.jsbundle"))),physical_effect:effectRoot,physical_react:reactRoot},null,2)+"\n");
