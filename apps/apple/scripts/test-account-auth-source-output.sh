#!/bin/bash
# LIGHT F3 regression only. Never execute the full native runner, even with PATH spies.
set -euo pipefail
if [ "$#" -ne 2 ] || { [ "$1" != baseline ] && [ "$1" != current ]; }; then
    printf 'Usage: bash test-account-auth-source-output.sh <baseline|current> <existing AS03 sandbox>\n' >&2
    exit 2
fi
mode=$1
root=$(cd -P "$(dirname "$0")/../../.." && pwd)
sandbox=$(cd -P -- "$2" && pwd)
case "$sandbox" in
    "$root/apps/apple/build/account-auth-source/"*|*/healthmd-account-sync.O0LAHV/evidence/as03-source-output-*) ;;
    *) printf 'FAIL sandbox-admission\n' >&2; exit 2;;
esac
runner="$root/apps/apple/scripts/test-account-auth-source.sh"
if [ "$mode" = baseline ]; then
    text=$(git -C "$root" show 1b8500facf49599e9f92b372cdc6adf62e3a2320:apps/apple/scripts/test-account-auth-source.sh)
else
    text=$(< "$runner")
fi
# The absolute compiler line AND EVERY subsequent stage are excluded before child execution.
# Fail closed if the known boundary moves or known heavy dispatch spellings enter the prefix.
prefix=; boundary=0
while IFS= read -r line; do
    if [ "$line" = '/usr/bin/swiftc --version' ]; then boundary=1; break; fi
    prefix="$prefix$line"$'\n'
done <<< "$text"
[ "$boundary" -eq 1 ] || { printf 'FAIL missing-compiler-boundary\n' >&2; exit 3; }
case "$prefix" in
    *swiftc*|*perl*|*'/usr/bin/'*|*'exec '*|*'eval '*|*'command '*|*with-heavy-slot*|*'cargo '*|*'node '*|*gradle*)
        printf 'FAIL unsafe-preflight-prefix\n' >&2; exit 3;;
esac
helper="$root/apps/apple/scripts/account-auth-source-output.sh"
if [ "$mode" = current ]; then
    helper_text=$(< "$helper")
    case "$helper_text" in
        *swiftc*|*perl*|*'/usr/bin/'*|*'exec '*|*'eval '*|*'command '*|*with-heavy-slot*|*'cargo '*|*'node '*|*gradle*)
            printf 'FAIL unsafe-validation-helper\n' >&2; exit 3;;
    esac
fi
# Only mutation SYSTEM commands are spied. cd/pwd/namespace/artifact decisions remain genuine.
spies='
mkdir() { printf "mutation mkdir\n" >> "$AS03_SPY_FILE"; }
rm() { printf "mutation rm\n" >> "$AS03_SPY_FILE"; }
cp() { printf "mutation cp\n" >> "$AS03_SPY_FILE"; }
mv() { printf "mutation mv\n" >> "$AS03_SPY_FILE"; }
ln() { printf "mutation ln\n" >> "$AS03_SPY_FILE"; }
install() { printf "mutation install\n" >> "$AS03_SPY_FILE"; }
touch() { printf "mutation touch\n" >> "$AS03_SPY_FILE"; }
tee() { printf "mutation tee\n" >> "$AS03_SPY_FILE"; }
'
program="$spies$prefix"$'\n''printf "compiler-boundary-fence\n" >> "$AS03_SPY_FILE"; exit 97'
negative=0; positive=0
reject() {
    local name=$1 candidate=$2 status=0 spy="$sandbox/$1.spy"
    : > "$spy"
    AS03_SPY_FILE="$spy" BASH_ENV= ENV= /bin/bash --noprofile --norc -c "$program" "$runner" "$candidate" \
        > "$sandbox/$name.stdout" 2> "$sandbox/$name.stderr" || status=$?
    local mutations fences
    mutations=$(grep -c '^mutation ' "$spy") || true
    fences=$(grep -c '^compiler-boundary-fence$' "$spy") || true
    printf 'case=%s exit=%s mutation_spy_calls=%s boundary_fence_reached=%s compiler_program_excluded=1\n' \
        "$name" "$status" "$mutations" "$fences"
    if [ "$status" -ne 2 ] || [ -s "$spy" ]; then
        printf 'FAIL %s-must-refuse-before-any-mutation\n' "$name"
        exit 1
    fi
    negative=$((negative + 1))
}
accept_helper_only() {
    local name=$1 candidate=$2 expected=$3 status=0 spy="$sandbox/$1.spy" actual
    : > "$spy"
    AS03_SPY_FILE="$spy" BASH_ENV= ENV= /bin/bash --noprofile --norc -c \
        "$spies"$'\n''source "$0"; account_auth_source_validate_output "$1" "$2"' "$helper" "$root" "$candidate" \
        > "$sandbox/$name.stdout" 2> "$sandbox/$name.stderr" || status=$?
    actual=$(< "$sandbox/$name.stdout")
    [ "$status" -eq 0 ] && [ ! -s "$spy" ] && [ "$actual" = "$expected" ] || {
        printf 'FAIL %s-helper-only-admission\n' "$name"; exit 1;
    }
    printf 'case=%s exit=0 mutation_spy_calls=0 helper_only=1\n' "$name"
    positive=$((positive + 1))
}
# All real fixture writes are tiny and INSIDE the admitted sandbox, never at rejected targets.
[ ! -e "$sandbox/nonexisting-output" ] && [ ! -L "$sandbox/nonexisting-output" ] && \
    [ ! -e "$sandbox/nonexisting.spy" ] && [ ! -L "$sandbox/nonexisting.spy" ] && \
    [ ! -e "$sandbox/positive" ] || { printf 'FAIL reused-sandbox\n' >&2; exit 3; }
reject nonexisting "$sandbox/nonexisting-output"
[ ! -e "$sandbox/nonexisting-output" ] && [ ! -L "$sandbox/nonexisting-output" ] || exit 3
reject outside-existing "$root/apps/apple/scripts"
mkdir "$sandbox/compiler-artifact" "$sandbox/receipt-artifact" "$sandbox/partial-receipt" \
    "$sandbox/cache-artifact" "$sandbox/hidden-artifact" "$sandbox/guard-symlink" \
    "$sandbox/positive" "$sandbox/positive-guard"
printf 'compiler-sentinel\n' > "$sandbox/compiler-artifact/compiler.log"
printf 'receipt-sentinel\n' > "$sandbox/receipt-artifact/source-input-sha256.log"
printf 'status-sentinel\n' > "$sandbox/partial-receipt/source-status.log"
printf 'hidden-sentinel\n' > "$sandbox/hidden-artifact/.partial"
printf 'guard-sentinel\n' > "$sandbox/positive-guard/guard.log"
ln -s "$root/apps/apple/scripts" "$sandbox/escape"
ln -s "$root/apps/apple/scripts" "$sandbox/cache-artifact/module-cache"
ln -s "$sandbox/positive-guard/guard.log" "$sandbox/guard-symlink/guard.log"
lf_path="$sandbox/lf-name"$'\n'
mkdir "$lf_path"
ln -s "$lf_path" "$sandbox/lf-link"
reject symlink-escape "$sandbox/escape"
reject reused-compiler "$sandbox/compiler-artifact"
reject reused-receipt "$sandbox/receipt-artifact"
reject partial-receipt "$sandbox/partial-receipt"
reject cache-symlink "$sandbox/cache-artifact"
reject hidden-artifact "$sandbox/hidden-artifact"
reject guard-symlink "$sandbox/guard-symlink"
reject lf-name "$lf_path"
reject symlink-to-lf "$sandbox/lf-link"
[ ! -e "$sandbox/lf-name" ] && [ ! -L "$sandbox/lf-name" ] || exit 3
[ "$(< "$sandbox/compiler-artifact/compiler.log")" = compiler-sentinel ] && \
    [ "$(< "$sandbox/receipt-artifact/source-input-sha256.log")" = receipt-sentinel ] && \
    [ "$(< "$sandbox/partial-receipt/source-status.log")" = status-sentinel ] && \
    [ "$(< "$sandbox/hidden-artifact/.partial")" = hidden-sentinel ] || exit 3
# NO accepted argument is passed to the native runner's prefix/full program.
accept_helper_only physical "$sandbox/positive" "$sandbox/positive"
accept_helper_only outer-guard-log "$sandbox/positive-guard" "$sandbox/positive-guard"
case "$sandbox" in
    /private/var/*) accept_helper_only var-alias "${sandbox#/private}/positive" "$sandbox/positive";;
esac
[ "$(< "$sandbox/positive-guard/guard.log")" = guard-sentinel ] || exit 3
printf 'PASS output-admission-light rejected=%s helper-positive=%s compiler_calls=0 (compiler suffix never supplied to child)\n' \
    "$negative" "$positive"
