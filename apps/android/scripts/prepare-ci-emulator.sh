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
recovered=false
home_started=false
setup_started=false
for attempt in $(seq 1 30); do
    if [[ "$(adb_ci shell getprop sys.boot_completed | tr -d '\r')" != 1 ]]; then
        sleep 1
        continue
    fi
    focus="$(adb_ci shell dumpsys -t 2 window | tr -d '\r' | sed -n '/mCurrentFocus=/p')"
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
    home="$(adb_ci shell cmd package resolve-activity --brief \
        -a android.intent.action.MAIN -c android.intent.category.HOME | tr -d '\r' | tail -n 1)"
    case "$home" in
        com.google.android.googlesdksetup/.DefaultActivity|com.google.android.googlesdksetup/com.google.android.googlesdksetup.DefaultActivity)
            # A fresh Google APIs image initially resolves HOME to SDK setup.
            # Let that known activity finish provisioning and retire itself;
            # do not disable setup packages or force completion settings.
            if [[ "$setup_started" == false ]]; then
                echo 'Initializing the hosted image SDK setup activity once.'
                if setup_output="$(adb_ci shell am start -W -n "$home" 2>&1)"; then
                    echo "$setup_output"
                else
                    echo "$setup_output" >&2
                    # Setup can retire itself between HOME resolution and launch.
                    # Admit only that exact missing-activity transition to the
                    # known launcher; all other launch failures remain fatal.
                    if [[ "$setup_output" != *'Error type 3'* || "$setup_output" != *'does not exist.'* ]]; then
                        exit 1
                    fi
                    home_after="$(adb_ci shell cmd package resolve-activity --brief \
                        -a android.intent.action.MAIN -c android.intent.category.HOME | tr -d '\r' | tail -n 1)"
                    case "$home_after" in
                        "$launcher/"*) echo 'SDK setup retired; waiting for the known HOME window.' ;;
                        *) echo "SDK setup launch failed without a known HOME transition: $home_after" >&2; exit 1 ;;
                    esac
                fi
                setup_started=true
            fi
            sleep 1
            continue
            ;;
        "$launcher/"*) ;;
        *) echo "Unexpected HOME component on pinned CI image: $home" >&2; exit 1 ;;
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
