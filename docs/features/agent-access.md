# Agent registration, grants, and activity history

This document describes the shared authorization core. It does not define an HTTP, MCP, or UI surface.

## Separate trust boundaries

Health.md treats these as different objects and checks:

1. **Client registration** identifies a user-approved client record and its kind. Registration metadata is not proof that the current request authenticated as that client.
2. **Client grant** records the scope the user explicitly approved for one registered client. A grant is pinned to one exact Health Context Profile ID and revision.
3. **Health Context Profile reference and effective policy** describe the health context the user chose and the policy currently effective for that exact revision. A profile is not a client credential or a client grant.
4. **HealthKit authorization** remains an OS-level boundary. Health.md cannot grant a client data that HealthKit has not made readable to Health.md.
5. **Destination class** says how authorized output leaves the operation. `api_endpoint` is a class only; endpoint URLs and credentials are configuration and never belong in activity history.

Authorization requires the exact request to fit the client grant, the supplied effective profile policy, and the supplied HealthKit authorization snapshot. A profile ID or revision mismatch is a denial. The core never rewrites an overbroad request into a narrower one: callers receive a stable reason code and must submit a new request.

The existing loopback CLI has no client identity or credential. Until a future transport performs registration and authentication, it must be represented as `legacy_unattributed_local_process`. It must not be labeled as an authenticated registered client.

## User-authorized scope can be unlimited

The user may explicitly approve:

- all historical time (`all_history`),
- all available metrics (`all_available`),
- every operation (`all_operations`),
- lossless individual records,
- every destination class (`all_destination_classes`), and
- a grant with no expiry.

The authorization core does not impose a hidden lookback, metric, record-count, byte, or destination policy cap on such a grant. Narrow grants remain supported with exact date ranges, selected metric IDs, selected operations, selected detail levels, selected destinations, expiry, pause, and revocation.

Optional `AgentResourceControls` are per-page or per-stream-chunk safety settings. Every page or chunk protocol that applies them must provide continuation until every authorized matching record is reachable. They are not total-query limits and must never turn an otherwise authorized record into permanently unreachable data.

## Grant lifecycle

A grant begins pending unless it carries explicit user confirmation and a confirmation timestamp. The manager centralizes confirmation, pause, resume, explicit expiry, time-based expiry, and revocation. Authorization checks expiry directly, so an expired grant cannot remain usable merely because maintenance has not materialized `expiredAt` yet. Revocation and expiry are terminal. Activity-history clearing does not modify registrations, grants, or Keychain credentials.

## Persistence and credentials

The manager is actor-isolated and writes versioned access and activity envelopes under Application Support using same-directory atomic replacement. Directories and files receive restrictive local permissions; iOS files also receive data-protection attributes. Store URLs and the clock are injectable for tests.

Authentication credentials use the `AgentCredentialStoring` Keychain seam. Credential bytes are never fields of any Codable registration, grant, request, decision, envelope, or activity model. The production adapter uses a dedicated Keychain service and this-device-only accessibility.

A corrupt or unsupported access store fails authorization closed with a structured reason. A corrupt activity store also prevents audited authorization until activity history is explicitly cleared. No corrupted bytes are silently interpreted as grants.

## PHI-minimized activity history

Each activity record stores only:

- opaque registration/grant/profile IDs and pinned profile revision,
- timestamp and UUID correlation ID,
- exact requested date range or `all_history`,
- exact metric IDs or `all_available`,
- requested operation, detail level, and destination class,
- result record and byte counts,
- outcome and stable reason code.

Activity records never store health values, prompts, filenames, file paths, endpoint URLs, peer names, credentials, response bodies, or exported content. Correlation IDs are UUIDs so arbitrary prompt or PHI text cannot be placed in that field.

Activity retention may be bounded independently by age, encoded storage size, and record count. This retention affects audit history only; it does not reduce authorization scope or data reachability.
