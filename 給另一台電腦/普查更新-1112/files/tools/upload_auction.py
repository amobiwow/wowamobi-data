#!/usr/bin/env python3
"""
拍賣場物價一鍵上傳（老闆 10/24：「雙擊上傳工具」）。雙擊 D:\\魔獸網站\\上傳拍賣場物價.bat 就會跑這支：
  1. 找到這台電腦上所有的 AmobiAuction.lua 存檔（_forever_ 和 _classic_beta_ 的每個帳號）
  2. 先複製一份到 資料\\拍賣場\\存檔備份\\<日期時間>\\（插件只留 45 天、200 次，舊的備份在這裡；資料\\ 不進 git）
  3. tools\\amobi_auction.py 彙整成 資料\\拍賣場\\upload.json 和 報告.md
  4. site\\scripts\\upload-auction.mjs 上傳到 wowamobi.com（金鑰讀 D:\\魔獸網站\\.env 的 UPLOAD_TOKEN，不會印出來）
遊戲還開著的時候提醒一下：存檔要 /reload 或登出才會寫進電腦。
用法：python tools/upload_auction.py [--dry-run]（--dry-run 只彙整、不上傳）
"""
from __future__ import annotations

import glob
import json
import os
import pathlib
import shutil
import subprocess
import sys
from datetime import datetime, timedelta, timezone

ROOT = pathlib.Path(__file__).resolve().parent.parent
GAME = pathlib.Path(r"D:\World of Warcraft")
OUT = ROOT / "資料" / "拍賣場"
TW = timezone(timedelta(hours=8))
FLAVOR = {"_forever_": "正式服", "_classic_beta_": "封測"}
sys.path.insert(0, str(ROOT / "tools"))


def game_running() -> bool:
    try:
        out = subprocess.run(["tasklist"], capture_output=True, text=True, errors="replace").stdout
    except OSError:
        return False
    return any(name in out for name in ("Wow.exe", "WowB.exe", "WowT.exe"))


SETTINGS = ROOT / "資料" / "自動上傳" / "設定.json"   # 這台電腦的設定（遊戲資料夾）；tools/auto_upload.py --setup 寫


def is_game(p: pathlib.Path) -> bool:
    return any((p / flavor).is_dir() for flavor in FLAVOR)


def detect_game() -> pathlib.Path | None:
    """找遊戲資料夾（裡面有 _forever_ 或 _classic_beta_ 的那層）：先看預設的 D:\\World of Warcraft，再看 Battle.net 寫的
    安裝位置，最後看每個磁碟常見的位置。找不到回傳 None。另一台電腦裝在別的地方時用（老闆 10/24：另一台電腦也要自動上傳）。"""
    cands = [GAME]
    try:
        import winreg
        for hive, key in ((winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft"),
                          (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Blizzard Entertainment\World of Warcraft")):
            try:
                with winreg.OpenKey(hive, key) as k:
                    p = pathlib.Path(winreg.QueryValueEx(k, "InstallPath")[0])
                    cands += [p, p.parent]
            except OSError:
                pass
    except ImportError:
        pass
    for d in "CDEFGHIJ":
        if os.path.exists(f"{d}:\\"):
            cands += [pathlib.Path(f"{d}:\\") / sub for sub in (
                "World of Warcraft", r"Program Files (x86)\World of Warcraft", r"Program Files\World of Warcraft",
                r"Games\World of Warcraft", r"Battle.net\World of Warcraft", r"Blizzard\World of Warcraft")]
    for p in cands:
        try:
            if is_game(p):
                return p
        except OSError:
            continue
    return None


def game_dir() -> pathlib.Path:
    """設定檔寫的遊戲資料夾；沒寫（或不對）就自己找；都找不到用 D:\\World of Warcraft。"""
    try:
        p = pathlib.Path(json.loads(SETTINGS.read_text(encoding="utf-8"))["game"])
        if is_game(p):
            return p
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return detect_game() or GAME


def find_saves(filename: str = "AmobiAuction.lua") -> list[pathlib.Path]:
    """這台電腦上所有帳號的某個插件存檔（tools/auto_upload.py 也用這個找普查的 DenizensTW.lua、掉落的 AmobiLoot.lua）。"""
    game = game_dir()
    return sorted({pathlib.Path(p) for flavor in FLAVOR
                   for p in glob.glob(str(game / flavor / "WTF" / "Account" / "*" / "SavedVariables" / filename))})


def describe(f: pathlib.Path) -> str:
    t = datetime.fromtimestamp(f.stat().st_mtime, TW).strftime("%m/%d %H:%M")
    return f"{FLAVOR.get(f.parents[4].name, f.parents[4].name)}，帳號 {f.parents[1].name}，最後寫入 {t}"


def main(argv=None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    dry = "--dry-run" in argv
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    print("阿莫比 拍賣場物價上傳\n")
    files = find_saves()
    if not files:
        print("找不到 AmobiAuction.lua：先在遊戲裡打開拍賣場掃描，再 /reload 或登出。")
        return 1
    for f in files:
        print(f"  存檔：{describe(f)}")
    if game_running():
        print("\n遊戲還開著：存檔要在遊戲裡打 /reload（或登出）才會寫進電腦，沒做的話這次會傳到舊的資料。")
        if input("已經 /reload 過了嗎？要繼續就輸入 y 按 Enter：").strip().lower() != "y":
            print("先不上傳。")
            return 1

    stamp = datetime.now(TW).strftime("%Y%m%d-%H%M%S")
    backup = OUT / "存檔備份" / stamp
    backup.mkdir(parents=True, exist_ok=True)
    for i, f in enumerate(files):
        shutil.copy2(f, backup / f"{i + 1}-{f.parents[4].name.strip('_')}-{f.parents[1].name.replace('#', '-')}.lua")
    print(f"\n已備份存檔：{backup}\n")

    import amobi_auction
    res = amobi_auction.main([str(f) for f in files] + ["--out", str(OUT), "--json", str(OUT / "upload.json")])
    if not res or not res.get("days"):
        print("\n存檔裡還沒有可以上傳的價格（打開拍賣場掃描完，/reload 後再試）。")
        return 1
    if dry:
        print("\n只彙整、沒有上傳（--dry-run）。")
        return 0
    print("\n上傳到 wowamobi.com …")
    r = subprocess.run(["node", str(ROOT / "site" / "scripts" / "upload-auction.mjs"), str(OUT / "upload.json")], cwd=ROOT / "site")
    if r.returncode != 0:
        print("\n上傳沒有成功，畫面上面有原因；把這個視窗截圖給阿莫比。")
        return 1
    print(f"\n完成！物品頁和物價指數（wowamobi.com/market）最多 10 分鐘內會更新。報告：{OUT / '報告.md'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
