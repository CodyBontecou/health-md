import {chmodSync,chownSync,mkdirSync,existsSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
// Fly volume is initially root-owned. Initialize it before dropping all root identity.
try {
  if(process.getuid()!==0)throw new Error();
  mkdirSync('/data',{recursive:true,mode:0o700});chownSync('/data',1000,1000);chmodSync('/data',0o700);
  for(const name of ['licensing.sqlite','licensing.sqlite-wal','licensing.sqlite-shm']){
    const path='/data/'+name;if(existsSync(path)){chownSync(path,1000,1000);chmodSync(path,0o600);}
  }
  execFileSync('/bin/mount',['-t','tmpfs','-o','size=192m,mode=1777,nosuid,nodev','tmpfs','/tmp'],{stdio:'ignore'});
  process.setgroups([]);process.setgid(1000);process.setuid(1000);
  await import('./fly-server.mjs');
}catch{process.stderr.write('{"event":"licensing_bootstrap_failed"}\n');process.exit(1);}
