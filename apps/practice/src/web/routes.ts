import authorizationPolicy from "../contracts/authorization-policy.json";

/** Fixed routes are sourced from the canonical authorization policy. */
export const portalRoutes = Object.freeze(authorizationPolicy.routes.map(item => item.route));

export type PortalRoute = (typeof portalRoutes)[number];

export function isPortalRoute(pathname: string): pathname is PortalRoute {
  return portalRoutes.includes(pathname);
}

export function assertSafeRouteManifest(): void {
  for (const route of portalRoutes) {
    if (
      route.includes("?") ||
      route.includes(":") ||
      route.includes("[") ||
      route.includes("]") ||
      route.includes("{") ||
      route.includes("}") ||
      /\/[0-9a-f]{8}(?:-|$)/i.test(route)
    ) {
      throw new Error(`Unsafe dynamic Practice route: ${route}`);
    }
  }
}
