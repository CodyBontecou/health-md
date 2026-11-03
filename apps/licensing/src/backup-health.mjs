import {readdirSync} from 'node:fs';
try {
  const recent=readdirSync(process.env.LICENSING_BACKUP_DIR).some(name=>{
    const match=/^licensing-backup-([0-9]{13})\.hmlb$/.exec(name);
    return match&&Date.now()-Number(match[1])>=0&&Date.now()-Number(match[1])<7200000;
  });
  process.exitCode=recent?0:1;
} catch {process.exitCode=1;}
