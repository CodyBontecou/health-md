#!/usr/bin/env python3
"""
App Store screenshot enhancer using FLUX Kontext Pro on Replicate.
Takes scaffold PNGs and generates polished, professional marketing screenshots.
"""

import os
import sys
import base64
import time
import json
import urllib.request
import urllib.error
from pathlib import Path
import concurrent.futures
import argparse

REPLICATE_API_TOKEN = "r8_ZBpLVcLMRT9JY1bKXHberPB4e3EgCQu2tlnVA"
MODEL = "black-forest-labs/flux-kontext-pro"

SCREENSHOTS_DIR = Path(__file__).parent


def image_to_data_uri(path: Path) -> str:
    with open(path, "rb") as f:
        data = base64.b64encode(f.read()).decode()
    ext = path.suffix.lower().lstrip(".")
    mime = {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg"}.get(ext, "image/png")
    return f"data:{mime};base64,{data}"


def call_replicate(prompt: str, image_path: Path, output_path: Path, seed: int = None) -> bool:
    """Call Replicate FLUX Kontext Pro and save output."""
    
    image_uri = image_to_data_uri(image_path)
    
    payload = {
        "version": "black-forest-labs/flux-kontext-pro",
        "input": {
            "prompt": prompt,
            "input_image": image_uri,
            "aspect_ratio": "match_input_image",
            "output_format": "jpg",
            "safety_tolerance": 2,
            "prompt_upsampling": False,
        }
    }
    if seed is not None:
        payload["input"]["seed"] = seed
    
    headers = {
        "Authorization": f"Bearer {REPLICATE_API_TOKEN}",
        "Content-Type": "application/json",
        "Prefer": "wait"  # Wait for completion synchronously
    }
    
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        "https://api.replicate.com/v1/predictions",
        data=body,
        headers=headers,
        method="POST"
    )
    
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            result = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print(f"  HTTP Error {e.code}: {e.read().decode()[:500]}")
        return False
    except Exception as e:
        print(f"  Request failed: {e}")
        return False
    
    # Poll if not done
    poll_url = result.get("urls", {}).get("get")
    status = result.get("status")
    
    while status not in ("succeeded", "failed", "canceled"):
        time.sleep(3)
        poll_req = urllib.request.Request(
            poll_url,
            headers={"Authorization": f"Bearer {REPLICATE_API_TOKEN}"},
            method="GET"
        )
        try:
            with urllib.request.urlopen(poll_req, timeout=30) as resp:
                result = json.loads(resp.read())
                status = result.get("status")
                print(f"    Status: {status}")
        except Exception as e:
            print(f"    Poll error: {e}")
            time.sleep(5)
    
    if status != "succeeded":
        print(f"  Failed: {result.get('error', 'unknown')}")
        return False
    
    output = result.get("output")
    if isinstance(output, list):
        output = output[0]
    
    if not output:
        print("  No output URL")
        return False
    
    # Download output
    dl_req = urllib.request.Request(output, method="GET")
    try:
        with urllib.request.urlopen(dl_req, timeout=60) as resp:
            output_path.parent.mkdir(parents=True, exist_ok=True)
            with open(output_path, "wb") as f:
                f.write(resp.read())
        print(f"  ✓ Saved: {output_path}")
        return True
    except Exception as e:
        print(f"  Download failed: {e}")
        return False


# ─── Per-screenshot prompts ─────────────────────────────────────────────────

PROMPTS = {
    "01-export-locally": {
        "slug": "01-export-locally",
        "base_prompt": """Transform this App Store marketing screenshot scaffold into a polished, agency-quality professional image.

PRESERVE EXACTLY:
- The solid purple background (#9B6DD7) — keep it completely flat, no gradients, no glows, no effects
- The headline text "EXPORT" (large, bold, white) and "HEALTH DATA LOCALLY" (smaller, bold, white) — same exact position, size, weight, color
- The app screenshot content shown on the phone screen

ENHANCE:
- Replace the flat phone rectangle with a photorealistic iPhone 15 Pro mockup — titanium frame with subtle specular highlights, soft drop shadow beneath the device, accurate Dynamic Island at top, realistic screen glass with very subtle reflections
- The EXPORT FORMAT card on screen (showing Markdown, Obsidian, JSON, CSV pill buttons) should dramatically burst out of the phone: scale it up significantly so it extends well beyond BOTH left and right edges of the device frame, overlapping the phone bezel on both sides, nearly reaching the full width of the image. Keep it at the same vertical height as on screen. Add a soft dark drop shadow below this floating card to make it look like it hovers in front of the phone
- Add subtle ambient light on the phone edges to give it 3D depth
- The overall image should look like it came from a $5000+ App Store screenshot design agency — clean, premium, high-converting
- No watermarks, no extra text, no App Store UI chrome""",

        "v1_extra": "The Export Format card breakout should have crisp, sharp edges with a subtle frosted glass look.",
        "v2_extra": "Make the phone frame slightly darker titanium and the breakout card slightly elevated with a stronger drop shadow for maximum depth.",
        "v3_extra": "The breakout card should have a very subtle purple-tinted glow on its top edge, matching the app's brand color.",
    },

    "02-own-your-data": {
        "slug": "02-own-your-data",
        "base_prompt": """Transform this App Store marketing screenshot scaffold into a polished, agency-quality professional image.

PRESERVE EXACTLY:
- The solid purple background (#9B6DD7) — keep it completely flat, no gradients, no glows, no effects
- The headline text "OWN" (large, bold, white) and "YOUR HEALTH DATA" (smaller, bold, white) — same exact position, size, weight, color
- The app screenshot content shown on the phone screen

ENHANCE:
- Replace the flat phone rectangle with a photorealistic iPhone 15 Pro mockup — titanium frame with subtle specular highlights, soft drop shadow beneath the device, accurate Dynamic Island at top, realistic screen glass with very subtle reflections
- The WRITE MODE card on screen (showing Overwrite, Append, Update radio options) should dramatically burst out of the phone: scale it up significantly so it extends well beyond BOTH left and right edges of the device frame, overlapping the phone bezel on both sides, nearly reaching the full width of the image. Keep it at the same vertical height as on screen. Add a soft dark drop shadow below this floating card to make it look like it hovers in front of the phone
- Add subtle ambient light on the phone edges to give it 3D depth
- The overall image should look like it came from a $5000+ App Store screenshot design agency — clean, premium, high-converting
- No watermarks, no extra text, no App Store UI chrome""",

        "v1_extra": "The Write Mode card breakout should be crisp and clean with sharp rounded corners.",
        "v2_extra": "Make the phone frame slightly darker titanium and the breakout card slightly elevated with a stronger drop shadow for maximum depth.",
        "v3_extra": "The breakout card should emphasize the 'Overwrite' option being selected with a subtle purple highlight visible.",
    },

    "03-track-metrics": {
        "slug": "03-track-metrics",
        "base_prompt": """Transform this App Store marketing screenshot scaffold into a polished, agency-quality professional image.

PRESERVE EXACTLY:
- The solid purple background (#9B6DD7) — keep it completely flat, no gradients, no glows, no effects
- The headline text "TRACK" (large, bold, white) and "60+ HEALTH METRICS" (smaller, bold, white) — same exact position, size, weight, color
- The app screenshot content shown on the phone screen

ENHANCE:
- Replace the flat phone rectangle with a photorealistic iPhone 15 Pro mockup — titanium frame with subtle specular highlights, soft drop shadow beneath the device, accurate Dynamic Island at top, realistic screen glass with very subtle reflections
- The Sleep category card on screen (showing the grouped list with Total Sleep, Deep Sleep, REM Sleep, Light Sleep, Awake Time, In Bed Time all checked with purple checkboxes) should dramatically burst out of the phone: scale it up significantly so it extends well beyond BOTH left and right edges of the device frame, overlapping the phone bezel on both sides, nearly reaching the full width of the image. Keep it at the same vertical height as on screen. Add a soft dark drop shadow below this floating card to make it look like it hovers in front of the phone
- Add subtle ambient light on the phone edges to give it 3D depth
- The overall image should look like it came from a $5000+ App Store screenshot design agency — clean, premium, high-converting
- No watermarks, no extra text, no App Store UI chrome""",

        "v1_extra": "The Sleep metrics card should be crisp with all checkboxes clearly visible showing items are selected.",
        "v2_extra": "Make the phone frame slightly darker titanium and the breakout card slightly elevated with a stronger drop shadow for maximum depth.",
        "v3_extra": "The breakout card should have slightly more visible purple checkbox colors to reinforce the health tracking theme.",
    },

    "04-automate-exports": {
        "slug": "04-automate-exports",
        "base_prompt": """Transform this App Store marketing screenshot scaffold into a polished, agency-quality professional image.

PRESERVE EXACTLY:
- The solid purple background (#9B6DD7) — keep it completely flat, no gradients, no glows, no effects
- The headline text "AUTOMATE" (large, bold, white) and "DAILY EXPORTS" (smaller, bold, white) — same exact position, size, weight, color
- The app screenshot content shown on the phone screen

ENHANCE:
- Replace the flat phone rectangle with a photorealistic iPhone 15 Pro mockup — titanium frame with subtle specular highlights, soft drop shadow beneath the device, accurate Dynamic Island at top, realistic screen glass with very subtle reflections
- The "Automatic Export" toggle card on screen (showing the toggle switched ON with purple/white toggle, and subtitle "Export your health data automatically") should dramatically burst out of the phone: scale it up significantly so it extends well beyond BOTH left and right edges of the device frame, overlapping the phone bezel on both sides, nearly reaching the full width of the image. Keep it at the same vertical height as on screen. Add a soft dark drop shadow below this floating card to make it look like it hovers in front of the phone
- Add subtle ambient light on the phone edges to give it 3D depth
- The overall image should look like it came from a $5000+ App Store screenshot design agency — clean, premium, high-converting
- No watermarks, no extra text, no App Store UI chrome""",

        "v1_extra": "The Automatic Export toggle should be clearly visible in the ON state with its purple toggle color.",
        "v2_extra": "Make the phone frame slightly darker titanium and the breakout card slightly elevated with a stronger drop shadow for maximum depth.",
        "v3_extra": "The breakout card's toggle should have a slight glow effect to draw attention to the automation being active.",
    },

    "05-sync-obsidian": {
        "slug": "05-sync-obsidian",
        "base_prompt": """Transform this App Store marketing screenshot scaffold into a polished, agency-quality professional image.

PRESERVE EXACTLY:
- The solid purple background (#9B6DD7) — keep it completely flat, no gradients, no glows, no effects
- The headline text "SYNC" (large, bold, white) and "TO OBSIDIAN SEAMLESSLY" (smaller, bold, white) — same exact position, size, weight, color
- The app screenshot content shown on the phone screen

ENHANCE:
- Replace the flat phone rectangle with a photorealistic iPhone 15 Pro mockup — titanium frame with subtle specular highlights, soft drop shadow beneath the device, accurate Dynamic Island at top, realistic screen glass with very subtle reflections
- The "CURRENT FORMAT" card on screen (showing "Obsidian Bases" as the format with "Write mode: Overwrite") should dramatically burst out of the phone: scale it up significantly so it extends well beyond BOTH left and right edges of the device frame, overlapping the phone bezel on both sides, nearly reaching the full width of the image. Keep it at the same vertical height as on screen. Add a soft dark drop shadow below this floating card to make it look like it hovers in front of the phone
- Add subtle ambient light on the phone edges to give it 3D depth
- The overall image should look like it came from a $5000+ App Store screenshot design agency — clean, premium, high-converting
- No watermarks, no extra text, no App Store UI chrome""",

        "v1_extra": "The Current Format card should prominently display 'Obsidian Bases' text clearly.",
        "v2_extra": "Make the phone frame slightly darker titanium and the breakout card slightly elevated with a stronger drop shadow for maximum depth.",
        "v3_extra": "The breakout card should have an Obsidian-purple tint on its border to reinforce the Obsidian integration theme.",
    },
}


def generate_version(scaffold_path: Path, output_path: Path, full_prompt: str, seed: int) -> bool:
    print(f"  Generating {output_path.name} (seed={seed})...")
    return call_replicate(full_prompt, scaffold_path, output_path, seed)


def enhance_screenshot(slug: str) -> dict:
    """Generate all 3 versions for one screenshot."""
    cfg = PROMPTS[slug]
    scaffold = SCREENSHOTS_DIR / slug / "scaffold.png"
    
    if not scaffold.exists():
        print(f"✗ Scaffold not found: {scaffold}")
        return {"slug": slug, "success": False}
    
    print(f"\n{'='*60}")
    print(f"Enhancing: {slug}")
    print(f"{'='*60}")
    
    versions = [
        (SCREENSHOTS_DIR / slug / "v1.jpg", cfg["base_prompt"] + "\n\nAdditional styling: " + cfg["v1_extra"], 42),
        (SCREENSHOTS_DIR / slug / "v2.jpg", cfg["base_prompt"] + "\n\nAdditional styling: " + cfg["v2_extra"], 137),
        (SCREENSHOTS_DIR / slug / "v3.jpg", cfg["base_prompt"] + "\n\nAdditional styling: " + cfg["v3_extra"], 888),
    ]
    
    results = {}
    # Generate 3 versions in parallel
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        futures = {
            executor.submit(generate_version, scaffold, out_path, prompt, seed): out_path.name
            for out_path, prompt, seed in versions
        }
        for future in concurrent.futures.as_completed(futures):
            name = futures[future]
            try:
                ok = future.result()
                results[name] = ok
            except Exception as e:
                print(f"  ERROR for {name}: {e}")
                results[name] = False
    
    success = all(results.values())
    print(f"\n{'✓' if success else '✗'} {slug}: {results}")
    return {"slug": slug, "success": success, "results": results}


def main():
    parser = argparse.ArgumentParser(description="Enhance App Store screenshots")
    parser.add_argument("slugs", nargs="*", default=list(PROMPTS.keys()),
                        help="Screenshot slugs to process (default: all)")
    args = parser.parse_args()
    
    slugs = [s for s in args.slugs if s in PROMPTS]
    if not slugs:
        print(f"Valid slugs: {list(PROMPTS.keys())}")
        sys.exit(1)
    
    print(f"Enhancing {len(slugs)} screenshots...")
    
    all_results = []
    for slug in slugs:
        result = enhance_screenshot(slug)
        all_results.append(result)
    
    print("\n" + "="*60)
    print("SUMMARY")
    print("="*60)
    for r in all_results:
        status = "✓" if r["success"] else "✗"
        print(f"{status} {r['slug']}")
    
    failed = [r for r in all_results if not r["success"]]
    if failed:
        print(f"\n{len(failed)} failed: {[r['slug'] for r in failed]}")
        sys.exit(1)
    else:
        print("\nAll screenshots generated successfully!")


if __name__ == "__main__":
    main()
