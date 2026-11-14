"""AS01 design predicates / symbolic vectors only; NOT runtime authentication.

No HTTP handlers, external dependencies, secret generation, persistent adapters or
OS registration. Downstream implementations must independently consume the vectors
and prove parser, crypto, transaction, lifecycle and mobile behavior at their seam.
"""

import base64
from collections import Counter
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import re
import unittest
from urllib.parse import urlsplit

from build_reply_header_vectors import build_vectors as build_reply_header_vectors
from reply_headers import (MAX_NAME_BYTES, MAX_PAIR_BYTES, MAX_PAIRS, MAX_VALUE_BYTES,
                           parse_reply_headers)

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def load(path):
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object)


POLICY = load(HERE / "source-policy.json")
FIELDS = load(HERE / "field-scope.json")
CAPABILITIES = load(HERE / "capability-classifications.json")
VECTORS = load(HERE / "fixtures/security-vectors.json")
REGISTRY = POLICY["environments"]["synthetic"]
ROUTES = {row["id"]: row for row in POLICY["routes"]}
# Intentionally non-random test values: these are never valid production secrets.
VALUES = {
    "callback": REGISTRY["clients"][0]["callback"],
    "issuer": REGISTRY["issuer"],
    "code": "hmd_acode_" + "A" * 43,
    "refresh": "hmd_nrf_" + "A" * 43,
    "state": "B" * 42 + "A",
}


def base64url32(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_-]{43}", value):
        return False
    decoded = base64.urlsafe_b64decode(value + "=")
    return len(decoded) == 32 and base64.urlsafe_b64encode(decoded).decode().rstrip("=") == value


def callback_predicate(uri, context):
    """Design oracle for RAW callback bytes, not a native callback handler."""
    registry = POLICY["environments"].get(context["environment"])
    if not registry or not context["pending"] or not context["generation_matches"]:
        return "deny"
    client = next((c for c in registry["clients"] if c["client_id"] == context["client_id"]), None)
    if not client or len(uri.encode("utf-8")) > POLICY["bounds"]["callback_uri_bytes"]:
        return "deny"
    if "#" in uri or any(ord(ch) < 32 or ord(ch) == 127 for ch in uri):
        return "deny"
    raw_base, separator, query = uri.partition("?")
    if raw_base != client["callback"] or not separator or "%" in query:
        return "deny"
    pairs = [part.split("=", 1) for part in query.split("&")]
    if any(len(pair) != 2 for pair in pairs):
        return "deny"
    params = dict(pairs)
    if len(params) != len(pairs) or params.get("state") != VALUES["state"] or params.get("iss") != registry["issuer"]:
        return "deny"
    if set(params) == set(POLICY["callback_error_keys"]):
        return "accept_denial" if params["error"] == "access_denied" else "deny"
    if set(params) != set(POLICY["callback_success_keys"]):
        return "deny"
    code = params["code"]
    return "accept_code" if code.startswith("hmd_acode_") and base64url32(code[10:]) else "deny"


def authorization_predicate(params):
    if set(params) != set(POLICY["authorization_query_keys"]) or any(type(v) is not str for v in params.values()):
        return False
    client = next((c for c in REGISTRY["clients"] if c["client_id"] == params["client_id"]), None)
    scopes = params["scope"].split(" ")
    return bool(
        client and params["redirect_uri"] == client["callback"]
        and params["response_type"] == "code" and params["code_challenge_method"] == "S256"
        and params["audience"] == REGISTRY["audience"]
        and base64url32(params["state"]) and base64url32(params["code_challenge"])
        and scopes == sorted(set(scopes)) and set(scopes) <= set(POLICY["scopes"])
        and ("config:profiles:write" not in scopes or "config:profiles:read" in scopes)
    )


def default_principal():
    return {
        "kind": "native_access", "issuer": REGISTRY["issuer"], "environment": "synthetic",
        "audience": REGISTRY["audience"], "client_id": "synthetic-apple-ios",
        "account_id": "synthetic-account-a", "session_id": "synthetic-session-a",
        "account_active": True, "revoked": False, "expires_at": 400,
        "scopes": list(POLICY["scopes"]),
    }


def default_request(route):
    return {
        "method": route["method"], "path": route["path"], "query": "",
        "environment": "synthetic", "service_profile": "account", "auth_enabled": True,
        "sync_enabled": True, "config_opt_in": True, "privacy_policy_present": True,
        "target_account": "synthetic-account-a", "target_session": "synthetic-session-a",
        "origin": REGISTRY["issuer"], "csrf_verified": True,
        "recent_reauthentication": True, "mixed_credentials": False,
    }


def resource_predicate(route, principal, request):
    """Symbolic resource authority. Does not validate/parse real credentials."""
    registry = POLICY["environments"].get(request["environment"])
    if not registry or not request["auth_enabled"] or request["service_profile"] not in POLICY["new_route_service_profiles"]:
        return False
    if request["method"] != route["method"] or request["path"] != route["path"] or request["query"] or request["mixed_credentials"]:
        return False
    if principal["kind"] not in route["credential_kinds"]:
        return False
    if route.get("public_reference_only") and principal["kind"] == "none":
        return True  # Consent page reference, NOT credential/resource issuance.
    if not principal["account_active"] or principal["revoked"] or principal["expires_at"] <= 100:
        return False
    if request["target_account"] != principal["account_id"]:
        return False
    if principal["kind"] == "browser_session":
        if request["origin"] != registry["issuer"] or (route.get("browser_csrf") and not request["csrf_verified"]):
            return False
        if route.get("browser_other_reauthentication") and request["target_session"] != principal["session_id"] and not request["recent_reauthentication"]:
            return False
    else:
        if principal["issuer"] != registry["issuer"] or principal["environment"] != request["environment"] or principal["audience"] != registry["audience"]:
            return False
        if principal["client_id"] not in {c["client_id"] for c in registry["clients"]}:
            return False
        scopes = set(principal["scopes"])
        if not scopes <= set(POLICY["scopes"]):
            return False
        if principal["kind"] == "native_access" and not set(route["native_scopes"]) <= scopes:
            return False
        if route.get("native_target") == "self" and request["target_session"] != principal["session_id"]:
            return False
    if route["gate"] == "profile_sync" and not all(request[k] for k in ("sync_enabled", "config_opt_in", "privacy_policy_present")):
        return False
    return True


class SymbolicFamily:
    """Abstract transition oracle: symbolic labels only, no issuance/DB adapter."""

    def __init__(self):
        self.code_used = False
        self.issued = False
        self.active = False
        self.account_active = True
        self.current = "parent"
        self.spent = set()
        self.generation_matches = True

    def step(self, step):
        op = step["op"]
        if op == "exchange":
            if self.code_used or not self.account_active:
                return "invalid_grant"
            self.code_used = self.issued = self.active = True
            return "issued" if step.get("verified", True) else "verification_pending_no_secret"
        if op == "refresh":
            if not self.issued or not self.active or not self.account_active or not step.get("installation_matches", True) or step.get("scope_expansion", False):
                return "invalid_grant"
            token = step["token"]
            if token in self.spent:
                self.active = False
                return "reuse_family_revoked"
            if token != self.current:
                return "invalid_grant"
            self.spent.add(token)
            self.current = "child"
            return "rotated" if step.get("verified", True) else "verification_pending_no_secret"
        if op == "access":
            return "allow" if self.issued and self.active and self.account_active else "deny"
        if op == "revoke":
            self.active = False
            return "revoked" if step.get("verified", True) else "revocation_pending"
        if op == "disable_account":
            self.account_active = False
            return "disabled"
        if op == "switch_generation":
            self.generation_matches = False
            return "local_signed_out_remote_pending"
        if op == "apply_response":
            return "allow" if self.generation_matches else "deny"
        raise AssertionError("unknown symbolic operation")


def profile_guard(operation, state):
    if not state["mapping_verified"] or not state["foreign_provenance_verified"]:
        return False
    if operation == "publish":
        return not state["configuration_protected"]
    if operation != "execute":
        return False
    # The candidate being executed must be the accepted snapshot. Fetched
    # metadata does not revoke an unchanged already-accepted local snapshot.
    if state.get("requested_snapshot", "fetched") == "accepted":
        requested_revision, requested_hash = state["accepted_revision"], state["accepted_hash"]
    else:
        requested_revision, requested_hash = state["fetched_revision"], state["fetched_hash"]
    return bool(
        requested_revision == state["accepted_revision"] and requested_hash == state["accepted_hash"]
        and not state["import_blocked"] and state["binding_verified"] and state["local_execution_grants"]
    )


class SourceContractTests(unittest.TestCase):
    def test_registration_is_synthetic_and_activation_closed(self):
        self.assertFalse(POLICY["activation_default"])
        self.assertFalse(POLICY["profile_sync_default"])
        self.assertIsNone(POLICY["live_approval"])
        self.assertIsNone(FIELDS["real_configuration_policy"])
        self.assertEqual(set(POLICY["environments"]), {"synthetic", "development", "staging", "production"})
        for env in ("development", "staging", "production"):
            self.assertIsNone(POLICY["environments"][env])
        self.assertEqual(len({c["client_id"] for c in REGISTRY["clients"]}), 5)
        self.assertEqual(len({c["callback"] for c in REGISTRY["clients"]}), 5)
        for url in [REGISTRY["issuer"]] + [c["callback"] for c in REGISTRY["clients"]]:
            parsed = urlsplit(url)
            self.assertEqual(parsed.scheme, "https")
            self.assertTrue(parsed.hostname.endswith(".example"))
            self.assertFalse(parsed.query or parsed.fragment or parsed.username or parsed.password or parsed.port)

    def test_reviewed_token_metadata_is_not_sync_or_account_authority(self):
        self.assertEqual(set(POLICY["token_success_keys"]), {
            "token_type", "access_token", "expires_in", "refresh_token", "session_id", "scope",
            "issuer", "environment", "audience", "client_id", "installation_id", "account_id", "session_generation",
        })
        binding = POLICY["native_account_binding"]
        self.assertEqual(binding["namespace"], ["issuer", "environment", "account_id"])
        self.assertEqual(binding["subject_source"], "authoritative_account_and_grant_records")
        self.assertEqual(binding["server_generation_minimum"], 0)
        self.assertEqual(binding["server_generation_maximum"], 9_007_199_254_740_991)
        self.assertEqual(binding["initial_server_generation"], 0)
        self.assertEqual(binding["initial_scope_rule"], "exact_captured_requested_scopes")
        self.assertEqual(binding["refresh_scope_rule"], "unchanged_current_scopes")
        self.assertEqual(binding["credential_bindings"], ["audience", "client_id", "installation_id", "session_id", "session_generation"])
        for key in ("subject_is_authority", "server_generation_is_local_account_generation",
                    "sign_in_sets_sync_opt_in", "native_wire_and_secure_storage_qualified"):
            self.assertFalse(binding[key])
        model = ROOT / "apps/cloud/src/account-auth-v1/model.ts"
        if model.exists():  # AS01-only worktrees need not contain the later source slice.
            body = model.read_text().split("export interface NativeSessionResponse {", 1)[1].split("}", 1)[0]
            self.assertEqual(set(re.findall(r"\b([a-z_]+)\s*:", body)), set(POLICY["token_success_keys"]))

    def test_native_client_vector_integrity_and_pkce(self):
        # Corpus/integrity evidence only. Actual native parser/lifecycle consumers
        # must execute these cases; this check does not implement those adapters.
        vectors = load(HERE / "fixtures/native-client-vectors.json")
        self.assertTrue(vectors["synthetic_only"])
        self.assertEqual(vectors["status"], "proposed_disabled_source_not_os_or_authority_proof")
        self.assertTrue((ROOT / vectors["callback_vectors_source"]).is_file())
        responses = vectors["response_cases"]
        errors = vectors["error_cases"]
        self.assertEqual(len(responses), 73)
        self.assertEqual(len(errors), 15)
        self.assertEqual(len({c["id"] for c in responses + errors}), len(responses) + len(errors))
        positive_clients = set()
        for case in responses:
            if not case["valid"]:
                continue
            response = json.loads(case["raw"], object_pairs_hook=unique_object)
            self.assertEqual(response, case["expected"])
            self.assertEqual(set(response), set(POLICY["token_success_keys"]))
            self.assertLessEqual(len(case["raw"].encode()), POLICY["bounds"]["auth_body_bytes"])
            context = case["context"]
            for key in ("issuer", "environment", "audience", "client_id", "installation_id", "scope"):
                self.assertEqual(response[key], context[key])
            self.assertIn(context["client_id"], {c["client_id"] for c in REGISTRY["clients"]})
            positive_clients.add(context["client_id"])
            self.assertIs(type(response["session_generation"]), int)
            self.assertLessEqual(0, response["session_generation"])
            self.assertLessEqual(response["session_generation"], POLICY["native_account_binding"]["server_generation_maximum"])
            self.assertIs(type(response["expires_in"]), int)
            self.assertLess(0, response["expires_in"])
            self.assertLessEqual(response["expires_in"], POLICY["bounds"]["access_seconds"])
            for key, kind in (("access_token", "native_access"), ("refresh_token", "native_refresh")):
                prefix = POLICY["token_prefixes"][kind]
                self.assertTrue(response[key].startswith(prefix))
                self.assertTrue(base64url32(response[key][len(prefix):]))
            self.assertTrue(base64url32(response["session_id"]))
        self.assertEqual(positive_clients, {c["client_id"] for c in REGISTRY["clients"]})
        self.assertEqual(len(vectors["pkce_vectors"]), 3)
        for vector in vectors["pkce_vectors"]:
            self.assertTrue(re.fullmatch(r"[A-Za-z0-9._~-]{43,128}", vector["verifier"]))
            challenge = base64.urlsafe_b64encode(hashlib.sha256(vector["verifier"].encode()).digest()).decode().rstrip("=")
            self.assertEqual(challenge, vector["challenge"])
        self.assertIn("restart_stale_or_corrupt_no_resurrection", vectors["lifecycle_required"])
        self.assertIn("no_health_or_profile_or_destination_or_schedule_or_purchase_effects", vectors["lifecycle_required"])

    def test_reply_header_profile_and_reference_vectors(self):
        # SOURCE reference/corpus evidence only; no Swift/Kotlin/HTTP/TLS authority.
        profile = POLICY["native_reply_headers"]
        self.assertEqual(profile["source_profile"], "healthmd.account_auth.reply_headers")
        self.assertEqual(profile["source_profile_version"], 1)
        self.assertEqual(profile["status"], "locally_reviewed_synthetic_source_only")
        self.assertEqual(profile["input"], "lossless_decoded_name_value_pairs_before_map")
        self.assertEqual(profile["operations"], ["code_exchange", "refresh", "revoke"])
        self.assertEqual(profile["bounds"], {"pairs": 16, "name_bytes": 64, "value_bytes": 1024, "total_name_value_bytes": 4096})
        self.assertEqual((MAX_PAIRS, MAX_NAME_BYTES, MAX_VALUE_BYTES, MAX_PAIR_BYTES), (16, 64, 1024, 4096))
        self.assertEqual(profile["name_full_match"], "[A-Za-z0-9-]{1,64}")
        self.assertEqual(profile["value_ascii_range"], [32, 126])
        self.assertEqual(profile["forbidden_names"], ["authorization", "cookie", "proxy-authorization", "set-cookie"])
        self.assertEqual(profile["required"], {
            "content-type": ["application/json", "application/json; charset=utf-8"],
            "cache-control": ["no-store"], "referrer-policy": ["no-referrer"],
        })
        self.assertEqual(profile["name_comparison"], "ascii_case_insensitive")
        self.assertEqual(profile["duplicate_rule"], "reject_identical_and_ascii_folded_before_map")
        self.assertEqual(profile["other_headers"], "bounded_safe_pairs_allowed_not_acted_upon")
        self.assertTrue(profile["preserve_accepted_pairs"])
        self.assertTrue(profile["empty_nonrequired_value_allowed"])
        for flag in ("bounds_include_http_framing", "native_consumers_qualified", "http_transport_qualified", "grants_authority"):
            self.assertFalse(profile[flag])
        vectors = load(HERE / "fixtures/native-reply-header-vectors.json")
        self.assertEqual(vectors, build_reply_header_vectors())
        self.assertEqual(vectors["schema"], "healthmd.account_auth.native_reply_header_vectors")
        self.assertEqual(vectors["schema_version"], 1)
        self.assertTrue(vectors["synthetic_only"])
        self.assertFalse(vectors["native_consumers_qualified"] or vectors["grants_authority"])
        self.assertEqual(vectors["operations"], profile["operations"])
        encoded = json.dumps(profile, sort_keys=True, separators=(",", ":")).encode()
        self.assertEqual(vectors["policy_sha256"], hashlib.sha256(encoded).hexdigest())
        cases = vectors["cases"]
        self.assertEqual(len({case["id"] for case in cases}), len(cases))
        for case in cases:
            with self.subTest(header_case=case["id"]):
                if case["valid"]:
                    parsed = parse_reply_headers(case["pairs"])
                    self.assertEqual(parsed.pairs, tuple(tuple(pair) for pair in case["pairs"]))
                    self.assertEqual(parsed.get("CACHE-CONTROL"), "no-store")
                    self.assertEqual(parsed.get("referrer-policy"), "no-referrer")
                else:
                    with self.assertRaisesRegex(ValueError, "^invalid source reply headers$"):
                        parse_reply_headers(case["pairs"])

    def test_reply_header_reference_immutable_and_nonreflecting(self):
        pairs = [["Content-Type", "application/json"], ["Cache-Control", "no-store"],
                 ["Referrer-Policy", "no-referrer"], ["X-Private-Label", "synthetic-private-label"]]
        accepted = parse_reply_headers(pairs)
        captured = accepted.pairs
        pairs[3][1] = "changed"
        pairs.append(["Authorization", "synthetic-no-authority"])
        self.assertEqual(accepted.pairs, captured)
        self.assertEqual(accepted.get("X-PRIVATE-LABEL"), "synthetic-private-label")
        self.assertIsNone(accepted.get(" X-Private-Label"))
        with self.assertRaises(AttributeError):
            accepted.pairs = ()
        for text in (repr(accepted), str(accepted)):
            self.assertNotIn("synthetic-private-label", text)
            self.assertNotIn("X-Private-Label", text)
            self.assertIn("no authority", text)
        with self.assertRaisesRegex(ValueError, "^invalid source reply headers$"):
            parse_reply_headers(iter(captured))
        with self.assertRaisesRegex(ValueError, "^invalid source reply headers$"):
            parse_reply_headers([[b"Content-Type", "application/json"]])
        self.assertEqual(parse_reply_headers(captured).pairs, captured)

    def test_callback_vectors(self):
        for vector in VECTORS["callback_vectors"]:
            context = {"environment": "synthetic", "client_id": "synthetic-apple-ios", "pending": True, "generation_matches": True}
            context.update(vector.get("context", {}))
            with self.subTest(vector=vector["id"]):
                self.assertEqual(callback_predicate(vector["uri"].format(**VALUES), context), vector["expected"])
        context = {"environment": "synthetic", "client_id": "synthetic-apple-ios", "pending": True, "generation_matches": True}
        valid = VECTORS["callback_vectors"][0]["uri"].format(**VALUES)
        self.assertEqual(callback_predicate(valid + "&pad=" + "A" * 4096, context), "deny")
        self.assertEqual(callback_predicate(valid + "\n", context), "deny")
        context["pending"] = False  # Accepted attempt cleared: replay is denied.
        self.assertEqual(callback_predicate(valid, context), "deny")
        for client in REGISTRY["clients"]:
            values = {**VALUES, "callback": client["callback"]}
            context.update(client_id=client["client_id"], pending=True)
            self.assertEqual(callback_predicate(VECTORS["callback_vectors"][0]["uri"].format(**values), context), "accept_code")

    def test_authorization_vectors(self):
        verifier = "C" * 43
        challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
        baseline = {
            "client_id": "synthetic-apple-ios", "redirect_uri": VALUES["callback"], "response_type": "code",
            "scope": " ".join(POLICY["scopes"]), "state": VALUES["state"], "code_challenge": challenge,
            "code_challenge_method": "S256", "audience": REGISTRY["audience"],
        }
        for vector in VECTORS["authorization_vectors"]:
            params = {**baseline, **vector.get("patch", {})}
            for key in vector.get("remove", []):
                params.pop(key)
            with self.subTest(vector=vector["id"]):
                self.assertEqual(authorization_predicate(params), vector["expected"] == "allow")
        self.assertFalse(authorization_predicate({**baseline, "state": True}))
        self.assertFalse(authorization_predicate({**baseline, "scope": ""}))

    def test_resource_authority_vectors(self):
        for vector in VECTORS["authority_vectors"]:
            route = ROUTES[vector["route"]]
            principal = {**default_principal(), **vector.get("principal", {})}
            request = {**default_request(route), **vector.get("request", {})}
            with self.subTest(vector=vector["id"]):
                self.assertEqual(resource_predicate(route, principal, request), vector["expected"] == "allow")

    def test_exhaustive_credential_and_service_partition(self):
        allowed_native = {"config_read", "config_write", "sessions", "revoke"}
        # Independent allow table: changing the manifest alone cannot silently
        # turn a health/provider/direct credential into configuration authority.
        expected_kinds = {
            "authorize_page": {"none", "browser_session"},
            "decision": {"browser_session"},
            "code_exchange": {"authorization_code"},
            "refresh": {"native_refresh"},
            "sessions": {"browser_session", "native_access"},
            "revoke": {"browser_session", "native_access", "native_refresh"},
            "config_read": {"browser_session", "native_access"},
            "config_write": {"browser_session", "native_access"},
        }
        self.assertEqual(set(ROUTES), set(expected_kinds))
        for route in ROUTES.values():
            self.assertEqual(set(route["credential_kinds"]), expected_kinds[route["id"]])
            for kind in POLICY["credential_kinds"]:
                principal = {**default_principal(), "kind": kind}
                request = default_request(route)
                with self.subTest(route=route["id"], kind=kind):
                    self.assertEqual(resource_predicate(route, principal, request), kind in expected_kinds[route["id"]])
            if resource_predicate(route, default_principal(), default_request(route)):
                self.assertIn(route["id"], allowed_native)
            for profile in POLICY["denied_service_profiles"]:
                for kind in route["credential_kinds"]:
                    self.assertFalse(resource_predicate(route, {**default_principal(), "kind": kind}, {**default_request(route), "service_profile": profile}))
        self.assertEqual({r["id"] for r in ROUTES.values() if "native_access" in r["credential_kinds"]}, allowed_native)
        allowed_paths = {(r["method"], r["path"]) for r in ROUTES.values() if "native_access" in r["credential_kinds"]}
        for operation in POLICY["native_denied_operations"]:
            self.assertNotIn((operation["method"], operation["path"]), allowed_paths)
        self.assertEqual(set(POLICY["scopes"]), {"config:profiles:read", "config:profiles:write", "account:sessions:read", "account:sessions:revoke:self"})
        for prefix in POLICY["token_prefixes"].values():
            for legacy in ("hmd_ses_", "hmd_ing_", "hmd_dev_", "hmd_read_", "hmd_login_"):
                self.assertFalse(prefix.startswith(legacy))

    def test_exchange_binding_vectors(self):
        baseline = {
            "verifier_matches": True, "client_matches": True, "callback_matches": True,
            "environment_matches": True, "audience_matches": True, "code_unused": True,
            "account_active": True, "consent_account_matches": True, "installation_present": True,
            "expires_at": 220,
        }
        for vector in VECTORS["exchange_vectors"]:
            state = {**baseline, **vector["patch"]}
            allowed = all(state[k] for k in baseline if k != "expires_at") and state["expires_at"] > 100
            with self.subTest(vector=vector["id"]):
                self.assertEqual(allowed, vector["expected"] == "allow")

    def test_symbolic_lifecycle_vectors(self):
        for vector in VECTORS["lifecycle_vectors"]:
            family = SymbolicFamily()
            for index, step in enumerate(vector["steps"]):
                with self.subTest(vector=vector["id"], step=index):
                    self.assertEqual(family.step(step), step["expected"])

    def test_profile_preservation_and_revision_guards(self):
        baseline = {
            "mapping_verified": True, "foreign_provenance_verified": True, "configuration_protected": False,
            "accepted_revision": 1, "fetched_revision": 1, "accepted_hash": "synthetic-hash-a",
            "fetched_hash": "synthetic-hash-a", "import_blocked": False,
            "binding_verified": True, "local_execution_grants": True,
        }
        for vector in VECTORS["profile_guard_vectors"]:
            state = {**baseline, **vector.get("patch", {})}
            with self.subTest(vector=vector["id"]):
                self.assertEqual(profile_guard(vector["operation"], state), vector["expected"] == "allow")
        pending = {**baseline, "fetched_revision": 2, "fetched_hash": "synthetic-new-hash", "requested_snapshot": "accepted"}
        self.assertTrue(profile_guard("execute", pending))

    def test_field_inventory_resolves_all_pinned_rows(self):
        sections = {row["path"] for row in FIELDS["portable_sections"]}
        schema_ref = FIELDS["source_schema"]
        schema_path = ROOT / schema_ref["path"]
        self.assertEqual(hashlib.sha256(schema_path.read_bytes()).hexdigest(), schema_ref["sha256"])
        source_schema = load(schema_path)
        profile_keys = set(source_schema["$defs"]["profile"]["properties"])
        self.assertEqual(sections, profile_keys - {"bundle_id"})
        self.assertFalse(FIELDS["mapped_contract_paths"]["native_settings_json_allowed"])
        total = 0
        union = set()
        for source in FIELDS["source_ledgers"]:
            path = ROOT / source["path"]
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), source["sha256"])
            rows = load(path)["fields"]
            total += len(rows)
            self.assertEqual(len(rows), source["field_count"])
            self.assertEqual(dict(Counter(row["disposition"] for row in rows)), source["disposition_counts"])
            self.assertEqual(len({(r["source_type"], r[source["field_key"]]) for r in rows}), len(rows))
            for row in rows:
                disposition = row["disposition"]
                self.assertIn(disposition, FIELDS["disposition_to_sync"])
                if FIELDS["disposition_to_sync"][disposition] == "excluded":
                    self.assertIsNone(row["contract_path"])
                else:
                    path_text = row["contract_path"]
                    self.assertIsNotNone(path_text)
                    union.add(path_text)
                    if path_text != "profiles[]":  # Explicitly decomposed mixed container.
                        self.assertTrue(path_text.startswith("profiles[]."))
                        self.assertIn(path_text[len("profiles[]."):].split(".")[0], sections)
        self.assertEqual(total, 329)
        self.assertTrue(union)
        self.assertEqual(FIELDS["disposition_to_sync"]["schedule_intent"], "inert_content_disabled_schedule")
        android = load(ROOT / FIELDS["source_ledgers"][1]["path"])["fields"]
        for field in ("todayRefreshEnabled", "todayRefreshIntervalHours"):
            rows = [r for r in android if r["source_type"] == "ScheduledProfileEntry" and r["serialized_field"] == field]
            self.assertEqual([r["disposition"] for r in rows], ["local_only"])

    def test_capability_and_evidence_paths(self):
        classifications = {"shared", "apple_only", "android_only", "unavailable", "planned"}
        for capability in CAPABILITIES["capabilities"]:
            self.assertIn(capability["classification"], classifications)
            for platform in ("apple", "android"):
                value = capability["platforms"][platform]
                self.assertIn(value["state"], {"available", "planned", "unavailable"})
                if value["state"] == "planned":
                    self.assertTrue(value.get("target"))
                if value["state"] == "unavailable":
                    self.assertTrue(value.get("reason"))
            for evidence in capability["evidence"]:
                self.assertTrue((ROOT / evidence).is_file(), evidence)
        for evidence in POLICY["evidence"]:
            self.assertTrue((ROOT / evidence).is_file(), evidence)
        docs = [ROOT / "docs/architecture/account-profile-sync-source-design.md", HERE / "contract.md"]
        for document in docs:
            for link in re.findall(r"\]\(([^)]+)\)", document.read_text(encoding="utf-8")):
                if not link.startswith(("https:", "http:", "#")):
                    self.assertTrue((document.parent / link.split("#", 1)[0]).exists(), (document, link))

    def test_vector_integrity_and_closed_json_parsing(self):
        self.assertTrue(VECTORS["synthetic_only"])
        for key, rows in VECTORS.items():
            if key.endswith("_vectors"):
                self.assertEqual(len({r["id"] for r in rows}), len(rows), key)
                self.assertTrue(any(r.get("expected") == "deny" or key == "lifecycle_vectors" for r in rows), key)
        with self.assertRaises(ValueError):
            json.loads('{"client_id":"synthetic-a","client_id":"synthetic-b"}', object_pairs_hook=unique_object)
        self.assertEqual(POLICY["rotation_policy"], "single_child_strict_reuse_revokes_family_no_grace")
        self.assertEqual(POLICY["unverified_commit_result"], "verification_pending_no_secret")
        self.assertIn("change_chart_precedence", POLICY["forbidden_side_effects"])
        self.assertIn("link_accounts", POLICY["forbidden_side_effects"])
        self.assertIn("no_global_destination_fallback", FIELDS["activation_rules"])
        self.assertEqual(FIELDS["mapped_contract_paths"]["foreign_provenance_read_failure"], "quarantine_never_publish_empty_foreign_deletions")
        self.assertIn("execution_approval_is_revision_hash_bound_not_identity_only", FIELDS["activation_rules"])


if __name__ == "__main__":
    counts = {key: len(rows) for key, rows in VECTORS.items() if key.endswith("_vectors")}
    print("Synthetic design vectors:", counts, flush=True)
    unittest.main(verbosity=2)
