import {createServer, request as upstreamRequest} from 'node:http';
import {isIP} from 'node:net';

// Only this port is exposed by Fly Proxy; backend/admin listeners stay on loopback.
export function createFlyIngress({issuer, ingressKey, backendPort=8792, operationalHealth=()=>true}) {
  const expectedHost=new URL(issuer).host;
  const patients=new Set(['/v2/invitations/redeem','/v1/sponsorship/refresh','/v1/sponsorship/disconnect']);
  const server=createServer({maxHeaderSize:8192},async(req,res)=>{
    const finish=(status)=>{res.writeHead(status,{'Cache-Control':'no-store','Content-Type':'application/json','X-Content-Type-Options':'nosniff'});res.end(JSON.stringify({ok:status===200}));};
    try {
      if(req.method==='GET'&&req.url==='/ops/health'){finish(await operationalHealth()?200:503);return;}
      if(!((req.method==='POST'&&patients.has(req.url))||(req.method==='GET'&&['/healthz','/readyz'].includes(req.url)))){finish(404);return;}
      const clientIP=req.headers['fly-client-ip'];
      // Fly Proxy supplies this header. Never use client-provided X-Forwarded-For.
      if(typeof clientIP!=='string'||!isIP(clientIP)){finish(403);return;}
      const chunks=[];let length=0;
      for await(const chunk of req){length+=chunk.length;if(length>16384){finish(413);return;}chunks.push(chunk);}
      const headers={'Host':expectedHost,'X-Licensing-Ingress-Key':ingressKey,'X-Licensing-Client-IP':clientIP,
        'Content-Type':req.headers['content-type']||'application/json'};
      if(req.headers.origin)headers.Origin=req.headers.origin;
      const upstream=upstreamRequest({host:'127.0.0.1',port:backendPort,path:req.url,method:req.method,headers},reply=>{
        res.writeHead(reply.statusCode,reply.headers);reply.pipe(res);
      });
      upstream.setTimeout(15000,()=>upstream.destroy());
      upstream.on('error',()=>{if(!res.headersSent)finish(503);else res.destroy();});
      res.on('close',()=>upstream.destroy());upstream.end(Buffer.concat(chunks));
    }catch{if(!res.headersSent)finish(400);else res.destroy();}
  });
  server.requestTimeout=10000;server.headersTimeout=5000;server.keepAliveTimeout=5000;
  server.maxHeadersCount=24;server.on('clientError',(_,socket)=>socket.destroy());
  return server;
}
