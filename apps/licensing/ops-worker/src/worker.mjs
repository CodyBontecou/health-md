import {timingSafeEqual} from 'node:crypto';
const reply=(status,value={ok:status<400})=>new Response(JSON.stringify(value),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
export async function authorized(request,secret){
  if(typeof secret!=='string'||!/^[A-Za-z0-9_-]{43}$/.test(secret))return false;
  const received=request.headers.get('Authorization')||'';
  const digest=value=>crypto.subtle.digest('SHA-256',new TextEncoder().encode(value));
  const [a,b]=await Promise.all([digest(received),digest('Bearer '+secret)]);
  return timingSafeEqual(new Uint8Array(a),new Uint8Array(b));
}
export async function sendAlert(env,subject,text){
  await env.EMAIL.send({from:env.ALERT_FROM,to:env.ALERT_TO,subject:'[Health.md licensing] '+subject,text,html:'<pre>'+text.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;')+'</pre>'});
}
export async function checkHealth(env,now=Date.now(),fetcher=(...args)=>fetch(...args)){
  let serviceOK=false,backupOK=false,serviceHTTPStatus=0,serviceFailure=null;
  try{
    const response=await fetcher(env.SERVICE_HEALTH_URL,{redirect:'manual',signal:AbortSignal.timeout(10000),headers:{'Cache-Control':'no-store'}});
    serviceHTTPStatus=response.status;serviceOK=response.status===200;await response.body?.cancel();
  }catch(error){serviceFailure=['TypeError','TimeoutError','AbortError'].includes(error?.name)?error.name:'transport_error';}
  try{
    const latest=await env.BACKUPS.get('status/latest.json');
    const value=latest?await latest.json():null;
    backupOK=Number.isSafeInteger(value?.uploadedAt)&&now>=value.uploadedAt&&now-value.uploadedAt<7200000&&!!(await env.BACKUPS.head(value.key));
  }catch{}
  const problem=[...(!serviceOK?['service_unhealthy']:[]),...(!backupOK?['backup_stale']:[])].join(',');
  const previous=await env.STATE.get('health',{type:'json'})||{problem:'',failures:0,lastAlert:0};
  const failures=problem?(previous.problem===problem?previous.failures+1:1):0;
  let lastAlert=previous.lastAlert;
  if(problem&&failures>=2&&(previous.notified!==problem||now-lastAlert>=21600000)){
    await sendAlert(env,'Action required',`Checks failed: ${problem}.\nService: ${env.SERVICE_HEALTH_URL}\nNo clinic, patient or credential data is included.\nCheck Fly health/log summaries and off-host backups.`);
    lastAlert=now;
  }else if(!problem&&previous.notified){
    await sendAlert(env,'Recovered','Licensing service health and off-host backup freshness checks have recovered.');lastAlert=now;
  }
  await env.STATE.put('health',JSON.stringify({problem,failures,lastAlert,notified:problem&&failures>=2?problem:problem?previous.notified:null,checkedAt:now,serviceHTTPStatus,serviceFailure}));
  return {ok:!problem};
}
export default {
  async fetch(request,env){
    try{
      const url=new URL(request.url);if(url.search)return reply(404);
      if(request.method==='PUT'&&url.pathname==='/v1/backup'){
        if(!await authorized(request,env.UPLOAD_TOKEN))return reply(401);
        const size=Number(request.headers.get('Content-Length'));
        if(!Number.isSafeInteger(size)||size<34||size>67108864||request.headers.get('Content-Type')!=='application/octet-stream')return reply(413);
        const key=`archives/${Date.now()}-${crypto.randomUUID()}.hmlb`;
        // Require the encrypted archive magic and fixed length before publishing the object.
        let prefix=new Uint8Array(0);
        const checked=request.body.pipeThrough(new TransformStream({
          transform(chunk,controller){
            if(prefix.length<5){
              const bytes=new Uint8Array(chunk),combined=new Uint8Array(Math.min(5,prefix.length+bytes.length));
              combined.set(prefix);combined.set(bytes.subarray(0,combined.length-prefix.length),prefix.length);prefix=combined;
              if(prefix.length===5&&new TextDecoder().decode(prefix)!=='HMLB1')throw new Error('invalid_archive');
            }
            controller.enqueue(chunk);
          },flush(){if(prefix.length!==5)throw new Error('invalid_archive');},
        }));
        const fixed=new FixedLengthStream(size);
        const pumping=checked.pipeTo(fixed.writable);
        await Promise.all([pumping,env.BACKUPS.put(key,fixed.readable,{httpMetadata:{contentType:'application/octet-stream'}})]);
        await env.BACKUPS.put('status/latest.json',JSON.stringify({key,uploadedAt:Date.now()}));
        return reply(201);
      }
      if(!await authorized(request,env.OPERATIONS_TOKEN))return reply(404);
      if(request.method==='POST'&&url.pathname==='/v1/check')return reply(200,await checkHealth(env));
      if(request.method==='POST'&&url.pathname==='/v1/test-alert'){
        await sendAlert(env,'Alert delivery test','Production licensing alert delivery is configured. This test contains no clinic data or secrets.');return reply(200);
      }
      if(request.method==='GET'&&url.pathname==='/v1/backup/latest'){
        const status=await env.BACKUPS.get('status/latest.json');if(!status)return reply(404);
        const latest=await status.json(),object=await env.BACKUPS.get(latest.key);if(!object)return reply(404);
        return new Response(object.body,{headers:{'Content-Type':'application/octet-stream','Cache-Control':'no-store'}});
      }
      return reply(404);
    }catch{return reply(503);}
  },
  async scheduled(_event,env,ctx){
    if(env.MONITOR_ENABLED!=='true')return;
    ctx.waitUntil(checkHealth(env).catch(()=>{console.error(JSON.stringify({event:'licensing_monitor_failed'}));}));
  },
};
