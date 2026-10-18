#!/usr/bin/env bash
# Admit only the disposable hosted AVD, with a responsive HOME window.
set -euo pipefail

if [[ $# != 0 || "${GITHUB_ACTIONS:-}" != true ]]; then
    echo 'Emulator recovery is restricted to the owned GitHub Actions AVD.' >&2
    exit 2
fi

adb_ci() {
    timeout 10 adb -s emulator-5554 "$@"
}

if [[ "$(adb_ci shell getprop ro.boot.qemu | tr -d '\r')" != 1 ]]; then
    echo 'Refusing emulator recovery on a non-emulator target.' >&2
    exit 1
fi

launcher=com.google.android.apps.nexuslauncher
home="$(adb_ci shell cmd package resolve-activity --brief \
    -a android.intent.action.MAIN -c android.intent.category.HOME | tr -d '\r' | tail -n 1)"
case "$home" in
    "$launcher/"*) ;;
    *) echo "Unexpected HOME component on pinned CI image: $home" >&2; exit 1 ;;
esac

recovered=false
home_started=false
for attempt in $(seq 1 30); do
    if [[ "$(adb_ci shell getprop sys.boot_completed | tr -d '\r')" != 1 ]]; then
        sleep 1
        continue
    fi
    focus="$(adb_ci shell dumpsys window windows | tr -d '\r' | sed -n '/mCurrentFocus=/p')"
    echo "Hosted AVD focus: $focus"
    case "$focus" in
        *"Application Not Responding: $launcher}"*)
            if [[ "$recovered" == false ]]; then
                # Kill only the known external launcher. Do not dismiss arbitrary
                # dialogs, suppress ANRs, or recover Health.md/test process failures.
                adb_ci shell am force-stop "$launcher"
                echo 'Recovered the external launcher ANR; restarting HOME once.'
                recovered=true
                home_started=false
            fi
            ;;
        *'Application Not Responding:'*)
            echo 'Unexpected ANR; refusing to hide an application or platform failure.' >&2
            exit 1
            ;;
    esac
    if [[ "$home_started" == false ]]; then
        adb_ci shell am start -W -n "$home"
        home_started=true
    else
        case "$focus" in
            *" u0 $launcher/"*'}')
                echo 'Hosted emulator HOME is ready; native input admission tests remain mandatory.'
                exit 0
                ;;
        esac
    fi
    sleep 1
done

echo 'Hosted emulator did not regain a ready HOME window within the bounded setup.' >&2
exit 1
