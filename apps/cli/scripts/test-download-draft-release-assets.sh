#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
downloader="$script_dir/download-draft-release-assets.sh"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
mkdir -p "$temporary/bin" "$temporary/assets"

cat > "$temporary/bin/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
endpoint=""
for argument in "$@"; do
  if [[ "$argument" == repos/* ]]; then
    endpoint="$argument"
  fi
done
case "$endpoint" in
  repos/example/project/releases/42)
    cat "$FAKE_GH_RELEASE"
    ;;
  repos/example/project/releases/assets/*)
    asset_id="${endpoint##*/}"
    if [[ "${FAKE_GH_SKIP_ASSET:-}" == "$asset_id" ]]; then
      exit 0
    fi
    cat "$FAKE_GH_ASSETS/$asset_id"
    ;;
  *)
    echo "unexpected fake gh endpoint: $endpoint" >&2
    exit 70
    ;;
esac
FAKE_GH
chmod +x "$temporary/bin/gh"

printf 'qualified asset bytes\n' > "$temporary/assets/100"
digest="$(sha256sum "$temporary/assets/100" | cut -d ' ' -f 1)"
tag='healthmd-cli/v0.1.0-alpha.3'
sha='0123456789abcdef0123456789abcdef01234567'

jq -n \
  --arg tag "$tag" \
  --arg sha "$sha" \
  --arg digest "sha256:$digest" \
  '{
    id: 42,
    draft: true,
    tag_name: $tag,
    target_commitish: $sha,
    assets: [{
      id: 100,
      name: "asset.txt",
      digest: $digest,
      state: "uploaded"
    }]
  }' > "$temporary/valid.json"

invoke() {
  local release="$1"
  local output="$2"
  rm -rf "$output"
  PATH="$temporary/bin:$PATH" \
    FAKE_GH_RELEASE="$release" \
    FAKE_GH_ASSETS="$temporary/assets" \
    bash "$downloader" example/project 42 "$tag" "$sha" "$output"
}

expect_failure() {
  local label="$1"
  local release="$2"
  local output="$temporary/output-$label"
  if invoke "$release" "$output" >/dev/null 2>&1; then
    echo "expected downloader failure: $label" >&2
    exit 1
  fi
}

invoke "$temporary/valid.json" "$temporary/output-valid"
cmp "$temporary/assets/100" "$temporary/output-valid/asset.txt"

jq '.draft = false' "$temporary/valid.json" > "$temporary/public.json"
expect_failure public-release "$temporary/public.json"

jq '.tag_name = "healthmd-cli/v9.9.9"' "$temporary/valid.json" > "$temporary/wrong-tag.json"
expect_failure wrong-tag "$temporary/wrong-tag.json"

jq '.target_commitish = "ffffffffffffffffffffffffffffffffffffffff"' \
  "$temporary/valid.json" > "$temporary/wrong-sha.json"
expect_failure wrong-sha "$temporary/wrong-sha.json"

jq '.assets[0].digest = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' \
  "$temporary/valid.json" > "$temporary/wrong-digest.json"
expect_failure wrong-digest "$temporary/wrong-digest.json"

cp "$temporary/assets/100" "$temporary/assets/101"
jq '.assets += [(.assets[0] | .id = 101)]' \
  "$temporary/valid.json" > "$temporary/duplicate-name.json"
expect_failure duplicate-name "$temporary/duplicate-name.json"

if PATH="$temporary/bin:$PATH" \
  FAKE_GH_RELEASE="$temporary/valid.json" \
  FAKE_GH_ASSETS="$temporary/assets" \
  FAKE_GH_SKIP_ASSET=100 \
  bash "$downloader" example/project 42 "$tag" "$sha" "$temporary/output-incomplete" \
  >/dev/null 2>&1; then
  echo 'expected downloader failure: incomplete download' >&2
  exit 1
fi

echo 'draft release asset downloader tests passed'
