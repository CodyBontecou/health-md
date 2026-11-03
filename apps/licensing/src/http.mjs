import { equalSecret, RequestLimiter } from './security.mjs';
import { LicensingError } from './service.mjs';

const response = (body, status = 200) => new Response(JSON.stringify(body), {status,headers:{
  'Content-Type':'application/json', 'Cache-Control':'no-store',
  'X-Content-Type-Options':'nosniff', 'Content-Security-Policy':"default-src 'none'",
}});

async function readObject(request) {
  if (!/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(request.headers.get('content-type')||'')) throw new LicensingError(415,'json_required');
  if (!request.body) throw new LicensingError(400,'invalid_request');
  const reader=request.body.getReader(), chunks=[]; let size=0;
  try {
    while(true) {
      const {done,value}=await reader.read(); if(done)break;
      size+=value.byteLength;
      if(size>16384) {await reader.cancel();throw new LicensingError(413,'request_too_large');}
      chunks.push(Buffer.from(value));
    }
    const value=JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if(!value || typeof value!=='object' || Array.isArray(value))throw new Error();
    return value;
  } catch(error) {
    if(error instanceof LicensingError)throw error;
    throw new LicensingError(400,'invalid_request');
  } finally {reader.releaseLock();}
}

function fields(body, required) {
  if(Object.keys(body).sort().join(',')!==[...required].sort().join(','))throw new LicensingError(400,'invalid_request');
}

/** Bearer-only fixed-path API; no cookies, CORS, health payloads, URLs or identities in logs. */
export function createHandler(service, { operatorToken, operatorTokens=[operatorToken], surface="all", limiter=new RequestLimiter() }) {
  if(!operatorTokens.length || operatorTokens.some(token=>typeof token!=="string" || !/^[A-Za-z0-9_-]{32,128}$/.test(token)))throw new Error("Operator credentials required");
  return async (request, {clientIdentity="local"}={}) => {
    try {
      const url=new URL(request.url);
      if(!limiter.allow(clientIdentity))return new Response(JSON.stringify({error:'rate_limited'}),{status:429,headers:{'Content-Type':'application/json','Cache-Control':'no-store','Retry-After':'60'}});
      if(!url.search && request.method==='GET' && ['/healthz','/readyz'].includes(url.pathname)) {
        if(url.pathname==='/readyz')service.db.prepare('SELECT 1').get();
        return response({ok:true});
      }
      if(request.headers.has('origin'))return response({error:'native_client_required'},403);
      if(url.search || request.method!=='POST')return response({error:'not_found'},404);
      const known=new Set(['/v2/invitations/redeem','/v1/sponsorship/refresh','/v1/sponsorship/disconnect',
        '/v1/admin/invitations','/v1/admin/revoke','/v1/operator/clinics','/v1/operator/activate','/v1/operator/suspend','/v1/operator/rotate-admin','/v1/operator/erase','/v1/admin/memberships']);
      const control=url.pathname.startsWith('/v1/operator/')||url.pathname.startsWith('/v1/admin/');
      if((surface==='public'&&control)||(surface==='control'&&!control))return response({error:'not_found'},404);
      if(!known.has(url.pathname))return response({error:'not_found'},404);
      const bearer=request.headers.get('authorization')?.match(/^Bearer ([A-Za-z0-9_-]{32,128})$/)?.[1];
      if(url.pathname.startsWith('/v1/operator/')) {
        if(!bearer || !operatorTokens.map(token=>equalSecret(bearer,token)).some(Boolean))throw new LicensingError(401,'unauthorized');
      } else if(url.pathname.startsWith('/v1/admin/')) service.clinicAdmin(bearer);
      const body=await readObject(request);
      switch(url.pathname) {
        case '/v1/operator/clinics':
          fields(body,['name','endpoint','paidThroughMilliseconds']);return response(service.provisionClinic(body),201);
        case '/v1/operator/activate':
          fields(body,['clinicID','paidThroughMilliseconds']);service.activate(body.clinicID,body.paidThroughMilliseconds);return response({ok:true});
        case '/v1/operator/suspend':
          fields(body,['clinicID']);service.suspendClinic(body.clinicID);return response({ok:true});
        case '/v1/operator/rotate-admin':
          fields(body,['clinicID']);return response(service.rotateAdmin(body.clinicID));
        case '/v1/operator/erase':
          fields(body,['clinicID']);service.eraseClinic(body.clinicID);return response({ok:true});
        case '/v1/admin/memberships':
          fields(body,['after']);return response(service.memberships(bearer,body.after));
        case '/v1/admin/invitations':
          fields(body,[]);return response(service.createInvitation(bearer),201);
        case '/v1/admin/revoke':
          fields(body,['sponsorshipID']);service.revoke(bearer,body.sponsorshipID);return response({ok:true});
        case '/v2/invitations/redeem':
          fields(body,['invitationCode','installationID','enrollmentSecret']);return response(service.redeem(body));
        case '/v1/sponsorship/refresh':
          fields(body,['refreshToken','installationID']);return response(service.refresh(body));
        case '/v1/sponsorship/disconnect':
          fields(body,['refreshToken','installationID']);service.disconnect(body);return response({ok:true});
      }
    } catch(error) {
      return error instanceof LicensingError ? response({error:error.code},error.status) : response({error:'internal_error'},500);
    }
  };
}
