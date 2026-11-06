import { createServer } from 'node:http';
import { Readable } from 'node:stream';
import { createHandler } from './http.mjs';
import { equalSecret } from './security.mjs';

/** Only fixed aggregate status counters leave this boundary. No request logs or thrown error text. */
export function createRuntime(service,{operatorTokens,production=false,ingressKey,issuer,host='127.0.0.1',publicPort=8792,controlPort=8793,onSummary=()=>{}}) {
  if(production && !/^[A-Za-z0-9_-]{43}$/.test(ingressKey||''))throw new Error('Invalid ingress credential');
  const expectedHost=new URL(issuer).host;
  const counts={ok:0,denied:0,limited:0,failure:0};
  let stopping=false;
  const publicHandler=createHandler(service,{operatorTokens,surface:'public'});
  const controlHandler=createHandler(service,{operatorTokens,surface:'control'});
  function listener(handle,isPublic) {
    return createServer({maxHeaderSize:8192},async(req,res)=>{
      try {
        if(stopping){res.writeHead(503,{'Cache-Control':'no-store'});res.end();return;}
        if(!req.url || req.url.length>2048){res.writeHead(414);res.end();return;}
        if(production&&isPublic&&(!equalSecret(req.headers['x-licensing-ingress-key'],ingressKey)||req.headers.host!==expectedHost)) {
          counts.denied++;res.writeHead(403,{'Cache-Control':'no-store'});res.end();return;
        }
        const identity=production&&isPublic ? req.headers['x-licensing-client-ip'] : req.socket.remoteAddress;
        if(production&&isPublic&&(typeof identity!=='string'||identity.length>128)) {
          counts.denied++;res.writeHead(403,{'Cache-Control':'no-store'});res.end();return;
        }
        const request=new Request(new URL(req.url,'http://localhost'),{method:req.method,headers:req.headers,
          ...(req.method==='POST'?{body:Readable.toWeb(req),duplex:'half'}:{})});
        const result=await handle(request,{clientIdentity:identity||'unknown'});
        counts[result.status===429?'limited':result.status>=500?'failure':result.status>=400?'denied':'ok']++;
        res.writeHead(result.status,Object.fromEntries(result.headers));res.end(Buffer.from(await result.arrayBuffer()));
      } catch {counts.failure++;res.writeHead(400,{'Cache-Control':'no-store'});res.end();}
    });
  }
  const publicServer=listener(publicHandler,true),controlServer=listener(controlHandler,false);
  for(const server of [publicServer,controlServer]) {
    server.requestTimeout=10000;server.headersTimeout=5000;server.keepAliveTimeout=5000;
    server.maxHeadersCount=24;server.maxRequestsPerSocket=100;
    server.on('clientError',(_,socket)=>socket.destroy());
  }
  let maintenanceFailed=false;
  function summary(){onSummary({event:'licensing_summary',...counts,maintenanceFailed});for(const key of Object.keys(counts))counts[key]=0;}
  const maintenance=setInterval(()=>{try{service.maintain();maintenanceFailed=false;}catch{maintenanceFailed=true;}},3600000);
  const monitoring=setInterval(summary,60000);maintenance.unref();monitoring.unref();
  return {
    publicServer,controlServer,
    async start(){
      const listen=(server,port)=>new Promise((resolve,reject)=>{server.once('error',reject);server.listen(port,host,resolve);});
      try{await listen(publicServer,publicPort);await listen(controlServer,controlPort);}
      catch(error){await this.close();throw error;}
    },
    async close(){
      stopping=true;clearInterval(maintenance);clearInterval(monitoring);
      await Promise.all([publicServer,controlServer].map(server=>new Promise(resolve=>{
        if(!server.listening)return resolve();
        const timeout=setTimeout(()=>server.closeAllConnections(),11000);timeout.unref();
        server.close(()=>{clearTimeout(timeout);resolve();});server.closeIdleConnections();
      })));
      summary();
    },
  };
}
