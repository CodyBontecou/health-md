import {readdirSync,statSync,unlinkSync} from 'node:fs';
import {join} from 'node:path';
import {encryptedBackup} from './backup.mjs';
const env=process.env;
if(!env.LICENSING_DATABASE||!env.LICENSING_BACKUP_DIR||!env.LICENSING_BACKUP_KEY_FILE)throw new Error('Backup configuration required');
let stopping=false, running=false;
async function run(){
  if(running)return;running=true;
  try {
    const now=Date.now(),name=`licensing-backup-${now}.hmlb`;
    await encryptedBackup(env.LICENSING_DATABASE,join(env.LICENSING_BACKUP_DIR,name),env.LICENSING_BACKUP_KEY_FILE);
    for(const file of readdirSync(env.LICENSING_BACKUP_DIR)) {
      const match=/^licensing-backup-([0-9]{13})\.hmlb$/.exec(file);
      if(match&&Number(match[1])<now-7*86400000&&statSync(join(env.LICENSING_BACKUP_DIR,file)).isFile())unlinkSync(join(env.LICENSING_BACKUP_DIR,file));
    }
    process.stdout.write('{"event":"licensing_backup_complete"}\n');
  } catch {process.stderr.write('{"event":"licensing_backup_failed"}\n');}
  finally {running=false;}
}
await run();
const interval=setInterval(()=>{if(!stopping)void run();},3600000);
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>{stopping=true;clearInterval(interval);});
