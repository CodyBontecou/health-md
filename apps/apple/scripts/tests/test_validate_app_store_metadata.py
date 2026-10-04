#!/usr/bin/env python3
"""Adversarial tests for the App Store metadata validator."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

VALIDATOR_PATH = Path(__file__).resolve().parents[1] / "validate-app-store-metadata.py"
SPEC = importlib.util.spec_from_file_location("validate_app_store_metadata", VALIDATOR_PATH)
assert SPEC and SPEC.loader
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


def run_against(tree: dict[str, str]) -> tuple[int, list[str]]:
    """Run the validator against a metadata tree; return (main rc, errors)."""
    import contextlib
    import io

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for rel, body in tree.items():
            target = root / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(body, encoding="utf-8")
        validator.APP_INFO_DIR = root / "app-info"
        validator.VERSION_DIR = root / "version"
        errors: list[str] = []
        app_info = validator.validate_app_info(errors)
        validator.validate_version(errors, app_info)
        stream = io.StringIO()
        with contextlib.redirect_stdout(stream):
            rc = validator.main()
        return rc, errors


def app_info(name: str, subtitle: str) -> str:
    return json.dumps(
        {"name": name, "subtitle": subtitle, "privacyPolicyUrl": "https://example.com/p"},
        ensure_ascii=False,
    )


def version_file(keywords: str, *, whats_new: str = "Fixes") -> str:
    return json.dumps(
        {
            "description": "Description",
            "keywords": keywords,
            "marketingUrl": "https://example.com",
            "supportUrl": "https://example.com/s",
            "whatsNew": whats_new,
        },
        ensure_ascii=False,
    )


VALID_APP_INFO = app_info("Health.md", "Daily Health Journal & Export")
VALID_VERSION = version_file("obsidian,hrv,sleep,markdown,tracker")


def keyword_tree(locale: str, keywords: str) -> dict[str, str]:
    tree = {
        "app-info/en-US.json": VALID_APP_INFO,
        "version/3.4.1/en-US.json": VALID_VERSION,
    }
    tree[f"app-info/{locale}.json"] = VALID_APP_INFO
    tree[f"version/3.4.1/{locale}.json"] = version_file(keywords)
    return tree


class KeywordFieldTests(unittest.TestCase):
    def test_valid_fields_pass(self) -> None:
        rc, errors = run_against(
            {
                "app-info/en-US.json": VALID_APP_INFO,
                "version/3.0.6/en-US.json": VALID_VERSION,
            }
        )
        self.assertEqual((rc, errors), (0, []))

    def test_original_japanese_keywords_over_byte_limit_fail(self) -> None:
        # Frozen version/3.4.1/ja.json counterexample: valid character count,
        # but more than twice the App Store Connect keyword byte budget.
        keywords = (
            "健康データ,書き出し,バックアップ,Obsidian,JSON,CSV,PDF,健康レポート,"
            "ローカル,プライバシー,同期,Mac,ショートカット,睡眠,心拍,血圧,歩数,体重,HRV,ヘルスケア"
        )
        self.assertEqual(len(keywords), 98)
        self.assertEqual(len(keywords.encode("utf-8")), 208)
        rc, errors = run_against(keyword_tree("ja", keywords))
        self.assertEqual(
            (rc, errors),
            (1, ["version/3.4.1/ja: keywords are 208 UTF-8 bytes (limit 100)"]),
        )

    def test_ascii_keywords_at_100_bytes_pass(self) -> None:
        self.assertEqual(run_against(keyword_tree("en-US", "a" * 100)), (0, []))

    def test_ascii_keywords_at_101_bytes_fail(self) -> None:
        self.assertEqual(
            run_against(keyword_tree("en-US", "a" * 101)),
            (1, ["version/3.4.1/en-US: keywords are 101 UTF-8 bytes (limit 100)"]),
        )

    def test_multibyte_keywords_at_100_bytes_pass(self) -> None:
        cases = (
            ("es-ES", "ñ" * 50),
            ("fr-FR", "é" * 50),
            ("ja", "あ" * 33 + "a"),
            ("ko", "건" * 33 + "a"),
            ("zh-Hans", "健" * 33 + "a"),
            ("en-US", "🩺" * 25),
        )
        for locale, keywords in cases:
            with self.subTest(locale=locale):
                self.assertEqual(run_against(keyword_tree(locale, keywords)), (0, []))

    def test_multibyte_keywords_at_101_bytes_fail(self) -> None:
        cases = (
            ("es-ES", "ñ" * 50 + "a"),
            ("fr-FR", "é" * 50 + "a"),
            ("ja", "あ" * 33 + "ab"),
            ("ko", "건" * 33 + "ab"),
            ("zh-Hans", "健" * 33 + "ab"),
            ("en-US", "🩺" * 25 + "a"),
        )
        for locale, keywords in cases:
            with self.subTest(locale=locale):
                self.assertEqual(
                    run_against(keyword_tree(locale, keywords)),
                    (1, [f"version/3.4.1/{locale}: keywords are 101 UTF-8 bytes (limit 100)"]),
                )

    def test_keyword_separators_count_toward_byte_limit(self) -> None:
        self.assertEqual(run_against(keyword_tree("fr-FR", "é" * 48 + ",csv")), (0, []))
        self.assertEqual(
            run_against(keyword_tree("fr-FR", "é" * 48 + ",json")),
            (1, ["version/3.4.1/fr-FR: keywords are 101 UTF-8 bytes (limit 100)"]),
        )

    def test_original_other_localized_keywords_over_byte_limit_fail(self) -> None:
        # Preserve both generations of affected keyword lists independently of
        # the corrected canonical files, so shortening metadata cannot hide the bug.
        cases = (
            (
                "es-ES", 101,
                "obsidian,vfc,sueño,bienestar,markdown,apple,métricas,seguimiento,"
                "corazón,pasos,peso,registro,notas",
            ),
            (
                "fr-FR", 103,
                "obsidian,vfc,sommeil,bien-être,markdown,apple,métriques,suivi,"
                "cœur,pas,poids,notes,fitness,quotidien",
            ),
            (
                "fr-FR", 103,
                "données,CSV,JSON,Obsidian,Markdown,rapport,médecin,sauvegarde,"
                "privé,Raccourcis,PDF,sommeil,Mac,local",
            ),
            (
                "ja", 228,
                "睡眠,ヘルスケア,体重管理,フィットネス,血圧,運動,カロリー,体温,ジャーナル,心拍,同期,ノート,歩数計,"
                "データ,手帳,血糖,HRV,VO2,体脂肪,BMI,栄養,呼吸,ウェルネス,記録,分析",
            ),
            (
                "ko", 220,
                "수면,웰니스,피트니스,체중관리,혈압,운동,칼로리,심박,일지,Obsidian,동기화,노트,만보기,체온,혈당,"
                "데이터,앱,HRV,BMI,체지방,영양,호흡,산소,바이탈,저널,다이어트,추적",
            ),
            (
                "ko", 213,
                "건강데이터,백업,건강일지,CSV,JSON,PDF,Obsidian,리포트,보고서,애플헬스,건강앱,단축어,Mac,동기화,"
                "로컬,개인정보,의사,진료,헬스데이터,마크다운,엑셀,아이클라우드",
            ),
            (
                "zh-Hans", 204,
                "睡眠,健身,体重,血压,运动,卡路里,心率,同步,笔记,计步,体温,血糖,数据,追踪,体脂,HRV,BMI,营养,呼吸,"
                "血氧,手环,手表,减肥,记录,养生,Apple,Watch,日志,分析,报告",
            ),
            (
                "zh-Hans", 174,
                "健康数据,备份,Obsidian,CSV,JSON,PDF,本地,隐私,快捷指令,Mac同步,医生,就诊,归档,数据迁移,健康报告,"
                "数据库,表格,YAML,Bases,CLI,iCloud,文件夹",
            ),
        )
        for locale, byte_count, keywords in cases:
            with self.subTest(locale=locale, keywords=keywords):
                self.assertLessEqual(len(keywords), 100)
                self.assertEqual(
                    run_against(keyword_tree(locale, keywords)),
                    (1, [f"version/3.4.1/{locale}: keywords are {byte_count} UTF-8 bytes (limit 100)"]),
                )

    def test_multibyte_visible_fields_keep_character_limits(self) -> None:
        self.assertEqual(
            run_against({"app-info/en-US.json": app_info("名" * 30, "日" * 30)}),
            (0, []),
        )
        self.assertEqual(
            run_against({"app-info/en-US.json": app_info("名" * 31, "日" * 31)}),
            (
                1,
                [
                    "app-info/en-US: name is 31 chars (limit 30)",
                    "app-info/en-US: subtitle is 31 chars (limit 30)",
                ],
            ),
        )

    def test_over_limit_keywords_fail(self) -> None:
        keywords = ",".join(["abcdefghij"] * 10)  # 109 ASCII bytes
        rc, errors = run_against(
            {
                "app-info/en-US.json": VALID_APP_INFO,
                "version/3.0.6/en-US.json": version_file(keywords),
            }
        )
        self.assertEqual(rc, 1)
        self.assertTrue(any("109 UTF-8 bytes" in e for e in errors))

    def test_space_after_comma_fails(self) -> None:
        rc, errors = run_against(
            {
                "app-info/en-US.json": VALID_APP_INFO,
                "version/3.0.6/en-US.json": version_file("obsidian, hrv"),
            }
        )
        self.assertEqual(rc, 1)
        self.assertTrue(any("space after a comma" in e for e in errors))

    def test_duplicate_term_fails(self) -> None:
        rc, errors = run_against(
            {
                "app-info/en-US.json": VALID_APP_INFO,
                "version/3.0.6/en-US.json": version_file("obsidian,OBSIDIAN,hrv"),
            }
        )
        self.assertEqual(rc, 1)
        self.assertTrue(any("duplicate keyword term" in e for e in errors))

    def test_exact_visible_token_duplicate_fails(self) -> None:
        rc, errors = run_against(
            {
                "app-info/en-US.json": app_info("Health.md", "Daily Health Journal & Export"),
                "version/3.0.6/en-US.json": version_file("obsidian,journal,hrv"),
            }
        )
        self.assertEqual(rc, 1)
        self.assertTrue(any("visible name/subtitle token" in e for e in errors))

    def test_clean_checkout_without_version_dir_passes(self) -> None:
        rc, errors = run_against({"app-info/en-US.json": VALID_APP_INFO})
        self.assertEqual((rc, errors), (0, []))


if __name__ == "__main__":
    unittest.main()
