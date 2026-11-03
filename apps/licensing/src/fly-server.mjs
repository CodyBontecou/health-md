import {mkdtempSync,writeFileSync,readFileSync,chmodSync,rmSync,statfsSync,openAsBlob} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {LicensingService} from './service.mjs';
import {readConfiguration} from './server.mjs';
import {createRuntime} from './runtime.mjs';
import {createFlyIngress} from './fly-ingress.mjs';
import {encryptedBackup} from './backup.mjs';

process.umask(0o077);
try {
  const directory=mkdtempSync(join(tmpdir(),'licensing-secrets-'));
  for(const [variable,file,target] of [
    ['LICENSING_SIGNING_KEY_B64','signing.pem','LICENSING_PRIVATE_KEY_FILE'],
    ['LICENSING_OPERATOR_TOKENS_B64','operator-tokens.json','LICENSING_OPERATOR_TOKENS_FILE'],
    ['LICENSING_INGRESS_KEY_B64','ingress-key','LICENSING_INGRESS_KEY_FILE'],
    ['LICENSING_BACKUP_KEY_B64','backup-key','LICENSING_BACKUP_KEY_FILE'],
    ['LICENSING_UPLOAD_TOKEN_B64','upload-token','LICENSING_UPLOAD_TOKEN_FILE'],
  ]) {
    if(!process.env[variable])throw new Error();
    const path=join(directory,file);writeFileSync(path,Buffer.from(process.env[variable],'base64'),{flag:'wx',mode:0o600});
    process.env[target]=path;delete process.env[variable];
  }
  const configuration=readConfiguration();
  if(configuration.host!=='127.0.0.1')throw new Error();
  const service=new LicensingService(configuration);chmodSync(configuration.databasePath,0o600);
  if(service.db.prepare('PRAGMA quick_check').get().quick_check!=='ok'||service.db.prepare('PRAGMA foreign_key_check').all().length)throw new Error();
  service.maintain();
  let maintenanceFailed=false,lastBackup=0,backupRunning;
  const runtime=createRuntime(service,{...configuration,onSummary:event=>{
    maintenanceFailed=event.maintenanceFailed;process.stdout.write(JSON.stringify(event)+'\n');
  }});
  await runtime.start();
  const ingress=createFlyIngress({...configuration,backendPort:configuration.publicPort,operationalHealth:()=>{
    const disk=statfsSync('/data');service.db.prepare('SELECT 1').get();
    return !maintenanceFailed&&Date.now()-lastBackup<7200000&&disk.bavail*disk.bsize>134217728;
  }});
  await new Promise((resolve,reject)=>{ingress.once('error',reject);ingress.listen(8080,'0.0.0.0',resolve);});
  const uploadURL=new URL(process.env.LICENSING_BACKUP_UPLOAD_URL);
  if(uploadURL.protocol!=='https:'||uploadURL.pathname!=='/v1/backup'||uploadURL.search||uploadURL.hash||uploadURL.username||uploadURL.password)throw new Error();
  const runBackup=()=>{
    if(backupRunning)return backupRunning;
    backupRunning=(async()=>{
      let temporary;
      try {
        temporary=mkdtempSync(join(tmpdir(),'licensing-offsite-'));const archive=join(temporary,'snapshot.hmlb');
        await encryptedBackup(configuration.databasePath,archive,process.env.LICENSING_BACKUP_KEY_FILE);
        const blob=await openAsBlob(archive);
        if(blob.size>67108864)throw new Error();
        const reply=await fetch(uploadURL,{method:'PUT',redirect:'error',signal:AbortSignal.timeout(120000),
          headers:{'Content-Type':'application/octet-stream',Authorization:`Bearer ${readFileSync(process.env.LICENSING_UPLOAD_TOKEN_FILE,'utf8')}`},body:blob});
        await reply.body?.cancel();if(!reply.ok)throw new Error();
        lastBackup=Date.now();process.stdout.write('{"event":"licensing_offsite_backup_complete"}\n');
      }catch{process.stderr.write('{"event":"licensing_offsite_backup_failed"}\n');}
      finally{if(temporary)rmSync(temporary,{recursive:true,force:true});backupRunning=undefined;}
    })();return backupRunning;
  };
  void runBackup();const backupTimer=setInterval(runBackup,3600000);
  let closing=false;
  for(const signal of ['SIGINT','SIGTERM'])process.on(signal,async()=>{
    if(closing)return;closing=true;clearInterval(backupTimer);
    const done=new Promise(resolve=>ingress.close(resolve));ingress.closeIdleConnections();
    await Promise.all([done,runtime.close(),backupRunning]);service.close();rmSync(directory,{recursive:true,force:true});
  });
}catch{process.stderr.write('{"event":"licensing_startup_failed"}\n');process.exit(1);}
