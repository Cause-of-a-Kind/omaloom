#!/usr/bin/env python3
"""Keep every plugin Text surface immune to Qt rich-text auto-detection."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_all_qml_text_items_force_plain_text():
    for path in sorted((ROOT / "qml").glob("*.qml")):
        source = path.read_text(encoding="utf-8")
        text_items = source.count("Text {")
        plain_text_items = source.count("textFormat: Text.PlainText")
        assert plain_text_items == text_items, (
            f"{path.relative_to(ROOT)} has {text_items} Text items but "
            f"only {plain_text_items} plain-text declarations"
        )


if __name__ == "__main__":
    test_all_qml_text_items_force_plain_text()
    print("QML plain-text tests passed")
