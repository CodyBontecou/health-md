import {generateKeyPairSync,randomBytes} from 'node:crypto';
import {mkdirSync,writeFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
try {
  if(process.argv.length!==3)throw new Error();
  process.umask(0o077);
  const keyID=process.env.LICENSING_KEY_ID||`clinic-${randomBytes(8).toString('hex')}`;
  if(!/^[A-Za-z0-9_-]{1,64}$/.test(keyID))throw new Error();
  const directory=resolve(process.argv[2]);mkdirSync(directory,{mode:0o700}); // Refuse an existing directory.
  const keys=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
  const put=(name,value)=>writeFileSync(join(directory,name),value,{flag:'wx',mode:0o600});
  put('signing.pem',keys.privateKey.export({type:'pkcs8',format:'pem'}));
  put('operator-tokens.json',JSON.stringify([randomBytes(32).toString('base64url')]));
  put('ingress-key',randomBytes(32).toString('base64url'));
  put('backup-key',randomBytes(32).toString('hex'));
  put('public-key.json',JSON.stringify({keyID,publicKeyDER:keys.publicKey.export({type:'spki',format:'der'}).toString('base64')})+'\n');
  put('trusted-keys.json',JSON.stringify({[keyID]:keys.publicKey.export({type:'spki',format:'der'}).toString('base64')}));
  process.stdout.write('{"ok":true}\n');
} catch {process.stderr.write('{"error":"secret_initialization_failed"}\n');process.exitCode=1;}
