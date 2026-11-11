import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { LicensingService } from '../src/service.mjs';
import { createHandler } from '../src/http.mjs';

test('fixed-path pilot HTTP journey authenticates roles and never accepts health fields',async()=>{
  const {privateKey}=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
  const service=new LicensingService({databasePath:':memory:',privateKey:privateKey.export({type:'pkcs8',format:'pem'}),
    keyID:'test',issuer:'https://licensing.healthmd.example',now:()=>1000000});
  const operatorToken='o'.repeat(43), handle=createHandler(service,{operatorToken});
  const post=(path,body,token)=>handle(new Request(`https://licensing.healthmd.example${path}`,{method:'POST',
    headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},body:JSON.stringify(body)}));
  try {
    const clinicBody={name:'Fictional clinic',endpoint:'https://clinic.example/upload',paidThroughMilliseconds:2000000};
    assert.equal((await post('/v1/operator/clinics',clinicBody)).status,401);
    const provision=await post('/v1/operator/clinics',clinicBody,operatorToken);
    assert.equal(provision.status,201);assert.equal(provision.headers.get('cache-control'),'no-store');
    const clinic=await provision.json();
    assert.equal((await post('/v1/admin/invitations',{},operatorToken)).status,401);
    const invite=await (await post('/v1/admin/invitations',{},clinic.adminToken)).json();
    const redemption={invitationCode:invite.invitationCode,installationID:'fictional-installation',enrollmentSecret:'s'.repeat(43)};
    assert.equal((await post('/v2/invitations/redeem',{...redemption,health:{steps:1}})).status,400);
    const result=await (await post('/v2/invitations/redeem',redemption)).json();
    assert.ok(result.grant);
    assert.equal((await post('/v2/invitations/redeem',redemption)).status,200);
    const refresh={refreshToken:'s'.repeat(43),installationID:'fictional-installation'};
    assert.equal((await post('/v1/sponsorship/refresh',refresh)).status,200);
    assert.equal((await post('/v1/sponsorship/disconnect',refresh)).status,200);
    assert.equal((await post('/v1/sponsorship/refresh',refresh)).status,403);
    assert.equal((await post('/v1/sponsorship/refresh?patient=abc',refresh)).status,404);
    const tooLarge=await handle(new Request('https://licensing.healthmd.example/v2/invitations/redeem',{
      method:'POST',headers:{'Content-Type':'application/json'},body:' '.repeat(16385)}));
    assert.equal(tooLarge.status,413);
  } finally {service.close();}
});
