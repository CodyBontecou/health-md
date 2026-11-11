import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, createPublicKey, verify } from 'node:crypto';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { LicensingService, canonicalEndpoint } from '../src/service.mjs';

function setup() {
  const keys = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const privateKey = keys.privateKey.export({ type:'pkcs8', format:'pem' });
  const service = new LicensingService({databasePath:':memory:',privateKey,keyID:'test',issuer:'https://licensing.healthmd.example',now:()=>1000000});
  const clinic = service.provisionClinic({name:'Fictional clinic',endpoint:'https://intake.clinic.example/upload',paidThroughMilliseconds:2000000});
  return {service,clinic,privateKey};
}

test('endpoint grammar matches both native consumers',()=>{
  const f=JSON.parse(readFileSync(new URL('../../../packages/contracts/clinic-sponsorship/v1/authorization-fixtures.json',import.meta.url)));
  for(const c of f.endpoints) assert.equal(canonicalEndpoint(c.input),c.expected,c.input);
});

test('invitation redemption is single use, signed and capped at paid-through',()=>{
  const {service,clinic,privateKey}=setup();
  try {
    const {invitationCode}=service.createInvitation(clinic.adminToken);
    const result=service.redeem({invitationCode,installationID:'fictional-installation',enrollmentSecret:'s'.repeat(43)});
    const parts=result.grant.split('.');
    assert.equal(verify('sha256',Buffer.from(parts.slice(0,3).join('.')),
      {key:createPublicKey(privateKey),dsaEncoding:'ieee-p1363'},Buffer.from(parts[3],'base64url')),true);
    const claims=JSON.parse(Buffer.from(parts[2],'base64url'));
    assert.equal(claims.issuedAtMilliseconds,940000);
    assert.equal(claims.expiresAtMilliseconds,2000000);
    assert.equal(claims.installationID,'fictional-installation');
    assert.throws(()=>service.redeem({invitationCode,installationID:'another-installation',enrollmentSecret:'s'.repeat(43)}),/invitation_unavailable/);
    assert.throws(()=>service.refresh({refreshToken:'s'.repeat(43),installationID:'another-installation'}),/unauthorized/);
    assert.ok(service.refresh({refreshToken:'s'.repeat(43),installationID:'fictional-installation',enrollmentSecret:'s'.repeat(43)}).grant);
    service.disconnect({refreshToken:'s'.repeat(43),installationID:'fictional-installation',enrollmentSecret:'s'.repeat(43)});
    assert.throws(()=>service.refresh({refreshToken:'s'.repeat(43),installationID:'fictional-installation',enrollmentSecret:'s'.repeat(43)}),/sponsorship_inactive/);
  } finally {service.close();}
});

test('backdated issuance tolerates a slow phone while expiry stays within seven signed days',()=>{
  const {service,clinic}=setup();
  try {
    service.activate(clinic.clinicID,1000000+10*86400000);
    const {invitationCode}=service.createInvitation(clinic.adminToken);
    const reply=service.redeem({invitationCode,installationID:'fictional-installation',enrollmentSecret:'k'.repeat(43)});
    const claims=JSON.parse(Buffer.from(reply.grant.split('.')[2],'base64url'));
    const slowPhoneNow=1000000-1000;
    assert.ok(claims.issuedAtMilliseconds<=slowPhoneNow);
    assert.ok(claims.expiresAtMilliseconds>slowPhoneNow);
    assert.equal(claims.expiresAtMilliseconds-claims.issuedAtMilliseconds,7*86400000);
    assert.equal(claims.expiresAtMilliseconds,1000000-60000+7*86400000);
  }finally{service.close();}
});

test('one clinic administrator cannot revoke another clinic membership',()=>{
  const {service,clinic}=setup();
  try {
    const second=service.provisionClinic({name:'Other fictional clinic',endpoint:'https://other.clinic.example/upload',paidThroughMilliseconds:2000000});
    const {invitationCode}=service.createInvitation(clinic.adminToken);
    const result=service.redeem({invitationCode,installationID:'fictional-installation',enrollmentSecret:'s'.repeat(43)});
    assert.throws(()=>service.revoke(second.adminToken,result.sponsorshipID),/not_found/);
    service.revoke(clinic.adminToken,result.sponsorshipID);
    assert.throws(()=>service.refresh({refreshToken:'s'.repeat(43),installationID:'fictional-installation',enrollmentSecret:'s'.repeat(43)}),/sponsorship_inactive/);
    assert.equal(service.db.prepare('SELECT refresh_hash FROM sponsorships').get().refresh_hash.includes('s'.repeat(43)),false);
  } finally {service.close();}
});

test('expired invitations and clinic subscriptions fail closed',()=>{
  const {service,clinic}=setup();
  try {
    const {invitationCode}=service.createInvitation(clinic.adminToken);
    service.now=()=>2000000;
    assert.throws(()=>service.redeem({invitationCode,installationID:'fictional-installation',enrollmentSecret:'s'.repeat(43)}),/invitation_unavailable/);
    assert.throws(()=>service.createInvitation(clinic.adminToken),/sponsorship_inactive/);
    service.activate(clinic.clinicID,3000000);
    assert.ok(service.createInvitation(clinic.adminToken));
  } finally {service.close();}
});

test('redemption and revocation survive restart without resurrecting access',()=>{
  const directory=mkdtempSync(join(tmpdir(),'healthmd-licensing-'));
  const {privateKey}=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
  const options={databasePath:join(directory,'pilot.sqlite'),privateKey:privateKey.export({type:'pkcs8',format:'pem'}),
    keyID:'test',issuer:'https://licensing.healthmd.example',now:()=>1000000};
  let service=new LicensingService(options);
  try {
    const clinic=service.provisionClinic({name:'Fictional clinic',endpoint:'https://clinic.example/upload',paidThroughMilliseconds:2000000});
    const {invitationCode}=service.createInvitation(clinic.adminToken);
    const result=service.redeem({invitationCode,installationID:'fictional-installation',enrollmentSecret:'s'.repeat(43)});
    service.close();service=new LicensingService(options);
    assert.equal(service.redeem({invitationCode,installationID:'fictional-installation',enrollmentSecret:'s'.repeat(43)}).sponsorshipID,result.sponsorshipID);
    const refresh={refreshToken:'s'.repeat(43),installationID:'fictional-installation',enrollmentSecret:'s'.repeat(43)};
    assert.ok(service.refresh(refresh).grant);
    service.revoke(clinic.adminToken,result.sponsorshipID);
    service.close();service=new LicensingService(options);
    assert.throws(()=>service.refresh(refresh),/sponsorship_inactive/);
  } finally {service.close();rmSync(directory,{recursive:true,force:true});}
});
