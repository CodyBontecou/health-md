#!/usr/bin/env bash
# check-apns-scheduling-preflight.sh — Guard production APNs scheduled exports.
#
# Usage: scripts/check-apns-scheduling-preflight.sh
#
# Fails release if the iOS production APNs entitlement, silent-push background
# mode, background-task identifier, or source bridge contract for server-driven
# scheduled exports is accidentally removed or pointed at a non-production APNs
# environment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

IOS_ENTITLEMENTS="${APNS_IOS_ENTITLEMENTS:-${REPO_ROOT}/HealthMd/HealthMd.entitlements}"
IOS_INFO_PLIST="${APNS_IOS_INFO_PLIST:-${REPO_ROOT}/HealthMd/Info.plist}"
IOS_SCHEDULING_MANAGER="${APNS_IOS_SCHEDULING_MANAGER:-${REPO_ROOT}/HealthMd/iOS/SchedulingManager.swift}"
IOS_APP_DELEGATE="${APNS_IOS_APP_DELEGATE:-${REPO_ROOT}/HealthMd/iOS/HealthMdApp.swift}"
PUSH_REGISTRATION_MANAGER="${APNS_PUSH_REGISTRATION_MANAGER:-${REPO_ROOT}/HealthMd/Shared/Managers/PushRegistrationManager.swift}"
AUTOMATION_CONTRACT="${APNS_AUTOMATION_CONTRACT:-${REPO_ROOT}/HealthMd/Shared/ExportAutomationKit/ExportAutomationScheduling.swift}"

FAILURES=0

fail() {
  local message="$1"
  echo "::error::${message}"
  echo "FAIL: ${message}" >&2
  FAILURES=$((FAILURES + 1))
}

pass() {
  echo "PASS: $1"
}

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    fail "Required file not found: ${path}"
    return 1
  fi
  pass "Found ${path#${REPO_ROOT}/}"
}

plist_value() {
  local plist="$1"
  local key_path="$2"
  /usr/libexec/PlistBuddy -c "Print ${key_path}" "${plist}" 2>/dev/null || true
}

source_contains() {
  local path="$1"
  local snippet="$2"
  local label="$3"
  if grep -Fq "${snippet}" "${path}"; then
    pass "${label}"
  else
    fail "${path#${REPO_ROOT}/} is missing required snippet: ${snippet}"
  fi
}

extract_background_task_identifier() {
  python3 - "$IOS_SCHEDULING_MANAGER" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
if not path.exists():
    sys.exit(0)
source = path.read_text()
match = re.search(r'static\s+let\s+backgroundTaskIdentifier\s*=\s*"([^"]+)"', source)
if match:
    print(match.group(1))
PY
}

echo "━━━  APNs Scheduling Preflight  ━━━"
echo "Repo: ${REPO_ROOT}"
echo ""

require_file "${IOS_ENTITLEMENTS}" || true
require_file "${IOS_INFO_PLIST}" || true
require_file "${IOS_SCHEDULING_MANAGER}" || true
require_file "${IOS_APP_DELEGATE}" || true
require_file "${PUSH_REGISTRATION_MANAGER}" || true
require_file "${AUTOMATION_CONTRACT}" || true

echo ""
echo "Checking production APNs entitlement..."
APS_ENVIRONMENT="$(plist_value "${IOS_ENTITLEMENTS}" ":aps-environment")"
if [[ "${APS_ENVIRONMENT}" == "production" ]]; then
  pass "HealthMd.entitlements aps-environment=production"
else
  fail "HealthMd/HealthMd.entitlements must set aps-environment to production (found: ${APS_ENVIRONMENT:-missing})"
fi

echo ""
echo "Checking silent push and background task plist configuration..."
BACKGROUND_MODES="$(plist_value "${IOS_INFO_PLIST}" ":UIBackgroundModes")"
if printf '%s\n' "${BACKGROUND_MODES}" | grep -Fq "remote-notification"; then
  pass "Info.plist UIBackgroundModes contains remote-notification"
else
  fail "HealthMd/Info.plist UIBackgroundModes must include remote-notification for silent scheduled export pushes"
fi

BACKGROUND_TASK_IDENTIFIER="$(extract_background_task_identifier)"
if [[ -z "${BACKGROUND_TASK_IDENTIFIER}" ]]; then
  fail "Could not extract SchedulingManager.backgroundTaskIdentifier"
else
  PERMITTED_IDENTIFIERS="$(plist_value "${IOS_INFO_PLIST}" ":BGTaskSchedulerPermittedIdentifiers")"
  if printf '%s\n' "${PERMITTED_IDENTIFIERS}" | grep -Fq "${BACKGROUND_TASK_IDENTIFIER}"; then
    pass "Info.plist permits BG task ${BACKGROUND_TASK_IDENTIFIER}"
  else
    fail "HealthMd/Info.plist BGTaskSchedulerPermittedIdentifiers must include ${BACKGROUND_TASK_IDENTIFIER}"
  fi
fi

echo ""
echo "Checking iOS scheduling bridge wiring..."
source_contains "${IOS_SCHEDULING_MANAGER}" "await PushRegistrationManager.shared.registerForRemoteNotificationsIfNeeded()" "SchedulingManager registers for remote notifications when scheduling is enabled"
source_contains "${IOS_SCHEDULING_MANAGER}" "PushRegistrationManager.shared.syncSchedule(schedule)" "SchedulingManager mirrors schedule changes to the worker"
source_contains "${IOS_APP_DELEGATE}" "didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data" "AppDelegate receives APNs tokens"
source_contains "${IOS_APP_DELEGATE}" "PushRegistrationManager.shared.submitDeviceToken(deviceToken)" "AppDelegate forwards APNs tokens to PushRegistrationManager"
source_contains "${IOS_APP_DELEGATE}" "didReceiveRemoteNotification userInfo: [AnyHashable: Any]" "AppDelegate handles silent remote notifications"
source_contains "${IOS_APP_DELEGATE}" "fetchCompletionHandler completionHandler" "Silent remote notification handler includes fetch completion"
source_contains "${IOS_APP_DELEGATE}" "userInfo[\"type\"] as? String == \"scheduled-export\"" "AppDelegate gates silent pushes to scheduled-export payloads"
source_contains "${IOS_APP_DELEGATE}" "performSilentPushExport(fireDate: fireDate)" "AppDelegate invokes scheduled export from silent push"

echo ""
echo "Checking PushRegistrationManager worker contract..."
source_contains "${PUSH_REGISTRATION_MANAGER}" "URL(string: \"https://healthmd-receipt-verifier.costream.workers.dev\")" "PushRegistrationManager uses the production worker endpoint"
source_contains "${PUSH_REGISTRATION_MANAGER}" "RemoteScheduleDeviceRegistrationPayload" "PushRegistrationManager builds the generic device registration payload"
source_contains "${PUSH_REGISTRATION_MANAGER}" "RemoteScheduleUpsertPayload" "PushRegistrationManager builds the generic schedule upsert payload"
source_contains "${PUSH_REGISTRATION_MANAGER}" "remoteClient.registerDevice(body)" "PushRegistrationManager registers APNs device tokens"
source_contains "${PUSH_REGISTRATION_MANAGER}" "remoteClient.upsertSchedule(body)" "PushRegistrationManager upserts schedules"
source_contains "${PUSH_REGISTRATION_MANAGER}" "RemoteSchedulePayload(schedule: schedule.automationSchedule(timeZone: timeZone))" "PushRegistrationManager bridges Health.md schedules to the generic worker payload"

source_contains "${AUTOMATION_CONTRACT}" "struct RemoteScheduleDeviceRegistrationPayload" "Generic contract defines device registration payload"
source_contains "${AUTOMATION_CONTRACT}" "var userId: String" "Worker payload includes userId"
source_contains "${AUTOMATION_CONTRACT}" "var platform: String" "Worker payload includes platform"
source_contains "${AUTOMATION_CONTRACT}" "var apnsToken: String" "Worker payload includes APNs token"
source_contains "${AUTOMATION_CONTRACT}" "var bundleId: String" "Worker payload includes bundleId"
source_contains "${AUTOMATION_CONTRACT}" "var appVersion: String?" "Worker payload supports app version metadata"
source_contains "${AUTOMATION_CONTRACT}" "var appBuild: String?" "Worker payload supports app build metadata"
source_contains "${AUTOMATION_CONTRACT}" "struct RemoteScheduleUpsertPayload" "Generic contract defines schedule upsert payload"
source_contains "${AUTOMATION_CONTRACT}" "var timezone: String" "Schedule payload includes timezone"
source_contains "${AUTOMATION_CONTRACT}" "var isEnabled: Bool" "Schedule payload includes enabled state"
source_contains "${AUTOMATION_CONTRACT}" "var frequency: AutomationScheduleFrequency" "Schedule payload includes lowercase frequency"
source_contains "${AUTOMATION_CONTRACT}" "var hour: Int" "Schedule payload includes hour"
source_contains "${AUTOMATION_CONTRACT}" "var minute: Int" "Schedule payload includes minute"
source_contains "${AUTOMATION_CONTRACT}" "var weekday: Int?" "Weekly schedule payload includes optional weekday"
source_contains "${AUTOMATION_CONTRACT}" "case daily = \"daily\"" "Daily frequency maps to worker schema"
source_contains "${AUTOMATION_CONTRACT}" "case weekly = \"weekly\"" "Weekly frequency maps to worker schema"
source_contains "${AUTOMATION_CONTRACT}" "struct RemoteScheduledExportAPNsPayload" "Generic contract defines silent APNs payload"
source_contains "${AUTOMATION_CONTRACT}" "case contentAvailable = \"content-available\"" "APNs payload sets content-available"
source_contains "${AUTOMATION_CONTRACT}" "static let scheduledExportPushType = \"scheduled-export\"" "APNs payload type is scheduled-export"

echo ""
if [[ "${FAILURES}" -gt 0 ]]; then
  echo "::error::APNs scheduling preflight failed with ${FAILURES} issue(s)"
  echo "FAIL: APNs scheduling preflight found ${FAILURES} issue(s)." >&2
  exit 1
fi

pass "APNs scheduling preflight passed."
exit 0
