import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {createFlyIngress} from '../src/fly-ingress.mjs';
import {checkHealth,authorized} from '../ops-worker/src/worker.mjs';

test('Fly ingress isolates control, overwrites trust headers and bounds bodies',async()=>{
 let captured;
 const backend=createServer((req,res)=>{captured=req.headers;req.resume();req.on('end',()=>res.end('{"ok":true}'));});
 await new Promise(resolve=>backend.listen(0,'127.0.0.1',resolve));
 const ingress=createFlyIngress({issuer:'https://licensing.healthmd.app/',ingressKey:'s'.repeat(43),backendPort:backend.address().port,operationalHealth:()=>false});
 await new Promise(resolve=>ingress.listen(0,'127.0.0.1',resolve));
 const url=`http://127.0.0.1:${ingress.address().port}`;
 try{
  assert.equal((await fetch(url+'/v1/operator/clinics',{method:'POST',body:'{}'})).status,404);
  assert.equal((await fetch(url+'/readyz')).status,403);
  assert.equal((await fetch(url+'/ops/health')).status,503);
  const headers={'Fly-Client-IP':'203.0.113.1','X-Licensing-Ingress-Key':'attacker','X-Licensing-Client-IP':'attacker','Content-Type':'application/json'};
  assert.equal((await fetch(url+'/v2/invitations/redeem',{method:'POST',headers,body:'{}'})).status,200);
  assert.equal(captured.host,'licensing.healthmd.app');assert.equal(captured['x-licensing-ingress-key'],'s'.repeat(43));
  assert.equal(captured['x-licensing-client-ip'],'203.0.113.1');
  assert.equal((await fetch(url+'/v2/invitations/redeem',{method:'POST',headers,body:'x'.repeat(16385)})).status,413);
 }finally{await Promise.all([new Promise(resolve=>ingress.close(resolve)),new Promise(resolve=>backend.close(resolve))]);}
});

test('operations credentials are role separated and compared without plaintext equality',async()=>{
 const secret='s'.repeat(43);
 assert.ok(await authorized(new Request('https://ops.example',{headers:{Authorization:'Bearer '+secret}}),secret));
 assert.equal(await authorized(new Request('https://ops.example',{headers:{Authorization:'Bearer '+'n'.repeat(43)}}),secret),false);
 assert.equal(await authorized(new Request('https://ops.example'),undefined),false);
});

test('monitor detects failed service/stale backup, deduplicates, reminds and reports recovery',async()=>{
 let state,latest={uploadedAt:1_000_000,key:'archives/fictional.hmlb'},objectExists=true;
 const messages=[];
 const env={SERVICE_HEALTH_URL:'https://service.clinic.example/ops/health',ALERT_FROM:'ops@clinic.example',ALERT_TO:'operator@clinic.example',
  STATE:{get:async()=>state?JSON.parse(state):null,put:async(_key,value)=>{state=value;}},
  BACKUPS:{get:async()=>latest?{json:async()=>latest}:null,head:async()=>objectExists?{}:null},
  EMAIL:{send:async message=>{messages.push(message);}}};
 let now=1_000_000;
 const failed=async()=>new Response('',{status:503}),ok=async(_url,options)=>{assert.equal(options.redirect,'manual');return new Response('',{status:200});};
 assert.deepEqual(await checkHealth(env,now,ok),{ok:true});
 await checkHealth(env,now,failed);assert.equal(messages.length,0);
 await checkHealth(env,now,failed);assert.equal(messages.length,1);
 await checkHealth(env,now,failed);assert.equal(messages.length,1);
 now+=21600001;latest.uploadedAt=now;
 await checkHealth(env,now,failed);assert.equal(messages.length,2);
 await checkHealth(env,now,ok);assert.equal(messages.length,3);assert.match(messages.at(-1).subject,/Recovered/);
 objectExists=false;
 await checkHealth(env,now,ok);await checkHealth(env,now,ok);assert.match(messages.at(-1).text,/backup_stale/);
 latest={uploadedAt:now+1,key:'archives/fictional.hmlb'};objectExists=true;
 assert.deepEqual(await checkHealth(env,now,ok),{ok:false});
});
