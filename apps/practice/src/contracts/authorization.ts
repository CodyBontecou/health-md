import authorizationPolicy from "./authorization-policy.json";
import type { Capability, OperationName, Role } from "./clinical";

export type PolicyRequirement = "public" | "authenticated" | Capability;
export type TenantEvidence = "none" | "deny_foreign_resource" | "filter_foreign_results";

export interface AuthorizationPolicyEntry {
  requiredCapability: PolicyRequirement;
  authorizedRoles: readonly Role[];
}

const operations = new Map(authorizationPolicy.operations.map(entry => [entry.operation as OperationName, entry]));
const routes = new Map(authorizationPolicy.routes.map(entry => [entry.route, entry]));

export const canonicalRoleCapabilities = authorizationPolicy.roleCapabilities as Readonly<Record<Role, readonly Capability[]>>;

export function operationPolicy(operation: OperationName) {
  const entry = operations.get(operation);
  if (!entry) throw new Error("Canonical operation policy is incomplete");
  return entry as typeof entry & AuthorizationPolicyEntry;
}

export function routePolicy(route: string) {
  const entry = routes.get(route);
  if (!entry) throw new Error("Canonical route policy is incomplete");
  return entry as typeof entry & AuthorizationPolicyEntry;
}

export function roleSatisfiesPolicy(role: Role, capabilities: readonly Capability[], entry: AuthorizationPolicyEntry): boolean {
  if (entry.requiredCapability === "public") return true;
  if (!entry.authorizedRoles.includes(role)) return false;
  return entry.requiredCapability === "authenticated" || capabilities.includes(entry.requiredCapability);
}
