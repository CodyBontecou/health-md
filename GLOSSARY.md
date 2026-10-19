# Health.md

Domain language for Health.md. The initial terms describe the explicitly opted-in Cloud archive, not complete device-health coverage.

## Language

### Cloud archives

**Retained export**:
A user-selected export successfully accepted into the user's Cloud archive. It establishes receipt of that export, not that the user's entire device health history was uploaded.
_Avoid_: Complete health backup, phone backup

**Cloud archive**:
A user's collection of retained exports, limited to exports successfully received by Cloud. It is the dataset covered by Cloud's retention, access and recovery policies.
_Avoid_: Complete device backup, live health mirror

**Service-readable Cloud archive**:
A Cloud archive whose contents Health.md can make readable for the account owner's authorized uses. It is not an archive whose health contents are cryptographically hidden from Health.md.
_Avoid_: Zero-knowledge archive, provider-blind archive

**Unbacked Cloud archive**:
A Cloud archive without an independently recoverable set of retained exports, account state and historical decryption authority. Loss of the service's data or decryption authority may permanently destroy access to the archive.
_Avoid_: Recoverable health backup, durable phone backup

**Full archive access**:
Permission to read every original field and byte in a user's retained exports, including retained revisions, source archives, provider data, free text and embedded binary. The permission's time coverage determines whether future received exports are included; it never includes unexported device data or another person's archive.
_Avoid_: Full device access, complete health history

**Unattended archive access**:
Authorized access to retained exports that does not require the user's phone, laptop or browser to be online. It does not imply unattended capture of new device health data.
_Avoid_: Unattended phone capture, live device sync

**Individual Cloud account**:
A Cloud account owned by one adult for that person's own retained exports. It is not a shared family, organization or clinician-managed account.
_Avoid_: Family workspace, clinical practice account

### Cloud enrollment and storage

**Cloud export target**:
An explicitly selected Health.md destination for sending chosen exports to the user's Individual Cloud account. It is distinct from authorizing agent reads or capturing additional device data.
_Avoid_: Automatic health sync, agent read connection

**Cloud storage plan**:
An offer defining an Individual Cloud account's storage allowance and payment terms. It is distinct from the native app's purchase entitlement and from authorization to read health data.
_Avoid_: Lifetime app unlock, agent permission

**Cloud storage allowance**:
The archive capacity assigned through a Cloud storage plan or a qualifying included benefit. It is distinct from the account's actual retained usage, upload size limits and Health.md's physical storage capacity.
_Avoid_: Unlimited storage, single-upload limit

**Cloud subscription**:
A recurring purchase of a Cloud storage plan for an Individual Cloud account. It is distinct from a lifetime native app purchase, health-data capture consent and an Agent connection.
_Avoid_: Lifetime Cloud unlock, agent authorization

**Lifetime-linked Cloud allowance**:
A Cloud storage allowance included with qualifying lifetime native app rights without a recurring Cloud subscription. It is distinct from a guarantee of lifetime hosting or archive recovery.
_Avoid_: Lifetime Cloud hosting, lifetime health backup

**Archive-retirement grace**:
A post-subscription period in which retained exports await warned retirement unless the owner reestablishes the required Cloud storage entitlement. It is not ordinary age expiry of exports with valid storage entitlement or a promise of archive recovery.
_Avoid_: Backup window, lifetime free retention

**Archive retirement**:
The warned removal of a Cloud archive and its access/decryption authority after the required storage entitlement remains absent. It is distinct from deleting the owner's account, expiry of permitted provider copies or recall of data already delivered to agents.
_Avoid_: Account deletion, every-copy deletion

### Agent access

**Agent connection**:
An account owner's authorization for an agent client, provider account or runtime to read that owner's Cloud archive within its approved scope. It may serve several Bots or services when their credentials are shared; it is not a separate authorization for each network session.
_Avoid_: Bot-isolated permission, MCP network connection

**Shared agent connection**:
An Agent connection available to multiple Bots or services within an owner-approved credential-sharing boundary. Its scope and revocation apply to the shared connection, not independently to each Bot using it.
_Avoid_: Individual Bot permission, shared tenant authority

**Bot isolation**:
Separation of Cloud archive access authority between individual Bots. Revoking one Bot's authority leaves other authorized Bots usable without letting the revoked Bot borrow their authority.
_Avoid_: Separate Bot labels, shared-account isolation

### Cloud recovery

**Account recovery**:
Regaining authorized control of an Individual Cloud account after losing the ability to sign in. It does not by itself establish that the account's retained exports or decryption authority are recoverable.
_Avoid_: Archive recovery, archive-key recovery

**Archive recovery**:
Restoring a user's retained exports after service data loss so that authorized users can read them again. It does not cover unuploaded device history or restore permission to read deliberately deleted exports.
_Avoid_: Phone recovery, account recovery

**Archive-key recovery**:
Restoring the decryption authority needed to make encrypted retained exports readable after that authority becomes unavailable. It is distinct from restoring the exports themselves or establishing an account owner's identity.
_Avoid_: Account recovery, password reset
