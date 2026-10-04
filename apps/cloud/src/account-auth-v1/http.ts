import { assertJsonContentType, json, readBoundedBody } from "../http";
import { SyntheticNativeAuthority } from "./authority";
import { AuthError, type BrowserIdentity } from "./model";
import { AUTH_BODY_BYTES, exactFields, parseAuthObject } from "./parsing";

const ROUTES = new Map([
  ["/account/authorize", "GET"], ["/api/account-auth/v1/decision", "POST"],
  ["/api/account-auth/v1/token", "POST"], ["/api/account-auth/v1/sessions", "GET"],
  ["/api/account-auth/v1/revoke", "POST"],
]);
export function isNativeAuthPath(path: string): boolean { return ROUTES.has(path); }
export function nativeAuthUnavailable(): Response {
  return json({ error: "unavailable" }, { status: 503 });
}
export interface BrowserIdentityAdapter {
  /** Existing auth only. Revalidate Cookie, CSRF and recent reauth; never trust posted account/session IDs. */
  verify(request: Request, requirements: { csrf: boolean; recent: boolean }): Promise<BrowserIdentity | null>;
}
export interface SyntheticHttpDependencies {
  authority: SyntheticNativeAuthority;
  browser: BrowserIdentityAdapter;
  // Trusted, bounded client-address label; purpose-HMAC happens in the authority before persistence.
  rateLabel: (request: Request) => string;
}
const statuses = { unavailable: 503, verification_pending: 503, invalid_request: 400, invalid_grant: 400,
  reuse_family_revoked: 400, unauthorized: 401, forbidden: 403, not_found: 404, rate_limited: 429 } as const;
function secure(response: Response): Response {
  const headers = new Headers(response.headers);
  headers.set("Cache-Control", "no-store");
  headers.set("Referrer-Policy", "no-referrer");
  headers.set("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'; base-uri 'none'");
  headers.set("X-Frame-Options", "DENY");
  headers.set("X-Content-Type-Options", "nosniff");
  return new Response(response.body, { status: response.status, headers });
}
/** No checked-in runtime registration or activation path: default is unavailable, not an env flag. */
export function createNativeAuthHttp(dependencies?: SyntheticHttpDependencies): (request: Request) => Promise<Response> {
  const deps = dependencies ? { ...dependencies } : undefined;
  return async (request) => {
    try {
      const url = new URL(request.url);
      if (ROUTES.get(url.pathname) !== request.method) throw new AuthError("not_found");
      if (!deps) return secure(nativeAuthUnavailable());
      const authority = deps.authority;
      if (url.origin !== authority.registration.issuer || url.username || url.password || url.hash ||
          (url.pathname !== "/account/authorize" && (url.search ||
            request.url !== `${authority.registration.issuer}${url.pathname}`))) throw new AuthError("invalid_request");
      const browser = async (csrf: boolean, recent: boolean): Promise<BrowserIdentity> => {
        if (request.headers.has("Authorization") || request.headers.get("Origin") !== authority.registration.issuer ||
            !request.headers.has("Cookie") || (csrf && !request.headers.get("X-HealthMd-CSRF"))) {
          throw new AuthError("unauthorized");
        }
        const identity = await deps.browser.verify(request, { csrf, recent });
        if (!identity) throw new AuthError("unauthorized");
        return identity;
      };
      const nativeOnly = () => {
        if (request.headers.has("Cookie")) throw new AuthError("unauthorized");
      };
      const bearer = (): string => {
        nativeOnly();
        const match = /^Bearer (hmd_nac_[A-Za-z0-9_-]{43})$/u.exec(request.headers.get("Authorization") ?? "");
        if (!match?.[1]) throw new AuthError("unauthorized");
        return match[1];
      };
      const body = async (): Promise<Uint8Array> => {
        try {
          assertJsonContentType(request);
          return await readBoundedBody(request, AUTH_BODY_BYTES, Date.now() + 5000);
        } catch { throw new AuthError("invalid_request"); }
      };
      switch (url.pathname) {
        case "/account/authorize": {
          const identity = await browser(false, false);
          // No consent UI or browser persistence installed. Synthetic response is review metadata only.
          const label = deps.rateLabel(request);
          if (typeof label !== "string" || label.length === 0 || label.length > 256) throw new AuthError("unavailable");
          return secure(json(await authority.begin(request.url, identity, label)));
        }
        case "/api/account-auth/v1/decision": {
          const identity = await browser(true, false);
          const v = parseAuthObject(await body());
          exactFields(v, ["authorization_id", "decision"]);
          const result = await authority.decide(v.authorization_id!, v.decision!, identity);
          // Callback contains only a short-lived code/state/issuer, not access/refresh/account IDs.
          return secure(new Response(null, { status: 303, headers: { Location: result.callback } }));
        }
        case "/api/account-auth/v1/token":
          nativeOnly();
          if (request.headers.has("Authorization")) throw new AuthError("unauthorized");
          return secure(json(await authority.token(await body())));
        case "/api/account-auth/v1/sessions": {
          const sessions = request.headers.has("Cookie") ?
            await authority.browserSessions(await browser(true, true)) : await authority.nativeSessions(bearer());
          return secure(json({ sessions }));
        }
        case "/api/account-auth/v1/revoke": {
          const v = parseAuthObject(await body());
          if (request.headers.has("Cookie")) {
            const identity = await browser(true, true);
            exactFields(v, ["session_id"]);
            return secure(json(await authority.revoke({ kind: "browser", identity, sessionId: v.session_id! })));
          }
          nativeOnly();
          if (request.headers.has("Authorization")) {
            exactFields(v, []);
            return secure(json(await authority.revoke({ kind: "access", token: bearer() })));
          }
          exactFields(v, ["refresh_token", "client_id", "installation_id"]);
          return secure(json(await authority.revoke({ kind: "refresh", token: v.refresh_token!,
            clientId: v.client_id!, installationId: v.installation_id! })));
        }
        default: throw new AuthError("not_found");
      }
    } catch (error) {
      const code = error instanceof AuthError ? error.code : "verification_pending";
      return secure(json({ error: code }, { status: statuses[code] }));
    }
  };
}
