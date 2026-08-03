#!/usr/bin/env python3
"""Generate localized 1200×630 documentation social cards.

Requires Pillow. Latin text uses the repository's self-hosted Geist variable
font. CJK text uses the locale-appropriate fonts bundled with macOS; generation
fails clearly rather than silently rendering missing-glyph boxes.
"""

import argparse
from functools import lru_cache
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "docs-src" / "public" / "social"
GEIST = ROOT / "assets" / "fonts" / "Geist-Variable.woff2"
ICON = ROOT / "assets" / "app-icon" / "icon_1024x1024.png"

CJK_FONTS = {
    "ja": (
        Path("/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc"),
        Path("/System/Library/Fonts/Hiragino Sans GB.ttc"),
    ),
    "ko": (
        Path("/System/Library/Fonts/AppleSDGothicNeo.ttc"),
        Path("/System/Library/Fonts/Supplemental/AppleGothic.ttf"),
    ),
    "zh-hans": (
        Path("/System/Library/Fonts/Hiragino Sans GB.ttc"),
        Path("/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc"),
    ),
}

COPY = {
    "es": {
        "title": "Documentación",
        "tagline": "Exporta. Consulta. Automatiza. Crea.",
        "features": "HERRAMIENTAS LOCALES  ·  ALCANCE EXPLÍCITO  ·  RESULTADOS VERSIONADOS",
    },
    "de": {
        "title": "Dokumentation",
        "tagline": "Exportieren. Abfragen. Automatisieren. Entwickeln.",
        "features": "LOKALE WERKZEUGE  ·  KLARER UMFANG  ·  VERSIONIERTE ERGEBNISSE",
    },
    "fr": {
        "title": "Documentation",
        "tagline": "Exportez. Interrogez. Automatisez. Développez.",
        "features": "OUTILS LOCAUX  ·  PÉRIMÈTRE EXPLICITE  ·  RÉSULTATS VERSIONNÉS",
    },
    "pt-br": {
        "title": "Documentação",
        "tagline": "Exporte. Consulte. Automatize. Desenvolva.",
        "features": "FERRAMENTAS LOCAIS  ·  ESCOPO EXPLÍCITO  ·  RESULTADOS VERSIONADOS",
    },
    "it": {
        "title": "Documentazione",
        "tagline": "Esporta. Interroga. Automatizza. Sviluppa.",
        "features": "STRUMENTI LOCALI  ·  AMBITO ESPLICITO  ·  RISULTATI VERSIONATI",
    },
    "nl": {
        "title": "Documentatie",
        "tagline": "Exporteer. Bevraag. Automatiseer. Bouw.",
        "features": "LOKALE TOOLS  ·  EXPLICIETE SCOPE  ·  GEVERSIONEERDE RESULTATEN",
    },
    "ja": {
        "title": "ドキュメント",
        "tagline": "エクスポート。クエリ。自動化。開発。",
        "features": "ローカルツール  ·  明示的なスコープ  ·  バージョン管理された結果",
    },
    "ko": {
        "title": "문서",
        "tagline": "내보내기. 쿼리. 자동화. 빌드.",
        "features": "로컬 도구  ·  명시적 범위  ·  버전 관리된 결과",
    },
    "zh-hans": {
        "title": "文档",
        "tagline": "导出。查询。自动化。构建。",
        "features": "本地工具  ·  明确范围  ·  版本化结果",
    },
}


@lru_cache(maxsize=None)
def font(locale: str, size: int, weight: int = 400) -> ImageFont.FreeTypeFont:
    if locale not in CJK_FONTS:
        value = ImageFont.truetype(str(GEIST), size)
        value.set_variation_by_axes([weight])
        return value

    path = next((candidate for candidate in CJK_FONTS[locale] if candidate.is_file()), None)
    if path is None:
        choices = ", ".join(str(candidate) for candidate in CJK_FONTS[locale])
        raise FileNotFoundError(f"No suitable {locale} font found; checked: {choices}")
    return ImageFont.truetype(str(path), size)


def fitting_font(
    draw: ImageDraw.ImageDraw,
    locale: str,
    value: str,
    maximum: int,
    start: int,
    weight: int = 400,
) -> ImageFont.FreeTypeFont:
    for size in range(start, 11, -1):
        candidate = font(locale, size, weight)
        left, _, right, _ = draw.textbbox((0, 0), value, font=candidate)
        if right - left <= maximum:
            return candidate
    raise ValueError(f"Text cannot fit in {maximum}px for {locale}: {value}")


def generate(locale: str, copy: dict[str, str]) -> Path:
    image = Image.new("RGB", (1200, 630), "#f1f1ee")
    draw = ImageDraw.Draw(image)

    for x in range(0, 1201, 84):
        draw.line((x, 0, x, 630), fill="#deded9", width=1)
    for y in range(0, 631, 84):
        draw.line((0, y, 1200, y), fill="#deded9", width=1)
    draw.rectangle((0, 0, 760, 630), fill="#f8f8f5")

    draw.text((88, 163), "Health.md", font=font("en", 84, 760), fill="#111111")
    draw.text(
        (88, 271),
        copy["title"],
        font=fitting_font(draw, locale, copy["title"], 640, 54),
        fill="#111111",
    )
    draw.text(
        (90, 364),
        copy["tagline"],
        font=fitting_font(draw, locale, copy["tagline"], 650, 28),
        fill="#60605e",
    )
    draw.rectangle((90, 449, 98, 457), fill="#111111")
    draw.text(
        (112, 439),
        copy["features"],
        font=fitting_font(draw, locale, copy["features"], 635, 20, 450),
        fill="#555553",
    )

    draw.rectangle((966, 246, 1104, 385), fill="#050505")
    icon = Image.open(ICON).convert("RGBA").resize((82, 82), Image.Resampling.LANCZOS)
    image.paste(icon, (994, 275), icon)

    OUTPUT.mkdir(parents=True, exist_ok=True)
    destination = OUTPUT / f"docs-og-{locale}.png"
    image.save(destination, optimize=True)
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("locales", nargs="*", choices=COPY, default=list(COPY))
    args = parser.parse_args()
    for locale in args.locales:
        print(generate(locale, COPY[locale]).relative_to(ROOT))
