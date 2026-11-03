import { readFileSync } from 'node:fs';
import { encryptedBackup, restoreBackup } from './backup.mjs';

// Tokens and request bodies are file/stdin inputs, never command-line values or HTTP query strings.
const actions={provision:'/v1/operator/clinics',activate:'/v1/operator/activate',suspend:'/v1/operator/suspend',
  'rotate-admin':'/v1/operator/rotate-admin',erase:'/v1/operator/erase',invite:'/v1/admin/invitations',
  revoke:'/v1/admin/revoke',memberships:'/v1/admin/memberships'};
try {
  const [action,...args]=process.argv.slice(2);
  if(action==='backup'||action==='restore') {
    if(args.length!==2||!process.env.LICENSING_BACKUP_KEY_FILE)throw new Error();
    await (action==='backup'?encryptedBackup:restoreBackup)(args[0],args[1],process.env.LICENSING_BACKUP_KEY_FILE);
    process.stdout.write('{"ok":true}\n');
  } else {
    if(!actions[action]||args.length)throw new Error();
    const base=new URL(process.env.LICENSING_CONTROL_URL||'http://127.0.0.1:8793/');
    if(base.protocol!=='http:'||!['127.0.0.1','[::1]','localhost'].includes(base.hostname)||base.pathname!=='/'||base.username||base.password||base.search||base.hash)throw new Error();
    const raw=readFileSync(process.env.LICENSING_CONTROL_TOKEN_FILE,'utf8').trim();
    const token=raw.startsWith('[')?JSON.parse(raw)[0]:raw.startsWith('{')?JSON.parse(raw).adminToken:raw;
    if(!/^[A-Za-z0-9_-]{32,128}$/.test(token))throw new Error();
    const chunks=[];let size=0;
    for await(const chunk of process.stdin){size+=chunk.length;if(size>16384)throw new Error();chunks.push(chunk);}
    const body=JSON.parse(Buffer.concat(chunks).toString('utf8'));
    const response=await fetch(new URL(actions[action],base),{method:'POST',redirect:'error',signal:AbortSignal.timeout(15000),
      headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`},body:JSON.stringify(body)});
    if(!response.ok)throw new Error();
    const data=await response.text();if(data.length>65536)throw new Error();
    process.stdout.write(data+'\n'); // May contain a freshly issued secret: redirect to a mode-0600 file.
  }
} catch {process.stderr.write('{"error":"licensing_operation_failed"}\n');process.exitCode=1;}
