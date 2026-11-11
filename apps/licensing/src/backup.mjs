import { backup, DatabaseSync } from 'node:sqlite';
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { createReadStream, createWriteStream, readFileSync, writeFileSync, appendFileSync,
  mkdtempSync, rmSync, existsSync, openSync, readSync, closeSync, statSync, linkSync, fsyncSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { tmpdir } from 'node:os';
import { pipeline } from 'node:stream/promises';

const magic=Buffer.from('HMLB1');
function keyFrom(path) {
  const value=readFileSync(path,'utf8').trim();
  if(!/^[a-f0-9]{64}$/.test(value))throw new Error('Invalid backup key');
  return Buffer.from(value,'hex');
}
function verifyDatabase(path) {
  const db=new DatabaseSync(path,{readOnly:true});
  try {
    if(db.prepare('PRAGMA quick_check').get().quick_check!=='ok'||db.prepare('PRAGMA foreign_key_check').all().length||
      db.prepare('PRAGMA user_version').get().user_version!==1)throw new Error('Backup integrity check failed');
  } finally {db.close();}
}

export async function encryptedBackup(databasePath,output,keyFile) {
  if(existsSync(output))throw new Error('Backup output already exists');
  const directory=mkdtempSync(join(tmpdir(),'healthmd-licensing-backup-'));
  const plain=join(directory,'snapshot.sqlite'),temporary=join(dirname(output),`.licensing-backup-${randomBytes(12).toString('hex')}`);
  let db;
  try {
    db=new DatabaseSync(databasePath,{readOnly:true});
    await backup(db,plain);verifyDatabase(plain);
    const nonce=randomBytes(12),header=Buffer.concat([magic,nonce]);
    const cipher=createCipheriv('aes-256-gcm',keyFrom(keyFile),nonce);cipher.setAAD(header);
    writeFileSync(temporary,header,{flag:'wx',mode:0o600});
    await pipeline(createReadStream(plain),cipher,createWriteStream(temporary,{flags:'a',mode:0o600}));
    appendFileSync(temporary,cipher.getAuthTag());
    const fd=openSync(temporary,'r');try{fsyncSync(fd);}finally{closeSync(fd);}
    // Exclusive publication: never replace another backup, including on concurrent invocations.
    linkSync(temporary,output);
    const parent=openSync(dirname(output),'r');try{fsyncSync(parent);}finally{closeSync(parent);}
  } finally {db?.close();rmSync(directory,{recursive:true,force:true});rmSync(temporary,{force:true});}
}

export async function restoreBackup(input,destination,keyFile) {
  if([destination,destination+'-wal',destination+'-shm'].some(existsSync))throw new Error('Restore requires a new database path');
  const directory=mkdtempSync(join(dirname(destination),'.licensing-restore-')),plain=join(directory,'restored.sqlite');
  try {
    const size=statSync(input).size;
    if(size<34)throw new Error('Invalid backup');
    const fd=openSync(input,'r'),header=Buffer.alloc(17),tag=Buffer.alloc(16);
    try{readSync(fd,header,0,17,0);readSync(fd,tag,0,16,size-16);}finally{closeSync(fd);}
    if(!header.subarray(0,5).equals(magic))throw new Error('Invalid backup version');
    const decipher=createDecipheriv('aes-256-gcm',keyFrom(keyFile),header.subarray(5));
    decipher.setAAD(header);decipher.setAuthTag(tag);
    await pipeline(createReadStream(input,{start:17,end:size-17}),decipher,createWriteStream(plain,{flags:'wx',mode:0o600}));
    verifyDatabase(plain);
    // A stale snapshot must not resurrect revoked refresh tokens or rotated admin credentials.
    // Disaster restore deliberately requires fresh invitations and operator-issued admin tokens.
    const restored = new DatabaseSync(plain);
    try {
      restored.exec('BEGIN IMMEDIATE');
      restored.prepare('UPDATE sponsorships SET revoked=1,revoked_at=?,enrollment_invitation_hash=NULL,recovery_until=NULL').run(Date.now());
      restored.exec('DELETE FROM invitations');
      for(const clinic of restored.prepare('SELECT id FROM clinics').all()) {
        restored.prepare('UPDATE clinics SET admin_hash=? WHERE id=?').run(randomBytes(32).toString('hex'),clinic.id);
      }
      restored.exec('COMMIT; PRAGMA wal_checkpoint(TRUNCATE);');
    } finally { restored.close(); }
    const fdOut=openSync(plain,'r');try{fsyncSync(fdOut);}finally{closeSync(fdOut);}
    linkSync(plain,destination);
    const parent=openSync(dirname(destination),'r');try{fsyncSync(parent);}finally{closeSync(parent);}
  } finally {rmSync(directory,{recursive:true,force:true});}
}
