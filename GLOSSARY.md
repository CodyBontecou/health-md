# Health.md personal data

Health.md brings health, location history, and screen time into one personal data product. These terms describe the selected product scope; individual acquisition capabilities still depend on platform support.

## Language

**Personal data**:
The health, location, and device usage information that a person chooses to collect, inspect, or export through Health.md.

**Screen time**:
The user-facing name for device and application usage, including available usage summaries, foreground app sessions, device activity states, and desktop window titles.
_Avoid_: Browsing history as a synonym

**Foreground app session**:
An observed interval during which a particular application is in the foreground on one device.
_Avoid_: Usage aggregate

**Usage aggregate**:
A source-provided usage total for an application or device over a specified time bucket.
_Avoid_: Foreground app session, exact activity timeline

**Window title observation**:
The title exposed by the operating system for a foreground desktop window at an observed time.
_Avoid_: Page visit, document contents

**Location point**:
A location observation with its source timestamp, coordinates, and available accuracy information.
_Avoid_: Snapped route point

**Visit**:
A detected or manually recorded stay at a location, with the source and certainty of its arrival and departure retained.
_Avoid_: Watch visit counter

**Saved place**:
A person's named or corrected location annotation used to recognize and describe visits.
_Avoid_: Location observation

**Recording session**:
A location recording interval explicitly started by the person.
_Avoid_: Inferred outing

**Inferred outing**:
A grouping of location observations produced by an inference rule rather than an explicit recording action.
_Avoid_: Recording session

**Coverage**:
The periods and kinds of information that a source can actually account for, including gaps, unavailable detail, and retention limits.
_Avoid_: Zero usage when observation is unavailable

**Combined export**:
One requested deliverable containing selected personal data domains and their separate source and coverage information.
_Avoid_: Complete backup unless all required information is included

**Cloud destination**:
An optional Health.md service that stores the exports a person explicitly sends to it.
_Avoid_: Automatic device backup

**Retained export**:
An export successfully stored by Health.md Cloud, with its original selection, source and coverage information.
_Avoid_: Live device data, complete lifetime history

**Hosted snapshot**:
A retained view of specified source data, with the covered period and available detail identified.
_Avoid_: Simultaneous snapshot of every device

**Agent connection**:
A person's authorized link between Health.md Cloud and an identified external agent service.
_Avoid_: Permission for every agent or every data domain

**Access grant**:
The specific information, recipient and duration a person authorizes for a connection, including whether selected future uploads are available.
_Avoid_: Upload permission

**Upload enrollment**:
A person's authorization for a specific source device to send selected exports to their Cloud account.
_Avoid_: Agent connection, permission to read stored exports

**Freshness**:
How recently the available source information was captured, shown separately from when its export was uploaded.
_Avoid_: Live data when only an old export is available

**Portability export**:
A deliverable containing the person's selected or complete retained Cloud data, with coverage and expired information identified.
_Avoid_: Account recovery

**Hosted deletion receipt**:
A status record identifying what hosted information has been blocked or removed and what cleanup or backup expiry remains pending.
_Avoid_: Proof that an external agent deleted its own copies
