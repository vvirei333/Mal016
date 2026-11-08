#!/usr/bin/env bash
# fetch_packs.sh — download tendies packs from the open SerStars/Nugget-Wallpapers catalog
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p packs
curl -sL "https://raw.githubusercontent.com/SerStars/Nugget-Wallpapers/main/wallpapers-custom.json" -o packs/custom.json
python3 - <<'PY'
import json, subprocess, os
d = json.load(open('packs/custom.json'))
for w in d:
    name = os.path.basename(w['url'])
    dst = os.path.join('packs', name)
    if os.path.exists(dst): continue
    url = f"https://raw.githubusercontent.com/SerStars/Nugget-Wallpapers/main/{w['url']}"
    subprocess.run(['curl','-sL',url,'-o',dst], check=True)
    print('[+] fetched', name)
PY
echo "[i] packs in packs/ — import with: Mal016 tendie import packs/<name>.tendies"
