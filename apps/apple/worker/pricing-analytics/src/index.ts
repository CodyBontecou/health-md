/** Retired custom analytics endpoint. No body reads, identifiers, logs, storage, or outbound requests. */
export default {
  async fetch(request: Request): Promise<Response> {
    const path = new URL(request.url).pathname.replace(/\/+$/, "");
    const headers = { "Cache-Control": "no-store", "Access-Control-Allow-Origin": "*" };
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: { ...headers,
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization" } });
    }
    if (request.method === "GET" && path === "/health") {
      return Response.json({ status: "retired", collection: false }, { headers });
    }
    if (request.method === "POST" && path === "/v1/events") {
      // Legacy clients treat 2xx as delivered and drop queued events. Do not parse the body.
      return new Response(null, { status: 204, headers });
    }
    return new Response(null, { status: 410, headers });
  },
};
