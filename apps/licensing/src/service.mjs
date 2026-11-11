import { createHash, createPrivateKey, randomBytes, randomUUID, sign } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';

const DAY = 86_400_000;
const hash = value => createHash('sha256').update(value).digest('hex');
const secret = () => randomBytes(32).toString('base64url');
const id = value => typeof value === 'string' && /^[A-Za-z0-9_-]{16,128}$/.test(value);
const millis = value => Number.isSafeInteger(value) && value >= 0;

export class LicensingError extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}
function requireThat(condition, status = 400, code = 'invalid_request') {
  if (!condition) throw new LicensingError(status, code);
}

export function canonicalEndpoint(value) {
  if (typeof value !== 'string' || /[^\x21-\x7e]/.test(value)) return null;
  const match = /^https:\/\/([A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?)(?::([0-9]{1,5}))?(\/[A-Za-z0-9._~!$&'()*+,;=:@/-]*)?$/i.exec(value);
  if (!match) return null;
  const host = match[1].toLowerCase(), labels = host.split('.');
  if (host.length > 253 || labels.length < 2 || labels.some(x => !x || x.length > 63 || x.startsWith('-') || x.endsWith('-')) || labels.every(x => /^\d+$/.test(x))) return null;
  const port = match[2] ? Number(match[2]) : 443, path = match[3] || '/';
  if (port < 1 || port > 65535 || path.includes('//') || path.split('/').some(x => x === '.' || x === '..')) return null;
  return `https://${host}${port === 443 ? '' : `:${port}`}${path}`;
}

/** Isolated licensing metadata only. This service never receives or forwards health exports. */
export class LicensingService {
  constructor({ databasePath, privateKey, keyID, issuer, audience = 'healthmd-clinic-access', now = Date.now }) {
    requireThat(typeof databasePath === 'string' && /^[A-Za-z0-9_-]{1,64}$/.test(keyID));
    requireThat(typeof issuer === 'string' && issuer.startsWith('https://'));
    this.key = createPrivateKey(privateKey);
    requireThat(this.key.asymmetricKeyType === 'ec' && this.key.asymmetricKeyDetails.namedCurve === 'prime256v1');
    this.keyID = keyID; this.issuer = issuer; this.audience = audience; this.now = now;
    this.db = new DatabaseSync(databasePath);
    try {
      const version = this.db.prepare('PRAGMA user_version').get().user_version;
      requireThat(version <= 1, 500, 'unsupported_database_version');
      this.db.exec(`PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA busy_timeout=5000;
        CREATE TABLE IF NOT EXISTS clinics (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, endpoint TEXT NOT NULL,
          destination_id TEXT NOT NULL, policy_version INTEGER NOT NULL,
          paid_through INTEGER NOT NULL, revoked INTEGER NOT NULL DEFAULT 0,
          admin_hash TEXT NOT NULL UNIQUE);
        CREATE TABLE IF NOT EXISTS invitations (
          token_hash TEXT PRIMARY KEY, clinic_id TEXT NOT NULL REFERENCES clinics(id),
          expires_at INTEGER NOT NULL, redeemed INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS sponsorships (
          id TEXT PRIMARY KEY, clinic_id TEXT NOT NULL REFERENCES clinics(id),
          installation_id TEXT NOT NULL, refresh_hash TEXT NOT NULL UNIQUE,
          revoked INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
        CREATE INDEX IF NOT EXISTS sponsorship_clinic ON sponsorships(clinic_id);`);
      if (version === 0) {
        this.db.exec(`BEGIN IMMEDIATE;
          ALTER TABLE sponsorships ADD COLUMN enrollment_invitation_hash TEXT;
          ALTER TABLE sponsorships ADD COLUMN recovery_until INTEGER;
          ALTER TABLE sponsorships ADD COLUMN revoked_at INTEGER;
          CREATE UNIQUE INDEX sponsorship_invitation ON sponsorships(enrollment_invitation_hash);
          CREATE TABLE audit (action TEXT NOT NULL, clinic_id TEXT NOT NULL, at INTEGER NOT NULL);
          PRAGMA user_version=1; COMMIT;`);
      }
    } catch (error) {
      try { this.db.exec('ROLLBACK'); } catch { }
      this.db.close(); throw error;
    }
  }

  close() { this.db.close(); }

  provisionClinic({ name, endpoint, paidThroughMilliseconds }) {
    const canonical = canonicalEndpoint(endpoint);
    requireThat(typeof name === 'string' && name.length > 0 && name.length <= 120 && !/[\x00-\x1f]/.test(name));
    requireThat(canonical && millis(paidThroughMilliseconds) && paidThroughMilliseconds > this.now());
    const clinicID = randomUUID(), destinationID = randomUUID(), adminToken = secret();
    this.db.prepare('INSERT INTO clinics(id,name,endpoint,destination_id,policy_version,paid_through,admin_hash) VALUES(?,?,?,?,1,?,?)')
      .run(clinicID, name, canonical, destinationID, paidThroughMilliseconds, hash(adminToken));
    return { clinicID, destinationID, policyVersion: 1, adminToken };
  }

  clinicAdmin(adminToken) {
    requireThat(typeof adminToken === 'string' && adminToken.length <= 128, 401, 'unauthorized');
    const clinic = this.db.prepare('SELECT * FROM clinics WHERE admin_hash=?').get(hash(adminToken));
    requireThat(clinic && !clinic.revoked, 401, 'unauthorized');
    return clinic;
  }

  createInvitation(adminToken) {
    const clinic = this.clinicAdmin(adminToken), now = this.now();
    requireThat(clinic.paid_through > now, 403, 'sponsorship_inactive');
    const invitationCode = secret(), expiresAtMilliseconds = Math.min(now + DAY, clinic.paid_through);
    this.db.prepare('INSERT INTO invitations(token_hash,clinic_id,expires_at) VALUES(?,?,?)')
      .run(hash(invitationCode), clinic.id, expiresAtMilliseconds);
    return { invitationCode, expiresAtMilliseconds, clinicName: clinic.name };
  }

  /** V2: proof is generated and durably stored by the phone before its first request.
   * Same invitation + installation + secret recovers the same membership for 24 hours.
   * No plaintext refresh/recovery secret or replay response is stored by the server.
   */
  redeem({ invitationCode, installationID, enrollmentSecret }) {
    requireThat(id(installationID) && typeof invitationCode === 'string' &&
      /^[A-Za-z0-9_-]{32,128}$/.test(invitationCode) && typeof enrollmentSecret === 'string' &&
      /^[A-Za-z0-9_-]{43}$/.test(enrollmentSecret));
    const now = this.now(), invitationHash = hash(invitationCode), secretHash = hash(enrollmentSecret);
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const invitation = this.db.prepare('SELECT * FROM invitations WHERE token_hash=?').get(invitationHash);
      requireThat(invitation && (invitation.redeemed || invitation.expires_at > now), 403, 'invitation_unavailable');
      const clinic = this.db.prepare('SELECT * FROM clinics WHERE id=?').get(invitation.clinic_id);
      requireThat(clinic && !clinic.revoked && clinic.paid_through > now, 403, 'sponsorship_inactive');
      let membership;
      if (invitation.redeemed) {
        membership = this.db.prepare('SELECT * FROM sponsorships WHERE enrollment_invitation_hash=?').get(invitationHash);
        requireThat(membership && !membership.revoked && membership.recovery_until > now &&
          membership.installation_id === installationID && membership.refresh_hash === secretHash,
          403, 'invitation_unavailable');
      } else {
        requireThat(invitation.expires_at > now, 403, 'invitation_unavailable');
        membership = { id: randomUUID(), installation_id: installationID };
        this.db.prepare(`INSERT INTO sponsorships(id,clinic_id,installation_id,refresh_hash,created_at,
          enrollment_invitation_hash,recovery_until) VALUES(?,?,?,?,?,?,?)`)
          .run(membership.id, clinic.id, installationID, secretHash, now, invitationHash, now + DAY);
        this.db.prepare('UPDATE invitations SET redeemed=1 WHERE token_hash=?').run(invitationHash);
        this.audit('enrollment', clinic.id);
      }
      const result = this.issue(clinic, membership, now);
      this.db.exec('COMMIT');
      return result;
    } catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }

  sponsorship(refreshToken, installationID) {
    requireThat(id(installationID) && typeof refreshToken === 'string' && refreshToken.length <= 128, 401, 'unauthorized');
    const membership = this.db.prepare('SELECT * FROM sponsorships WHERE refresh_hash=? AND installation_id=?')
      .get(hash(refreshToken), installationID);
    requireThat(membership, 401, 'unauthorized');
    return membership;
  }

  refresh({ refreshToken, installationID }) {
    const membership = this.sponsorship(refreshToken, installationID);
    const clinic = this.db.prepare('SELECT * FROM clinics WHERE id=?').get(membership.clinic_id);
    requireThat(!membership.revoked && clinic && !clinic.revoked && clinic.paid_through > this.now(), 403, 'sponsorship_inactive');
    return this.issue(clinic, membership, this.now());
  }

  disconnect({ refreshToken, installationID }) {
    const membership = this.sponsorship(refreshToken, installationID);
    this.db.prepare('UPDATE sponsorships SET revoked=1,revoked_at=? WHERE id=?').run(this.now(),membership.id);
  }

  revoke(adminToken, sponsorshipID) {
    const clinic = this.clinicAdmin(adminToken);
    const result = this.db.prepare('UPDATE sponsorships SET revoked=1,revoked_at=? WHERE id=? AND clinic_id=?').run(this.now(),sponsorshipID, clinic.id);
    requireThat(result.changes === 1, 404, 'not_found');
  }

  activate(clinicID, paidThroughMilliseconds) {
    requireThat(millis(paidThroughMilliseconds) && paidThroughMilliseconds > this.now());
    const result = this.db.prepare('UPDATE clinics SET paid_through=?,revoked=0 WHERE id=?').run(paidThroughMilliseconds, clinicID);
    requireThat(result.changes === 1, 404, 'not_found');
  }

  audit(action, clinicID) {
    this.db.prepare('INSERT INTO audit(action,clinic_id,at) VALUES(?,?,?)').run(action,clinicID,this.now());
  }

  suspendClinic(clinicID) {
    requireThat(this.db.prepare('UPDATE clinics SET revoked=1 WHERE id=?').run(clinicID).changes === 1,404,'not_found');
    this.audit('suspend',clinicID);
  }

  rotateAdmin(clinicID) {
    const adminToken = secret();
    requireThat(this.db.prepare('UPDATE clinics SET admin_hash=? WHERE id=?').run(hash(adminToken),clinicID).changes === 1,404,'not_found');
    this.audit('rotate_admin',clinicID);
    return { adminToken };
  }

  memberships(adminToken, after = '') {
    const clinic = this.clinicAdmin(adminToken);
    requireThat(typeof after === 'string' && after.length <= 128);
    const rows = this.db.prepare('SELECT id,created_at,revoked FROM sponsorships WHERE clinic_id=? AND id>? ORDER BY id LIMIT 100')
      .all(clinic.id,after);
    return { memberships: rows.map(x=>({sponsorshipID:x.id,createdAtMilliseconds:x.created_at,revoked:!!x.revoked})),
      nextCursor: rows.length === 100 ? rows.at(-1).id : null };
  }

  eraseClinic(clinicID) {
    // Explicit control-plane deletion; signed offline grants still expire on their original deadline.
    this.db.exec('BEGIN IMMEDIATE');
    try {
      this.db.prepare('DELETE FROM invitations WHERE clinic_id=?').run(clinicID);
      this.db.prepare('DELETE FROM sponsorships WHERE clinic_id=?').run(clinicID);
      this.db.prepare('DELETE FROM audit WHERE clinic_id=?').run(clinicID);
      requireThat(this.db.prepare('DELETE FROM clinics WHERE id=?').run(clinicID).changes === 1,404,'not_found');
      this.db.exec('COMMIT');
    } catch(error) { this.db.exec('ROLLBACK'); throw error; }
  }

  maintain() {
    const now=this.now();
    this.db.exec('BEGIN IMMEDIATE');
    try {
      this.db.prepare('UPDATE sponsorships SET enrollment_invitation_hash=NULL,recovery_until=NULL WHERE recovery_until<=?').run(now);
      this.db.prepare(`DELETE FROM invitations WHERE expires_at<=? AND NOT EXISTS
        (SELECT 1 FROM sponsorships WHERE enrollment_invitation_hash=invitations.token_hash AND recovery_until>?)`).run(now,now);
      this.db.prepare('DELETE FROM sponsorships WHERE (revoked=1 AND COALESCE(revoked_at,created_at)<?) OR clinic_id IN (SELECT id FROM clinics WHERE paid_through<?)')
        .run(now-30*DAY,now-90*DAY);
      this.db.prepare('DELETE FROM audit WHERE at<?').run(now-30*DAY);
      this.db.exec('COMMIT');
    } catch(error) { this.db.exec('ROLLBACK'); throw error; }
  }

  issue(clinic, membership, now) {
    // Phones can lag NTP by seconds. Backdate issuance, without relaxing native
    // verification or increasing the maximum signed lifetime or paid-through.
    const issuedAt = Math.max(0, now - 60_000);
    const claims = {
      issuer: this.issuer, audience: this.audience, installationID: membership.installation_id,
      sponsorshipID: membership.id, clinicID: clinic.id, destinationID: clinic.destination_id,
      policyVersion: clinic.policy_version, endpoint: clinic.endpoint,
      issuedAtMilliseconds: issuedAt, expiresAtMilliseconds: Math.min(issuedAt + 7 * DAY, clinic.paid_through),
    };
    const message = `v1.${this.keyID}.${Buffer.from(JSON.stringify(claims)).toString('base64url')}`;
    const signature = sign('sha256', Buffer.from(message), { key: this.key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
    return { grant: `${message}.${signature}`, clinicName: clinic.name, sponsorshipID: membership.id };
  }
}
