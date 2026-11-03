// Synthetic signatures only. Generates an ephemeral test key and never writes its private part.
import { generateKeyPairSync, sign } from 'node:crypto';
import { writeFileSync } from 'node:fs';

const { publicKey, privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const root = {
  issuer: 'https://licensing.healthmd.example', audience: 'healthmd-clinic-access',
  installationID: 'fictional-installation', sponsorshipID: 'fictional-sponsorship',
  clinicID: 'fictional-clinic', destinationID: 'primary', policyVersion: 1,
  endpoint: 'https://intake.clinic.example/upload', issuedAtMilliseconds: 900000,
  expiresAtMilliseconds: 1500000,
};
function token(claims, keyID = 'test-key', version = 'v1') {
  const content = `${version}.${keyID}.${Buffer.from(JSON.stringify(claims)).toString('base64url')}`;
  return `${content}.${sign('sha256', Buffer.from(content), {key: privateKey, dsaEncoding:'ieee-p1363'}).toString('base64url')}`;
}
const valid = token(root);
const cases = [{id:'valid',token:valid,expected:true}];
for (const [id, changes] of Object.entries({
  'wrong-issuer':{issuer:'https://other.example'},'wrong-audience':{audience:'other'},
  'wrong-installation':{installationID:'other'},'expired':{expiresAtMilliseconds:1000000},
  'not-yet-issued':{issuedAtMilliseconds:1000001},'overlong':{expiresAtMilliseconds:605700001},
  'invalid-endpoint':{endpoint:'http://intake.clinic.example/upload'},
  'missing-sponsorship':{sponsorshipID:''},'unknown-field':{unexpected:true},
  'empty-clinic':{clinicID:''},'invalid-policy':{policyVersion:0},
})) cases.push({id, token:token({...root,...changes}),expected:false});
cases.push({id:'unknown-key',token:token(root,'unknown'),expected:false});
cases.push({id:'unknown-version',token:token(root,'test-key','v2'),expected:false});
cases.push({id:'tampered-payload',token:valid.replace(valid.split('.')[2],Buffer.from(JSON.stringify({...root,endpoint:'https://other.example/upload'})).toString('base64url')),expected:false});
cases.push({id:'padded-signature',token:valid+'=',expected:false});
cases.push({id:'oversized',token:'x'.repeat(8193),expected:false});
cases.push({id:'missing-signature',token:valid.split('.').slice(0,3).join('.'),expected:false});
writeFileSync(new URL('./verification-fixtures.json',import.meta.url),JSON.stringify({
  schema:'healthmd.clinic_grant_verification.fixtures',version:1,
  issuer:root.issuer,audience:root.audience,installation_id:root.installationID,now_ms:1000000,
  key_id:'test-key',public_key_der:publicKey.export({type:'spki',format:'der'}).toString('base64'),cases,
},null,2)+'\n');
