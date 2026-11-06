import {test} from 'node:test';
import {request as nodeRequest} from 'node:http';

function httpFetch(url,options={}) {
  return new Promise((resolve,reject)=>{
    const req=nodeRequest(url,{method:options.method||'GET',headers:options.headers},res=>{
      const chunks=[];res.on('data',chunk=>chunks.push(chunk));res.on('end',()=>resolve(new Response(Buffer.concat(chunks),{status:res.statusCode,headers:res.headers})));
    });
    req.on('error',reject);req.end(options.body);
  });
}
import assert from 'node:assert/strict';
import {generateKeyPairSync,randomBytes} from 'node:crypto';
import {mkdtempSync,rmSync,writeFileSync,readFileSync,existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {LicensingService} from '../src/service.mjs';
import {createHandler} from '../src/http.mjs';
import {createRuntime} from '../src/runtime.mjs';
import {DatabaseSync} from 'node:sqlite';
import {readConfiguration} from '../src/server.mjs';
import {RequestLimiter} from '../src/security.mjs';
import {encryptedBackup,restoreBackup} from '../src/backup.mjs';

function setup(databasePath=':memory:') {
  const privateKey=generateKeyPairSync('ec',{namedCurve:'prime256v1'}).privateKey.export({type:'pkcs8',format:'pem'});
  let now=1000000;
  const options={databasePath,privateKey,keyID:'test',issuer:'https://license.clinic.example/',now:()=>now};
  const service=new LicensingService(options);
  const clinic=service.provisionClinic({name:'Synthetic clinic',endpoint:'https://intake.clinic.example/upload',paidThroughMilliseconds:now+3*86400000});
  const {invitationCode}=service.createInvitation(clinic.adminToken);
  const request={invitationCode,installationID:'fictional-installation',enrollmentSecret:'p'.repeat(43)};
  return {service,clinic,request,options,setTime:value=>{now=value;}};
}

test('lost response recovery is installation AND secret bound, bounded, and cannot resurrect revocation',()=>{
  const {service,clinic,request,setTime}=setup();
  try {
    const first=service.redeem(request);
    assert.equal(first.refreshToken,undefined);
    assert.equal(service.redeem(request).sponsorshipID,first.sponsorshipID);
    assert.equal(service.db.prepare('SELECT count(*) AS n FROM sponsorships').get().n,1);
    for(const changed of [{installationID:'another-installation'},{enrollmentSecret:'x'.repeat(43)}]) {
      assert.throws(()=>service.redeem({...request,...changed}),/invitation_unavailable/);
    }
    service.db.prepare('UPDATE invitations SET expires_at=0').run();
    assert.equal(service.redeem(request).sponsorshipID,first.sponsorshipID); // Already redeemed; proof-bound recovery window.
    setTime(1000000+86400000);
    assert.throws(()=>service.redeem(request),/invitation_unavailable/);
    setTime(1000000);
    service.revoke(clinic.adminToken,first.sponsorshipID);
    assert.throws(()=>service.redeem(request),/invitation_unavailable/);
    const stored=JSON.stringify(service.db.prepare('SELECT * FROM sponsorships').all());
    assert.equal(stored.includes(request.enrollmentSecret),false);
  } finally {service.close();}
});

test('control plane is absent on public handler and operator/admin rotation preserves tenant authority',async()=>{
  const {service,clinic}=setup();
  const operator='o'.repeat(43),previous='z'.repeat(43);
  const pub=createHandler(service,{operatorTokens:[operator,previous],surface:'public'});
  const control=createHandler(service,{operatorTokens:[operator,previous],surface:'control'});
  const post=(handler,path,body,token)=>handler(new Request('https://license.clinic.example'+path,{method:'POST',
    headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`},body:JSON.stringify(body)}));
  try {
    assert.equal((await post(pub,'/v1/operator/activate',{clinicID:clinic.clinicID,paidThroughMilliseconds:9e9},operator)).status,404);
    assert.equal((await post(control,'/v2/invitations/redeem',{},operator)).status,404);
    assert.equal((await post(control,'/v1/operator/activate',{clinicID:clinic.clinicID,paidThroughMilliseconds:9e9},previous)).status,200);
    const rotated=await (await post(control,'/v1/operator/rotate-admin',{clinicID:clinic.clinicID},operator)).json();
    assert.throws(()=>service.createInvitation(clinic.adminToken),/unauthorized/);
    assert.ok(service.createInvitation(rotated.adminToken).invitationCode);
    assert.equal((await post(control,'/v1/operator/suspend',{clinicID:clinic.clinicID},operator)).status,200);
    assert.throws(()=>service.createInvitation(rotated.adminToken),/unauthorized/);
    assert.equal((await post(control,'/v1/operator/erase',{clinicID:clinic.clinicID},operator)).status,200);
    assert.equal(service.db.prepare('SELECT count(*) AS n FROM clinics').get().n,0);
  } finally{service.close();}
});

test('rate limiter has independent client limits, bounded storage and minute expiry',()=>{
  let now=0;
  const limiter=new RequestLimiter({now:()=>now,globalLimit:5,clientLimit:2,maximumClients:2});
  assert.ok(limiter.allow('first'));assert.ok(limiter.allow('first'));assert.equal(limiter.allow('first'),false);
  assert.ok(limiter.allow('second'));assert.equal(limiter.allow('third'),false);
  assert.equal(limiter.allow('second'),false);
  now=60000;assert.ok(limiter.allow('third'));assert.equal(limiter.clients.size,1);
  assert.equal(JSON.stringify([...limiter.clients.keys()]).includes('third'),false);
});

test('production HTTP boundary requires trusted ingress, rejects header spoofing and hides admin routes',async()=>{
  const {service,request}=setup();
  const summaries=[];
  const ingress='i'.repeat(43);
  const runtime=createRuntime(service,{operatorTokens:['o'.repeat(43)],production:true,ingressKey:ingress,
    issuer:'https://license.clinic.example/',publicPort:0,controlPort:0,onSummary:x=>summaries.push(x)});
  try {
    await runtime.start();
    const base=`http://127.0.0.1:${runtime.publicServer.address().port}`;
    const headers={'Content-Type':'application/json',Host:'license.clinic.example','X-Licensing-Ingress-Key':ingress,'X-Licensing-Client-IP':'synthetic-address'};
    assert.equal((await httpFetch(base+'/readyz')).status,403);
    assert.equal((await httpFetch(base+'/readyz',{headers})).status,200);
    assert.equal((await httpFetch(base+'/v1/operator/clinics',{method:'POST',headers,body:'{}'})).status,404);
    const response=await httpFetch(base+'/v2/invitations/redeem',{method:'POST',headers,body:JSON.stringify(request)});
    assert.equal(response.status,200);
    const control=`http://127.0.0.1:${runtime.controlServer.address().port}`;
    assert.equal((await httpFetch(control+'/v1/admin/memberships',{method:'POST',headers:{'Content-Type':'application/json'},body:'{"after":""}'})).status,401);
  } finally{await runtime.close();service.close();}
  const summary=JSON.stringify(summaries);
  for(const secret of [ingress,request.enrollmentSecret,request.invitationCode,'synthetic-address','license.clinic.example'])assert.equal(summary.includes(secret),false);
});

test('encrypted backup restores a WAL snapshot, recovery and revocation; tampering never publishes plaintext',async()=>{
  const dir=mkdtempSync(join(tmpdir(),'licensing-production-'));
  const {service,clinic,request,options}=setup(join(dir,'source.sqlite'));
  const key=join(dir,'backup.key'),archive=join(dir,'snapshot.hmlb'),restored=join(dir,'restored.sqlite');
  writeFileSync(key,randomBytes(32).toString('hex'),{mode:0o600});
  let reopened;
  try {
    const first=service.redeem(request);
    await encryptedBackup(options.databasePath,archive,key);
    assert.equal(readFileSync(archive).includes(Buffer.from('SQLite format')),false);
    await restoreBackup(archive,restored,key);
    reopened=new LicensingService({...options,databasePath:restored});
    assert.throws(()=>reopened.redeem(request),/invitation_unavailable/);
    assert.throws(()=>reopened.refresh({refreshToken:request.enrollmentSecret,installationID:request.installationID}),/sponsorship_inactive/);
    assert.throws(()=>reopened.createInvitation(clinic.adminToken),/unauthorized/);
    const freshAdmin=reopened.rotateAdmin(clinic.clinicID).adminToken;
    const freshInvite=reopened.createInvitation(freshAdmin).invitationCode;
    assert.notEqual(reopened.redeem({...request,invitationCode:freshInvite,enrollmentSecret:'n'.repeat(43)}).sponsorshipID,first.sponsorshipID);
    await assert.rejects(restoreBackup(archive,restored,key),/new database path/);
    const altered=readFileSync(archive);altered[20]^=1;writeFileSync(join(dir,'bad.hmlb'),altered);
    const badDestination=join(dir,'bad.sqlite');
    await assert.rejects(restoreBackup(join(dir,'bad.hmlb'),badDestination,key));
    assert.equal(existsSync(badDestination),false);
  } finally{reopened?.close();service.close();rmSync(dir,{recursive:true,force:true});}
});

test('retention removes expired recovery material and revoked memberships without reviving access',()=>{
  const {service,clinic,request,setTime}=setup();
  try {
    const first=service.redeem(request);
    service.revoke(clinic.adminToken,first.sponsorshipID);
    setTime(1000000+31*86400000);service.maintain();
    assert.equal(service.db.prepare('SELECT count(*) AS n FROM invitations').get().n,0);
    assert.equal(service.db.prepare('SELECT count(*) AS n FROM sponsorships').get().n,0);
    assert.throws(()=>service.refresh({refreshToken:request.enrollmentSecret,installationID:request.installationID}),/unauthorized/);
  } finally{service.close();}
});


test('legacy database migration preserves existing grants and refuses future formats',()=>{
  const dir=mkdtempSync(join(tmpdir(),'licensing-migration-'));
  const path=join(dir,'legacy.sqlite');
  const {service,options,clinic,request}=setup(path);
  const first=service.redeem(request);service.close();
  const db=new DatabaseSync(path);
  db.exec(`DROP INDEX sponsorship_invitation; DROP TABLE audit;
    ALTER TABLE sponsorships DROP COLUMN enrollment_invitation_hash;
    ALTER TABLE sponsorships DROP COLUMN recovery_until;
    ALTER TABLE sponsorships DROP COLUMN revoked_at; PRAGMA user_version=0;`);db.close();
  let migrated;
  try {
    migrated=new LicensingService(options);
    assert.equal(migrated.refresh({refreshToken:request.enrollmentSecret,installationID:request.installationID}).sponsorshipID,first.sponsorshipID);
    assert.ok(migrated.createInvitation(clinic.adminToken).invitationCode);
    assert.equal(migrated.db.prepare('PRAGMA user_version').get().user_version,1);
    migrated.db.exec('PRAGMA user_version=99');migrated.close();migrated=null;
    assert.throws(()=>new LicensingService(options),/unsupported_database_version/);
    const future=new DatabaseSync(path);assert.equal(future.prepare('PRAGMA user_version').get().user_version,99);future.close();
  } finally {migrated?.close();rmSync(dir,{recursive:true,force:true});}
});

test('production configuration requires isolated file credentials, root HTTPS identity and separate ports',()=>{
  const dir=mkdtempSync(join(tmpdir(),'licensing-configuration-'));
  try {
    const privatePath=join(dir,'key.pem'),tokensPath=join(dir,'tokens.json'),ingressPath=join(dir,'ingress');
    writeFileSync(privatePath,'fixture-only');writeFileSync(tokensPath,JSON.stringify(['o'.repeat(43)]));writeFileSync(ingressPath,'i'.repeat(43));
    const env={LICENSING_MODE:'production',LICENSING_DATABASE:join(dir,'db.sqlite'),LICENSING_ISSUER:'https://license.clinic.example/',
      LICENSING_PRIVATE_KEY_FILE:privatePath,LICENSING_OPERATOR_TOKENS_FILE:tokensPath,LICENSING_INGRESS_KEY_FILE:ingressPath,LICENSING_KEY_ID:'test'};
    assert.equal(readConfiguration(env).production,true);
    for(const patch of [{LICENSING_MODE:''},{LICENSING_DATABASE:'relative.sqlite'},{LICENSING_ISSUER:'http://license.clinic.example/'},
      {LICENSING_ISSUER:'https://license.clinic.example/nested/'},{LICENSING_KEY_ID:''},{LICENSING_INGRESS_KEY_FILE:''},
      {LICENSING_OPERATOR_TOKENS_FILE:'',LICENSING_OPERATOR_TOKEN:'o'.repeat(43)},{LICENSING_CONTROL_PORT:'8792'},{LICENSING_HOST:'::'}]) {
      assert.throws(()=>readConfiguration({...env,...patch}));
    }
  } finally {rmSync(dir,{recursive:true,force:true});}
});
