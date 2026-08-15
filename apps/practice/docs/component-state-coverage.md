# Synthetic portal component and state coverage

This is an evidence index, not proof of TODO/epic completion or a production/manual-accessibility qualification claim. Substantial synthetic automation is partial evidence while named backend and external gates remain open. `UI automated` means rendered DOM/user interaction was exercised with an injected client. `Handler/service only` is not UI evidence. `Pending` identifies work that repository automation cannot establish.

## Shared primitives

| Primitive/state | Evidence level | Test evidence |
| --- | --- | --- |
| Safe text and responsive semantic table | UI automated + axe | `clinical-components.test.tsx`; hostile and large-report cases |
| Text/date/time/number/select/radio controls | UI automated | request and template builder flows |
| Linked error summary, focus, inline `aria-invalid` | UI automated | primitive and blocking builder tests |
| Loading/empty/error/denied/stale notices | UI automated | primitive matrix and route-state tests |
| Confirmation initial focus, Tab/Shift+Tab containment, Escape close, actual focus restoration | UI automated | `clinical-components.test.tsx` |
| Pagination and live announcements | UI automated | inbox/audit and navigation tests |
| SVG title/description plus complete table alternative | UI automated + axe | report tests |
| Skip link and route focus movement | UI automated | review-fix navigation tests |
| Reduced motion, forced colors, narrow 400%-equivalent reflow, focus-not-obscured, print CSS | Real-browser automated; manual pending | `e2e/practice.synthetic.spec.ts`; bundled engines are not manual latest-two/device qualification |
| Color contrast | Real-browser axe automated; manual pending | Playwright axe runs with color contrast enabled; jsdom still disables only its non-rendering contrast rule |
| Keyboard and dialog focus | Real-browser + component automated | sign-in/navigation/actions, initial dialog focus, Escape restoration; component suite covers Tab/Shift+Tab containment |
| Browser privacy surfaces | Real-browser automated | loopback-only network interception; path/query/referrer checks; HttpOnly cookie; empty storage/IndexedDB/service workers/cache; clean console/page errors |

## Routes and states

| Family | UI automated | Handler/service only or pending |
| --- | --- | --- |
| Sign-in/MFA/bootstrap/logout | Sign-in, MFA, server bootstrap truth, logout clearing; real App→client→Worker integration | Replay/rate/fixation details also covered at handler/service level; real IdP pending |
| Recovery/denied/expired/unavailable | Rendered and axe-checked | Manual browser/assistive-technology review pending |
| History/address lifecycle | query/fragment scrubbing, popstate, pagehide secret clearing, persisted-pageshow fail-closed bootstrap | Real browser bfcache pending |
| Relationships | zero, unique, ambiguous, inactive, denied behavior and explicit selection | Tenant/rate-limit matrix remains handler/service evidence |
| Templates | list/error, actual structured create validation, revise, archive, stale presentation | Production-approved template values pending |
| Requests | active-template revision binding, no-template block, fixed builder, blocking relative semantics, canonical preview, exact idempotent retry, cancel, explicit recurring successor with a newly entered period | Full server validation corpus remains domain/service evidence |
| Invitation | one-time route-local display, fixed-date/timezone/UTC materialization, exact instruction/review-digest binding, claim and accept, revoke, expire, cancel, pagehide/remount clearing, lifecycle reload | QR/deep-link rendering explicitly blocked pending approved mobile contract; replay/expiry clocks also service-tested |
| Inbox | filter body, empty/error/loading, cursor pagination, selection | Every backend availability enum is service-tested; not every enum has a dedicated UI interaction test |
| Report/view/history/print | inaccessible fail-closed, small and 80-row complete list in the fixed request timezone, disclosures/chart alternative, safe immutable JSON download, opened-on-render-or-download, capability gating, print negative inference, acknowledgment, review, stale action, immutable history | Native print/PDF visual review and real-browser download behavior pending |
| Members | role/offboard/revoke controls, step-up confirmation, post-mutation bootstrap, action-error handling | Cross-tenant and concurrent revocation remain service/security evidence |
| Retention | draft policy, deletion/hold/progress rendering | No mutation API exists in M1; production policy/legal approval pending |
| Audit | filter, empty table, cursor/next pagination | Large partitions and authorization denial also service-tested |

## Automated suites

- `e2e/practice.synthetic.spec.ts`: serial bundled Chromium/Firefox/WebKit workflows against real local Wrangler, rendered axe/keyboard/reflow/print/download/privacy checks, clinician lifecycle and admin gates.
- `security-matrix.test.ts`: canonical-policy-driven per-operation public, no-session, opposite-role, and applicable foreign-identifier denials.
- `src/contracts/authorization-policy.json`: canonical route/operation capabilities, roles, classifications, and denial applicability.
- `qualification/v1/security-inventory.json`: exact canonical-policy mirror and evidence index; the manifest itself is not proof.
- `clinical-components.test.tsx`: primitive semantics, focus, keyboard containment, hostile text, and axe.
- `portal-flows.test.tsx`: major clinician/admin flows, exact report output/actions/download, role navigation, and storage/network constraints.
- `review-fixes.test.tsx`: review regressions and actual route/state/action coverage.
- `app-worker-integration.test.tsx`: App → operation client → Worker handler sign-in/MFA/bootstrap/protected-operation path.
- Existing domain/service/handler/security tests remain separate evidence and are not relabeled as UI coverage.

## Explicitly pending external/manual gates

Latest-two Chrome/Edge/Firefox/Safari **manual** qualification, supported screen readers/manual AT, visual 400% zoom and forced-colors/high-contrast inspection, touch-device testing, native print/PDF reading order, production backend/IdP/persistence, migration/rollback/backup-restore/authoritative purge, compliance/BAA review, independent penetration testing, approved mobile invitation contract, and pilot-practice approval remain pending. Synthetic automation must not be used to claim any of those gates.
