import { readFileSync, chmodSync } from 'node:fs';
import { resolve, isAbsolute } from 'node:path';
import { pathToFileURL } from 'node:url';
import { LicensingService, canonicalEndpoint } from './service.mjs';
import { createRuntime } from './runtime.mjs';

export function readConfiguration(env=process.env) {
  const production=env.LICENSING_MODE==='production';
  if(!production&&env.LICENSING_MODE!=='local-pilot')throw new Error('Invalid licensing mode');
  const databasePath=env.LICENSING_DATABASE,issuer=env.LICENSING_ISSUER;
  if(!databasePath||!isAbsolute(databasePath)||!env.LICENSING_PRIVATE_KEY_FILE||
      canonicalEndpoint(issuer)!==issuer||!issuer.endsWith('/')||new URL(issuer).pathname!=='/')throw new Error('Invalid licensing configuration');
  const operatorTokens=env.LICENSING_OPERATOR_TOKENS_FILE ? JSON.parse(readFileSync(env.LICENSING_OPERATOR_TOKENS_FILE,'utf8')) : [env.LICENSING_OPERATOR_TOKEN];
  if(!Array.isArray(operatorTokens)||operatorTokens.length<1||operatorTokens.length>2||operatorTokens.some(x=>typeof x!=='string'||!/^[A-Za-z0-9_-]{32,128}$/.test(x)))throw new Error('Invalid operator credentials');
  if(production&&!env.LICENSING_OPERATOR_TOKENS_FILE)throw new Error('Production requires file-mounted credentials');
  const ingressKey=env.LICENSING_INGRESS_KEY_FILE ? readFileSync(env.LICENSING_INGRESS_KEY_FILE,'utf8').trim() : undefined;
  if(production&&(!/^[A-Za-z0-9_-]{43}$/.test(ingressKey||'')||!env.LICENSING_KEY_ID))throw new Error('Production trust configuration required');
  const port=(value,fallback)=>{const result=Number(value||fallback);if(!Number.isInteger(result)||result<1||result>65535)throw new Error('Invalid port');return result;};
  const publicPort=port(env.LICENSING_PORT,8792),controlPort=port(env.LICENSING_CONTROL_PORT,8793);
  if(publicPort===controlPort)throw new Error('Separate control port required');
  const host=env.LICENSING_HOST||'127.0.0.1';
  if(!['127.0.0.1','0.0.0.0'].includes(host)||(!production&&host!=='127.0.0.1'))throw new Error('Invalid listener address');
  return {databasePath,privateKey:readFileSync(env.LICENSING_PRIVATE_KEY_FILE,'utf8'),keyID:env.LICENSING_KEY_ID||'pilot-v1',
    issuer,operatorTokens,ingressKey,production,publicPort,controlPort,host};
}

export async function main(){
  process.umask(0o077);
  const configuration=readConfiguration();
  const service=new LicensingService(configuration);chmodSync(configuration.databasePath,0o600);
  if(service.db.prepare('PRAGMA quick_check').get().quick_check!=='ok'||service.db.prepare('PRAGMA foreign_key_check').all().length){service.close();throw new Error('Database integrity failed');}
  service.maintain();
  const runtime=createRuntime(service,{...configuration,onSummary:event=>process.stdout.write(JSON.stringify(event)+'\n')});
  await runtime.start();
  let closing=false;
  for(const signal of ['SIGINT','SIGTERM'])process.on(signal,async()=>{if(closing)return;closing=true;await runtime.close();service.close();});
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)main().catch(()=>{
  process.stderr.write('{"event":"licensing_startup_failed"}\n');process.exitCode=1;
});
