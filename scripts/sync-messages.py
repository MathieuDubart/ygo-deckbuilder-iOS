#!/usr/bin/env python3
"""
Fusionne les traductions du front web (apps/web/messages/<langue>/<namespace>.json) et celles
propres à l'app iOS (Localization/ios.<langue>.json) en un fichier par langue :
ygo-deckbuilder-iOS/Resources/messages.<langue>.json (lu par L10n.swift).

Usage : python3 scripts/sync-messages.py [chemin/vers/ygo-deckbuilder/apps/web/messages]
Par défaut, le dépôt web est cherché à côté de celui-ci (../ygo-deckbuilder).
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCALES = ["en", "fr", "de", "it", "pt"]
web = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT.parent / "ygo-deckbuilder" / "apps" / "web" / "messages"
out_dir = ROOT / "ygo-deckbuilder-iOS" / "Resources"

if not web.is_dir():
    sys.exit(f"Messages du web introuvables : {web}")

out_dir.mkdir(parents=True, exist_ok=True)
for locale in LOCALES:
    merged = {}
    for file in sorted((web / locale).glob("*.json")):
        merged[file.stem] = json.loads(file.read_text(encoding="utf-8"))
    merged["ios"] = json.loads((ROOT / "Localization" / f"ios.{locale}.json").read_text(encoding="utf-8"))
    target = out_dir / f"messages.{locale}.json"
    target.write_text(json.dumps(merged, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    print(f"{target.relative_to(ROOT)} : {len(merged)} namespaces")
