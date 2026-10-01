# Split-production account invite runbook

**Status:** source procedure only; no staging or production invite/resource is provisioned or approved.

Split account Workers admit a first account only when D1 contains an unexpired `account_invites.email_lookup` row from migration `0018_account_invites.sql`. The lookup is `HMAC-SHA256(identity key, "email-lookup-v1\0" + normalized email)`. Raw invite addresses are never stored in D1 or split Worker configuration. The account-creation transaction rechecks authority, creates at most one account for the lookup, consumes the invite, and creates the one-time magic link. A revoked or expired row cannot authorize an account even if an earlier eligibility read raced with revocation.

The combined development/VM profile retains its small `AUTH_INVITE_EMAILS` compatibility behavior. Split production rejects that variable.

## Preconditions

Do not run this procedure until all of the following are true:

1. the environment and exact D1 database are explicitly authorized for the intended synthetic or controlled cohort;
2. migrations through `0018_account_invites.sql` are verified on that database;
3. product/privacy/security/operations owners approved the cohort, expiry, support path and operator;
4. an approved workstation can temporarily access the exact account Worker's 32-byte identity key through the approved key-custody procedure; and
5. an owner-only working directory and reviewed Wrangler deployment identity are active.

Never use the pilot database/key for future production, put an email or identity key in a shell argument, upload the input/output files, or retain the files in source control, shell history, CI artifacts, tickets, logs or chat.

## Prepare a grant offline

Create an owner-only UTF-8 input file with one email per line (maximum 1,000) and an owner-only file containing only the canonical base64 identity key. Use a future expiry no more than 90 days away. The tool normalizes addresses, rejects duplicates/unsafe file modes, and creates a new mode-`0600` SQL file containing only lookup hashes and timestamps:

```bash
umask 077
export HEALTHMD_INVITE_EMAIL_FILE=/approved/private/cohort-emails.txt
export HEALTHMD_IDENTITY_KEY_FILE=/approved/private/account-identity-key.txt
export HEALTHMD_INVITE_SQL_OUTPUT=/approved/private/account-invite-grants.sql
export HEALTHMD_INVITE_OPERATION=grant
export HEALTHMD_INVITE_EXPIRES_AT=REPLACE_WITH_APPROVED_FUTURE_ISO_TIMESTAMP_WITHIN_90_DAYS
npm run prepare:account-invites
unset HEALTHMD_INVITE_EMAIL_FILE HEALTHMD_IDENTITY_KEY_FILE \
  HEALTHMD_INVITE_SQL_OUTPUT HEALTHMD_INVITE_OPERATION HEALTHMD_INVITE_EXPIRES_AT
```

The fixed success line reports only a count. Inspect permissions and confirm mechanically that the SQL contains no `@` before application without printing the file. Treat lookup hashes as sensitive pseudonymous identity metadata even though they are not raw addresses.

Apply the exact reviewed file only to the explicitly authorized D1 database using the reviewed account-profile/operator procedure. Do not use the checked-in placeholder database name and do not paste SQL into a CLI argument. Capture migration version, aggregate inserted count, deployment revision, operator approval and timestamp—but not hashes or addresses—in the approved evidence store.

## Revoke unused invites

Prepare revocation SQL from the same normalized address file and exact identity key. Revocation requires no expiry:

```bash
umask 077
export HEALTHMD_INVITE_EMAIL_FILE=/approved/private/revoked-emails.txt
export HEALTHMD_IDENTITY_KEY_FILE=/approved/private/account-identity-key.txt
export HEALTHMD_INVITE_SQL_OUTPUT=/approved/private/account-invite-revocations.sql
export HEALTHMD_INVITE_OPERATION=revoke
npm run prepare:account-invites
unset HEALTHMD_INVITE_EMAIL_FILE HEALTHMD_IDENTITY_KEY_FILE \
  HEALTHMD_INVITE_SQL_OUTPUT HEALTHMD_INVITE_OPERATION
```

Apply and verify the revocation before telling anyone admission is closed. A concurrent first-account transaction must still recheck the row; source tests cover deletion between eligibility and commit. Revocation does not disable an account that already consumed its invite—use the reviewed account-deletion/security procedure for that distinct action.

## Verification and cleanup

- Verify only aggregate unexpired-invite counts unless an approved incident procedure requires more.
- Request one link only through the reviewed account origin; responses remain generic and must not be used to infer eligibility.
- Confirm the invite count decreases after the first successful account transaction and that a second account row is not created under concurrent requests.
- Scheduled maintenance removes at most 500 oldest expired invite rows per run and preserves unexpired rows.
- Securely remove the local address, key and SQL files according to approved key-custody and cohort-record policy after durable verification. Do not delete the authoritative secret from its key system.
- If application or verification is ambiguous, stop. Re-read aggregate durable state through the authorized path; do not issue a broader invite, enable open signup, or rotate identity keys as a workaround.
