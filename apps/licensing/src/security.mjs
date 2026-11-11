import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';

export function equalSecret(left, right) {
  if (typeof left !== 'string' || typeof right !== 'string') return false;
  const digest=value=>createHash('sha256').update(value).digest();
  return timingSafeEqual(digest(left),digest(right));
}

/** Bounded, process-local abuse counters. No address, token, or body is persisted/logged. */
export class RequestLimiter {
  constructor({ now=Date.now, globalLimit=600, clientLimit=60, maximumClients=4096 }={}) {
    Object.assign(this,{now,globalLimit,clientLimit,maximumClients});
    this.key=randomBytes(32);this.clients=new Map();this.minute=-1;this.total=0;
  }
  allow(identity) {
    const minute=Math.floor(this.now()/60000);
    if(minute!==this.minute) {this.minute=minute;this.total=0;this.clients.clear();}
    if(++this.total>this.globalLimit)return false;
    const key=createHmac('sha256',this.key).update(String(identity).slice(0,256)).digest('hex');
    if(!this.clients.has(key)&&this.clients.size>=this.maximumClients)return false;
    const count=(this.clients.get(key)||0)+1;this.clients.set(key,count);
    return count<=this.clientLimit;
  }
}
