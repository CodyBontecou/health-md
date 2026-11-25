"""Upload screenshots to an APP_IPHONE_DUO set via the raw App Store Connect API (asc CLI lacks the type).

Usage: python3 -I upload_duo.py <versionLocalizationId> <png>...
Creates the set if missing, uploads files in order, waits for processing, prints each state.
"""
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.request

TYPE = "APP_IPHONE_DUO"


def asc(method, path, body=None, query=()):
    cmd = ["asc", "api", method, path]
    for q in query:
        cmd += ["--query", q]
    if body is not None:
        cmd += ["--confirm", "--body", json.dumps(body)]
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(f"{method} {path} failed: {out.stderr.strip() or out.stdout.strip()}")
    return json.loads(out.stdout) if out.stdout.strip() else {}


def find_set(loc_id):
    sets = asc("GET", f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets",
               query=[f"filter[screenshotDisplayType]={TYPE}"])["data"]
    if sets:
        return sets[0]["id"]
    created = asc("POST", "/v1/appScreenshotSets", {"data": {
        "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": TYPE},
        "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}})
    return created["data"]["id"]


def upload(set_id, path):
    data = open(path, "rb").read()
    reserved = asc("POST", "/v1/appScreenshots", {"data": {
        "type": "appScreenshots",
        "attributes": {"fileName": os.path.basename(path), "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})["data"]
    for op in reserved["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
        for h in op.get("requestHeaders", []):
            req.add_header(h["name"], h["value"])
        urllib.request.urlopen(req, timeout=120).read()
    asc("PATCH", f"/v1/appScreenshots/{reserved['id']}", {"data": {
        "type": "appScreenshots", "id": reserved["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    return reserved["id"]


def wait(shot_id):
    for _ in range(60):
        a = asc("GET", f"/v1/appScreenshots/{shot_id}")["data"]["attributes"]
        state = (a.get("assetDeliveryState") or {})
        if state.get("state") in ("COMPLETE", "FAILED"):
            return state
        time.sleep(3)
    return state


def main():
    loc_id, files = sys.argv[1], sys.argv[2:]
    set_id = find_set(loc_id)
    for f in files:
        shot = upload(set_id, f)
        state = wait(shot)
        print(os.path.basename(f), shot, state.get("state"), json.dumps(state.get("errors") or [])[:400])


main()
