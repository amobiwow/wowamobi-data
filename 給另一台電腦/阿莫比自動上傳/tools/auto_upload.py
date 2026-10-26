#!/usr/bin/env python3
"""
阿莫比自動上傳（老闆 10/24：「在我電腦上新增「阿莫比自動上傳」排程工作，拍賣場和普查都自動上傳；
普查照規則（完整輪、兩個陣營輪數一樣），對不上就先不傳、記在紀錄裡」）。

Windows 排程「阿莫比自動上傳」每 10 分鐘（和登入 Windows 時）用 pythonw 跑一次這支，不會跳出視窗：
  1. 找這台電腦上的 AmobiAuction.lua、DenizensTW.lua、AmobiLoot.lua、AmobiGuild.lua 存檔（_forever_ 和 _classic_beta_ 的每個帳號；
     遊戲資料夾見 upload_auction.game_dir）。遊戲只在登出、/reload、關遊戲時寫存檔，這支不知道你按了什麼，
     只看存檔有沒有被寫過。
  2. 存檔內容有變、而且已經 2 分鐘沒再寫入（遊戲寫完了）才處理；大小和修改時間沒變就連內容都不讀、
     也不寫硬碟，每次約 0.1 秒就結束（排程優先順序是「低於一般」，玩遊戲時遊戲先用 CPU）。
  3. 拍賣場：備份 → tools/amobi_auction.py 彙整 → site/scripts/upload-auction.mjs 上傳（和雙擊 上傳拍賣場物價.bat 一樣）。
  4. 普查：site/scripts/census-plan.mjs 算出「上傳之後」首頁開服那一段兩個陣營各幾輪完整普查
     （＝首頁「累計撈 N 次」）。兩邊一樣才備份、用 upload-census.mjs --phase=live 上傳彙總，再傳深度數據；
     不一樣就先不傳，寫進紀錄（存檔之後又有變才會再算一次）。
     11/5 07:00 開服前的封測、壓測已經結束（老闆 10/24：「封測跟壓測都不用在管了」），存檔裡有也不傳。
     「只算完整普查內看到的角色」（inRounds）是上傳程式本來就有的規則；做到一半登出的輪插件不會記。
     網站上同一個伺服器＋陣營有這台存檔沒有的輪（另一台電腦傳的）也不傳：網站是整份換掉，會蓋掉那些輪。
  5. 首領掉落（AmobiLoot，老闆 10/24：「副本掉落要不要一起撈」）：site/scripts/upload-loot.mjs 用站長金鑰上傳開服後的擊殺，
     和玩家在 /report 上傳的是同一個 /api/loot（同一場只算一次）。
     拍賣場、掉落也讀 AmobiGuild.lua（1.6.0）：公會成員的小幫手用插件訊息傳給站長角色的。拍賣場和自己掃的一起彙整；
     掉落算那個人回報的（網站要兩個人回報過才列），名字只送加密後的代號。
  6. 公會名單（阿莫比公會名單插件 AmobiGuild，只裝在老闆的電腦；老闆 10/25：競拍場開單限公會成員）：site/scripts/upload-roster.mjs
     把開服後讀到的聯盟公會名單加密（.env 的 ROSTER_KEY）後上傳；名單和上次傳的一樣就不傳。名字不出這台電腦。
  7. 榮譽擊殺（老闆 10/26，只針對阿莫比所在的亞服 PvP 規則聯盟）：小幫手 1.7.0 的聯盟角色用密語插件訊息傳給站長角色、
     AmobiGuild 收進存檔的（inbox 裡 H1 開頭的），site/scripts/upload-pvp.mjs 每個回報的人分開上傳到 /api/pvp；
     網站合併同一個擊殺的多人回報。開服前的不傳。
  8. 做了什麼都寫進 資料\\自動上傳\\紀錄.txt；上傳失敗（沒網路……）下一輪再試，同樣的錯誤一小時只記一次。
普查本身（按鍵查詢）不會自動：不掛機。上傳金鑰由 site\\scripts 的上傳程式讀 .env，這支只看有沒有、不讀值、不印。

另一台電腦：python tools/build_auto_upload_kit.py 做安裝包，那台雙擊 安裝自動上傳.bat（會跑 --setup）。

用法：
  python tools/auto_upload.py              跑一次（排程就是跑這個）
  python tools/auto_upload.py --dry-run    只檢查、印出會做什麼：不備份、不上傳、不寫紀錄和狀態
  python tools/auto_upload.py --install    新增（或更新）Windows 排程「阿莫比自動上傳」
  python tools/auto_upload.py --uninstall  刪掉排程（存檔、備份、紀錄都不動）
  python tools/auto_upload.py --setup [--game=<遊戲資料夾>] [--yes] [--skip-task]
                                           設定這台電腦：找遊戲資料夾、裝插件、檢查金鑰、新增排程、試跑一次
"""
from __future__ import annotations

import base64
import contextlib
import hashlib
import io
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import traceback
import zipfile
from datetime import datetime, timedelta, timezone

ROOT = pathlib.Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
DIR = ROOT / "資料" / "自動上傳"
LOG = DIR / "紀錄.txt"
STATE = DIR / "狀態.json"
BACKUP = DIR / "存檔備份"
AUCTION_OUT = ROOT / "資料" / "拍賣場"
TASK = "阿莫比自動上傳"
TW = timezone(timedelta(hours=8))
STABLE_SECS = 120          # 存檔 2 分鐘沒再寫入才算寫完
REPEAT_ERROR_SECS = 3600   # 同樣的錯誤一小時只記一次
LOG_MAX = 5 * 1024 * 1024  # 紀錄超過 5 MB 就改名成 紀錄-<日期>.txt，重開一份
PHASE_ZH = {"beta": "封測", "live": "開服"}
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)
sys.path.insert(0, str(ROOT / "tools"))

from upload_auction import describe, find_saves  # noqa: E402


class Retry(Exception):
    """這次沒做成，下一輪再試（訊息會寫進紀錄）。"""


def now_tw() -> datetime:
    return datetime.now(TW)


class Log:
    def __init__(self, dry: bool):
        self.dry = dry

    def __call__(self, text: str) -> None:
        stamp = now_tw().strftime("%m/%d %H:%M")
        lines = text.rstrip("\n").split("\n")
        out = "".join(f"{stamp}  {lines[0]}\n" if i == 0 else f"{'':11}  {ln}\n" for i, ln in enumerate(lines))
        if self.dry:
            print(out, end="")
            return
        DIR.mkdir(parents=True, exist_ok=True)
        if LOG.exists() and LOG.stat().st_size > LOG_MAX:
            LOG.rename(LOG.with_name(f"紀錄-{now_tw().strftime('%Y%m%d-%H%M%S')}.txt"))
        with open(LOG, "a", encoding="utf-8", newline="\r\n") as f:
            f.write(out)


def load_state() -> dict:
    try:
        return json.loads(STATE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def save_state(state: dict) -> None:
    DIR.mkdir(parents=True, exist_ok=True)
    tmp = STATE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, ensure_ascii=False, indent=1), encoding="utf-8")
    os.replace(tmp, STATE)


def digest(files: list[pathlib.Path]) -> str:
    h = hashlib.sha256()
    for f in files:
        h.update(str(f).encode("utf-8") + b"\0" + f.read_bytes() + b"\0")
    return h.hexdigest()


def env_keys() -> set[str]:
    """.env 裡有填值的鍵名（只看名字，不讀出值）。"""
    try:
        text = (ROOT / ".env").read_text(encoding="utf-8")
    except OSError:
        return set()
    return set(re.findall(r"^([A-Z][A-Z0-9_]*)=[ \t]*\S", text, re.M))


def node() -> str:
    return shutil.which("node") or r"C:\Program Files\nodejs\node.exe"


def run_node(script: str, *args: str) -> tuple[int, str]:
    r = subprocess.run([node(), str(SITE / "scripts" / script), *args], cwd=SITE, capture_output=True,
                       creationflags=NO_WINDOW, timeout=1200)
    out = (r.stdout + r.stderr).decode("utf-8", errors="replace").replace("\r", "\n")
    return r.returncode, "\n".join(ln.rstrip() for ln in out.split("\n") if ln.strip())


def indent(text: str, limit: int = 40) -> str:
    lines = text.split("\n")
    if len(lines) > limit:
        lines = lines[:limit] + [f"…（還有 {len(lines) - limit} 行）"]
    return "\n".join("  " + ln for ln in lines if ln)


def backup(files: list[pathlib.Path], kind: str) -> pathlib.Path:
    BACKUP.mkdir(parents=True, exist_ok=True)
    stamp = now_tw().strftime('%Y%m%d-%H%M%S')
    dest, n = BACKUP / f"{stamp}-{kind}.zip", 1
    while dest.exists():
        n += 1
        dest = BACKUP / f"{stamp}-{kind}-{n}.zip"
    with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as z:
        for i, f in enumerate(files):
            z.write(f, f"{i + 1}-{f.parents[4].name.strip('_')}-{f.parents[1].name.replace('#', '-')}-{f.name}")
    return dest


def rel(p: pathlib.Path) -> str:
    try:
        return str(p.relative_to(ROOT))
    except ValueError:
        return str(p)


def note(st: dict, log: Log, dry: bool, text: str) -> None:
    """「這次沒東西可傳」這類說明：和上次記的一樣就不再記。"""
    if dry or st.get("note") != text:
        log(text)
        st["note"] = text


# ---------------------------------------------------------------------------
# 拍賣場
# ---------------------------------------------------------------------------

def do_auction(files: list[pathlib.Path], st: dict, log: Log, dry: bool) -> None:
    import amobi_auction
    out_dir = pathlib.Path(tempfile.mkdtemp(prefix="amobi-ah-")) if dry else AUCTION_OUT
    upload = out_dir / "upload.json"
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
            res = amobi_auction.main([str(f) for f in files] + ["--out", str(out_dir), "--json", str(upload)])
    except SystemExit as e:
        raise Retry(f"拍賣場：彙整存檔失敗（{e}）\n{indent(buf.getvalue().strip())}")
    if not res or not res.get("days"):
        note(st, log, dry, "拍賣場：存檔有更新，但裡面還沒有可以上傳的價格（打開拍賣場掃描完、/reload 或登出後才會有）。")
        return
    # 每次登出遊戲都會重寫存檔；彙整出來和上次傳的一模一樣就不用再傳（也不用再備份）
    data = json.loads(upload.read_text(encoding="utf-8"))
    sig = hashlib.sha256(json.dumps([data.get("scans"), data.get("days")], sort_keys=True).encode("utf-8")).hexdigest()
    if sig == st.get("uploaded"):
        if dry:
            print("拍賣場：存檔重寫過，但價格和上次上傳的一樣，不用傳。")
        return
    head = "拍賣場：存檔有更新（" + "；".join(describe(f) for f in files) + "）"
    if dry:
        code, out = run_node("upload-auction.mjs", str(upload), "--dry-run")
        log(f"{head}\n  （試跑）會上傳：\n{indent(out)}")
        return
    if st.get("backup") != st.get("pending"):
        dest = backup(files, "拍賣場")
        st["backup"] = st["pending"]
        head += f"\n  已備份：{rel(dest)}"
    code, out = run_node("upload-auction.mjs", str(upload))
    if code != 0:
        raise Retry(f"拍賣場：上傳沒有成功，下一輪再試。\n{indent(out)}")
    st["uploaded"] = sig
    log(f"{head}\n{indent(out)}\n  報告：{rel(AUCTION_OUT / '報告.md')}")


# ---------------------------------------------------------------------------
# 普查
# ---------------------------------------------------------------------------

FZ = {"Alliance": "聯盟", "Horde": "部落"}
WAIT = DIR / "等待公開"   # 送到網站等待區的那份存檔：公開後拿它傳深度數據，輪數才會和公開的一樣


def census_decide(plan: dict) -> tuple[list[str], list[tuple[str, str]]]:
    """哪幾段要送到網站、哪幾段不送（回傳要寫進紀錄的話）。存檔和網站一樣、或已經在等待區的段落兩邊都不列。
    兩個陣營輪數一不一樣交給網站判斷：送到等待區，兩邊都有一樣輪數的版本時網站才一起公開
    （老闆 10/24：「一台電腦會是部落，一台會是聯盟」，一台電腦只看得到自己的陣營）。
    封測、壓測已經結束（老闆 10/24：「封測跟壓測都不用在管了」）：11/5 07:00 開服前的段落一律不傳，只記一次。"""
    todo, notes = [], []
    for ph in plan.get("phases", []):
        if not ph.get("changed"):
            continue
        if ph["phase"] != "live":
            notes.append((ph["phase"], "普查：存檔裡 11/5 開服前的資料（封測、壓測）已經結束，不上傳；只傳 11/5 07:00 開服後的普查。"))
            continue
        name = PHASE_ZH.get(ph["phase"], ph["phase"])
        # 網站上有這台存檔沒有的輪（另一台電腦傳的同一個陣營）：網站是整份換掉、不是相加，傳了會蓋掉那些輪
        other = [s for s in ph["slices"] if s.get("foreign")]
        if other:
            rows = "；".join(f"{s['realm']} {FZ[s['faction']]}有 {s['foreign']} 輪" for s in other)
            notes.append((ph["phase"], f"普查（{name}）：網站上 {rows}是這台電腦的存檔裡沒有的（應該是另一台電腦傳的）。"
                         "網站上每個伺服器＋陣營是整份換掉、不是相加，這台傳上去會把那些蓋掉，所以先不傳。\n"
                         "  同一個伺服器的同一個陣營，請固定在同一台電腦普查。"))
            continue
        todo.append(ph["phase"])
    return todo, notes


def waiting_text(realm: str, status: dict) -> str:
    """網站上這個伺服器公開的輪數和等待區的版本（寫進紀錄用）。"""
    pub = {p["faction"]: p["rounds"] for p in status.get("site", []) if p["phase"] == "live" and p["realm"] == realm}
    stg: dict[str, list[int]] = {}
    for s in status.get("staged", []):
        if s["phase"] == "live" and s["realm"] == realm:
            stg.setdefault(s["faction"], []).append(s["rounds"])
    shown = "、".join(f"{FZ[f]} {pub[f]} 輪" if f in pub else f"{FZ[f]}還沒有" for f in FZ)
    wait = "、".join(f"{FZ[f]} " + "、".join(map(str, sorted(stg[f]))) + " 輪" if f in stg else f"{FZ[f]}沒有" for f in FZ)
    return f"網站上公開的：{shown}；等待區：{wait}"


def last_json(out: str):
    try:
        return json.loads(out.split("\n")[-1])
    except ValueError:
        return None


def do_census(files: list[pathlib.Path], st: dict, log: Log, dry: bool) -> None:
    code, out = run_node("census-plan.mjs", *map(str, files))
    if code != 0:
        raise Retry(f"普查：讀不到網站上現在的普查資料，下一輪再試。\n{indent(out)}")
    plan = last_json(out)
    if plan is None:
        raise Retry(f"普查：檢查程式的結果看不懂，下一輪再試。\n{indent(out)}")
    todo, notes = census_decide(plan)
    # 同一段「不傳」的原因和上次記的一樣就不再記（例如開服後，封測那段一直都在）
    seen = st.setdefault("notes", {})
    for phase, n in notes:
        if dry or seen.get(phase) != n:
            log(n)
            seen[phase] = n
    if not todo:
        return
    if dry:
        for phase in todo:
            _, out = run_node("upload-census.mjs", *map(str, files), f"--phase={phase}", "--dry-run")
            log(f"普查（{PHASE_ZH[phase]}）：（試跑）會送到網站的等待區，兩個陣營都有一樣輪數的版本時網站會一起公開：\n{indent(out)}")
        return
    if st.get("backup") != st["pending"]:
        st["backupPath"], st["backup"] = rel(backup(files, "普查")), st["pending"]
    keep = WAIT / now_tw().strftime("%Y%m%d-%H%M%S")
    n = 1
    while keep.exists():
        n += 1
        keep = WAIT / f"{now_tw().strftime('%Y%m%d-%H%M%S')}-{n}"
    keep.mkdir(parents=True)
    for i, f in enumerate(files):
        shutil.copy2(f, keep / f"{i + 1}-{f.name}")
    status = None
    for phase in todo:
        name = PHASE_ZH[phase]
        code, out = run_node("upload-census.mjs", *map(str, files), f"--phase={phase}", "--stage", "--no-insights", "--json")
        res = last_json(out) if code == 0 else None
        if res is None:
            if not any(w["dir"] == rel(keep) for w in st.get("waiting", [])):
                shutil.rmtree(keep, ignore_errors=True)
            raise Retry(f"普查（{name}）：送到網站沒有成功，下一輪再試。\n{indent(out)}")
        status = res
        waiting = st.setdefault("waiting", [])
        sent = [r for r in res.get("results", []) if r.get("action") == "staged"]
        for r in sent:
            waiting[:] = [w for w in waiting if not (w["realm"] == r["realm"] and w["faction"] == r["faction"] and w["rounds"] == r["rounds"])]
            waiting.append({"realm": r["realm"], "faction": r["faction"], "rounds": r["rounds"], "snapshot": r["snapshot"], "dir": rel(keep)})
        if not sent:
            continue
        lines = []
        for realm in sorted({r["realm"] for r in sent}):
            done = [p for p in res.get("moved", []) if p["realm"] == realm]
            if done:
                lines.append(f"{realm}：兩個陣營都有 {done[0]['rounds']} 輪了，網站已經一起公開。")
            else:
                lines.append(f"{realm}：放在網站的等待區，還沒公開。{waiting_text(realm, res)}。\n"
                             "  兩個陣營都有一樣輪數的版本時（另一台電腦登出或 /reload 後也會送來），網站會一起公開，深度數據接著自動傳。")
        log(f"普查（{name}）：送出 " + "、".join(f"{FZ[r['faction']]} {r['rounds']} 輪" for r in sent)
            + "（" + "；".join(describe(f) for f in files) + f"）\n  已備份：{st.get('backupPath', '')}\n  " + "\n  ".join(lines))
    save_state_hook()
    if not any(w["dir"] == rel(keep) for w in st.get("waiting", [])):
        shutil.rmtree(keep, ignore_errors=True)
    census_followup(st, log, dry, status)   # 剛好一起公開的話，馬上傳深度數據


def census_followup(st: dict, log: Log, dry: bool, status: dict | None = None) -> None:
    """等待區裡這台送的版本公開了沒（可能是另一台電腦送來另一個陣營之後才公開）：公開了就用送出去的那份存檔傳深度數據；
    被更新的版本取代了就不用傳。等待中每一輪都會問一次網站（很小的請求）。"""
    if not st.get("waiting"):
        return
    if not status or "site" not in status:
        code, out = run_node("census-plan.mjs", "--status")
        status = last_json(out) if code == 0 else None
        if status is None:
            raise Retry(f"普查：讀不到網站的等待區，下一輪再試。\n{indent(out)}")
    pub = {(p["realm"], p["faction"]): p for p in status.get("site", []) if p["phase"] == "live"}
    staged = {(s["realm"], s["faction"], s["rounds"]) for s in status.get("staged", []) if s["phase"] == "live"}
    for w in list(st["waiting"]):
        p = pub.get((w["realm"], w["faction"]))
        if p and p["snapshot"] == w["snapshot"]:
            if dry:
                print(f"普查：{w['realm']} {FZ[w['faction']]} {w['rounds']} 輪已經公開，會傳深度數據。")
                continue
            saves = sorted((ROOT / w["dir"]).glob("*.lua"))
            code, out = run_node("upload-insights.mjs", *map(str, saves), "--phase=live", f"--only={w['faction']}")
            if code != 0:
                raise Retry(f"普查（開服）：網站已經公開 {w['realm']} {FZ[w['faction']]} {w['rounds']} 輪，"
                            f"但深度數據上傳沒有成功，下一輪再試。\n{indent(out)}")
            st["waiting"].remove(w)
            save_state_hook()
            log(f"普查（開服）：網站已經把 {w['realm']} 兩個陣營 {w['rounds']} 輪一起公開，{FZ[w['faction']]}的深度數據已上傳。\n{indent(out, 20)}")
        elif (w["realm"], w["faction"], w["rounds"]) not in staged and not dry:
            st["waiting"].remove(w)   # 被更新的版本取代了（公開的輪數比較多，或等待區沒有這個版本了）
    if dry:
        return
    used = {w["dir"] for w in st["waiting"]}
    if WAIT.exists():
        for d in WAIT.iterdir():
            if d.is_dir() and rel(d) not in used:
                shutil.rmtree(d, ignore_errors=True)
    if not st["waiting"]:
        st.pop("waiting", None)


# 普查送出去、深度數據傳好就先存狀態，下一輪失敗重試時不會重做已經好的部分
save_state_hook = lambda: None  # noqa: E731


# ---------------------------------------------------------------------------
# 首領掉落（AmobiLoot）
# ---------------------------------------------------------------------------

def do_loot(files: list[pathlib.Path], st: dict, log: Log, dry: bool) -> None:
    code, out = run_node("upload-loot.mjs", *map(str, files), "--dry-run")
    if code != 0:
        raise Retry(f"掉落：讀存檔失敗，下一輪再試。\n{indent(out)}")
    lines = out.split("\n")
    try:
        info = json.loads(lines[-1])
    except ValueError:
        raise Retry(f"掉落：檢查程式的結果看不懂，下一輪再試。\n{indent(out)}")
    summary = "\n".join(lines[:-1])
    if not info.get("kills"):
        note(st, log, dry, "掉落：存檔有更新，但沒有 11/5 開服後的首領擊殺可以上傳（開服前的封測、壓測不傳）。")
        return
    if info.get("sig") == st.get("uploaded"):
        if dry:
            print("掉落：存檔重寫過，但首領擊殺和上次上傳的一樣，不用傳。")
        return
    head = "掉落：存檔有新的首領擊殺（" + "；".join(describe(f) for f in files) + "）"
    if dry:
        log(f"{head}\n  （試跑）會上傳：\n{indent(summary)}")
        return
    if st.get("backup") != st.get("pending"):
        dest = backup(files, "掉落")
        st["backup"] = st["pending"]
        head += f"\n  已備份：{rel(dest)}"
    code, out = run_node("upload-loot.mjs", *map(str, files))
    if code != 0:
        raise Retry(f"掉落：上傳沒有成功，下一輪再試。\n{indent(out)}")
    st["uploaded"] = info.get("sig")
    st.pop("note", None)
    log(f"{head}\n{indent(out)}")


# ---------------------------------------------------------------------------
# 榮譽擊殺（AmobiGuild 收的小幫手 H1 資料；亞服 PvP 聯盟限定）
# ---------------------------------------------------------------------------

def do_pvp(files: list[pathlib.Path], st: dict, log: Log, dry: bool) -> None:
    code, out = run_node("upload-pvp.mjs", *map(str, files), "--dry-run")
    if code != 0:
        raise Retry(f"榮譽擊殺：讀存檔失敗，下一輪再試。\n{indent(out)}")
    lines = out.split("\n")
    try:
        info = json.loads(lines[-1])
    except ValueError:
        raise Retry(f"榮譽擊殺：檢查程式的結果看不懂，下一輪再試。\n{indent(out)}")
    summary = "\n".join(lines[:-1])
    if not info.get("kills"):
        return                                            # 沒有開服後的榮譽擊殺（大部分時候）：不記
    if info.get("sig") == st.get("uploaded"):
        return
    head = f"榮譽擊殺：小幫手傳來新的回報（{info.get('people', 0)} 個人）"
    if dry:
        log(f"{head}\n  （試跑）會上傳：\n{indent(summary)}")
        return
    code, out = run_node("upload-pvp.mjs", *map(str, files))
    if code != 0:
        raise Retry(f"榮譽擊殺：上傳沒有成功，下一輪再試。\n{indent(out)}")
    st["uploaded"] = info.get("sig")
    st.pop("note", None)
    log(f"{head}\n{indent(out)}")


# ---------------------------------------------------------------------------
# 公會名單（AmobiGuild，給競拍場開單）
# ---------------------------------------------------------------------------

def do_guild(files: list[pathlib.Path], st: dict, log: Log, dry: bool) -> None:
    # 存檔每次登出都會重寫（時間會變），先問名單本身有沒有變；不用備份（網站每次整份換掉）
    code, out = run_node("upload-roster.mjs", *map(str, files), "--dry-run")
    if code != 0:
        raise Retry(f"公會名單：讀存檔失敗，下一輪再試。\n{indent(out)}")
    lines = out.split("\n")
    try:
        info = json.loads(lines[-1])
    except ValueError:
        raise Retry(f"公會名單：檢查程式的結果看不懂，下一輪再試。\n{indent(out)}")
    if not info.get("guild"):
        note(st, log, dry, "公會名單：存檔有更新，但沒有 11/5 開服後讀到的公會名單（在公會裡的角色登入一次就會讀）。")
        return
    if info.get("sig") == st.get("uploaded"):
        if dry:
            print("公會名單：和上次上傳的一樣，不用傳。")
        return
    head = f"公會名單：「{info['guild']}」{info['members']} 人，和網站上的不一樣"
    if dry:
        log(f"{head}\n  （試跑）會上傳（只傳加密後的名字）。")
        return
    code, out = run_node("upload-roster.mjs", *map(str, files))
    if code != 0:
        raise Retry(f"公會名單：上傳沒有成功，下一輪再試。\n{indent(out)}")
    st["uploaded"] = info.get("sig")
    st.pop("note", None)
    log(f"{head}\n{indent(out)}")


# ---------------------------------------------------------------------------
# 每一輪
# ---------------------------------------------------------------------------

# (狀態裡的名字, 紀錄裡的名字, 存檔檔名, 怎麼處理, 要 .env 裡有哪些金鑰)
# 拍賣場、掉落也讀 AmobiGuild.lua：公會成員的小幫手用插件訊息傳來的（1.6.0，阿莫比公會名單插件收的）
JOBS = [("auction", "拍賣場", ("AmobiAuction.lua", "AmobiGuild.lua"), do_auction, ("UPLOAD_TOKEN",)),
        ("census", "普查", ("DenizensTW.lua",), do_census, ("UPLOAD_TOKEN", "INSIGHTS_SALT")),
        ("loot", "掉落", ("AmobiLoot.lua", "AmobiGuild.lua"), do_loot, ("UPLOAD_TOKEN",)),
        ("guild", "公會名單", ("AmobiGuild.lua",), do_guild, ("UPLOAD_TOKEN", "ROSTER_KEY")),
        ("pvp", "榮譽擊殺", ("AmobiGuild.lua",), do_pvp, ("UPLOAD_TOKEN",))]


def saves(names: tuple) -> list[pathlib.Path]:
    return sorted({f for n in names for f in find_saves(n)})


def report(st: dict, log: Log, now: float, msg: str) -> None:
    """錯誤寫進紀錄：同樣的錯誤一小時只記一次。"""
    if msg != st.get("error") or now - st.get("errorAt", 0) >= REPEAT_ERROR_SECS:
        log(msg)
        st["error"], st["errorAt"] = msg, now


def run_once(dry: bool) -> int:
    global save_state_hook
    log = Log(dry)
    state = load_state()
    state.pop("lastRun", None)
    before = json.dumps(state, sort_keys=True)
    if not dry:
        save_state_hook = lambda: save_state(state)  # noqa: E731
    now = time.time()
    today = now_tw().strftime("%Y-%m-%d")
    found = {key: saves(names) for key, _, names, _, _ in JOBS}
    if state.get("day") != today:
        parts = []
        for key, zh, _, _, _ in JOBS:
            fs = found[key]
            parts.append(f"{zh}存檔 " + ("、".join(describe(f).split("最後寫入 ")[-1] for f in fs) + " 寫入" if fs else "還沒有"))
        log("排程正常，今天第一次檢查（" + "；".join(parts) + "）。")
        state["day"] = today
    ran = set()
    for key, zh, _, handler, need in JOBS:
        files = found[key]
        if not files:
            continue
        st = state.setdefault(key, {})
        # 平常這裡就結束：存檔的大小和修改時間和上次一樣，連內容都不讀（每次檢查約 0.1 秒）
        stat = [[str(f), f.stat().st_size, f.stat().st_mtime_ns] for f in files]
        if stat == st.get("stat"):
            if dry:
                print(f"{zh}：存檔沒有動過，不用做。")
            continue
        newest = max(f.stat().st_mtime for f in files)
        if now - newest < STABLE_SECS:
            if dry:
                print(f"{zh}：存檔 {int(now - newest)} 秒前才寫入，等寫完（2 分鐘）下一輪再看。")
            continue
        try:
            h = digest(files)
        except OSError as e:
            log(f"{zh}：讀不到存檔（{e}），下一輪再試。")
            continue
        if h == st.get("hash"):
            st["stat"] = stat
            if dry:
                print(f"{zh}：存檔重寫過，內容和上次處理的一樣，不用做。")
            continue
        # 金鑰沒放好（例如另一台電腦少複製了 .env）：先不傳，記一次；補好之後下一輪就會傳。
        # 普查一定要有原本那組匿名代號密鑰，不然上傳程式會自己產生一組新的、代號全部對不起來
        missing = [k for k in need if k not in env_keys()]
        if missing:
            msg = (f"{zh}：{ROOT / '.env'} 裡沒有 {'、'.join(missing)}，先不上傳。"
                   "請從原本那台電腦的安裝包重新安裝（不要自己產生新的）。")
            if dry or st.get("envNote") != msg:
                log(msg)
                st["envNote"] = msg
            continue
        st.pop("envNote", None)
        st["pending"] = h
        ran.add(key)
        try:
            handler(files, st, log, dry)
        except Retry as e:
            report(st, log, now, str(e))
            continue
        except Exception:
            report(st, log, now, f"{zh}：程式出錯，下一輪再試。\n{indent(traceback.format_exc().strip(), 30)}")
            continue
        st["hash"], st["stat"], st["doneAt"] = h, stat, now_tw().isoformat(timespec="seconds")
        st.pop("error", None)
        st.pop("errorAt", None)
    # 普查還在網站的等待區（等另一台電腦送另一個陣營）：存檔沒變也要問一下公開了沒，公開了就傳深度數據
    cst = state.get("census", {})
    if cst.get("waiting") and "census" not in ran and {"UPLOAD_TOKEN", "INSIGHTS_SALT"} <= env_keys():
        try:
            census_followup(cst, log, dry)
        except Retry as e:
            report(cst, log, now, str(e))
        except Exception:
            report(cst, log, now, f"普查：程式出錯，下一輪再試。\n{indent(traceback.format_exc().strip(), 30)}")
    # 沒事的時候不寫硬碟（上次什麼時候跑看工作排程器的「上次執行時間」）
    if not dry and json.dumps(state, sort_keys=True) != before:
        save_state(state)
    return 0


@contextlib.contextmanager
def single_instance():
    """同一時間只跑一個（排程和手動同時跑的時候，後來的直接結束）。"""
    import msvcrt
    DIR.mkdir(parents=True, exist_ok=True)
    f = open(DIR / "執行中.lock", "a+b")
    f.seek(0)
    try:
        msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)
    except OSError:
        f.close()
        yield False
        return
    try:
        yield True
    finally:
        f.seek(0)
        msvcrt.locking(f.fileno(), msvcrt.LK_UNLCK, 1)
        f.close()


# ---------------------------------------------------------------------------
# Windows 排程
# ---------------------------------------------------------------------------

def powershell(script: str) -> subprocess.CompletedProcess:
    enc = base64.b64encode(script.encode("utf-16-le")).decode("ascii")
    return subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-EncodedCommand", enc],
                          capture_output=True, text=True, encoding="utf-8", errors="replace")


def install() -> int:
    pyw = pathlib.Path(sys.executable).with_name("pythonw.exe")
    if not pyw.exists():
        print(f"找不到 {pyw}")
        return 1
    me = pathlib.Path(__file__).resolve()
    ps = f"""
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$a = New-ScheduledTaskAction -Execute '{pyw}' -Argument '"{me}"' -WorkingDirectory '{ROOT}'
$t1 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 10)
$t2 = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\\$env:USERNAME"
$s = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
$p = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$d = '每 10 分鐘看一次遊戲存檔（拍賣場 AmobiAuction.lua、普查 DenizensTW.lua、掉落 AmobiLoot.lua、公會名單 AmobiGuild.lua），有新的就上傳到 wowamobi.com；紀錄在 {DIR}\\紀錄.txt'
Register-ScheduledTask -TaskName '{TASK}' -Action $a -Trigger $t1,$t2 -Settings $s -Principal $p -Description $d -Force | Out-Null
$t = Get-ScheduledTask -TaskName '{TASK}'
"OK " + $t.State + " | " + (($t.Triggers | ForEach-Object {{ $_.CimClass.CimClassName + ' ' + $_.Repetition.Interval + ' ' + $_.Repetition.Duration }}) -join ' ; ')
"""
    r = powershell(ps)
    print((r.stdout + r.stderr).strip())
    return 0 if r.returncode == 0 and "OK " in r.stdout else 1


def uninstall() -> int:
    r = powershell(f"$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'; Unregister-ScheduledTask -TaskName '{TASK}' -Confirm:$false; 'OK'")
    print((r.stdout + r.stderr).strip())
    return 0 if r.returncode == 0 else 1


def ask(question: str, yes: bool) -> str:
    if yes:
        return ""
    try:
        return input(question).strip()
    except EOFError:
        return ""


def setup(argv: list[str]) -> int:
    """設定這台電腦（另一台電腦的安裝包 安裝自動上傳.bat 會跑這個）：遊戲資料夾 → 插件 → 金鑰 → 排程 → 試跑。"""
    from upload_auction import SETTINGS, detect_game, is_game
    yes = "--yes" in argv
    print("阿莫比自動上傳：設定這台電腦\n")

    # 1. 遊戲資料夾
    given = next((a[7:].strip('"') for a in argv if a.startswith("--game=")), None)
    game = pathlib.Path(given) if given else detect_game()
    if game and is_game(game):
        print(f"遊戲資料夾：{game}")
    else:
        print(f"找不到遊戲資料夾{f'（{given} 裡面沒有 _forever_ 資料夾）' if given else ''}。")
        game = None
        while True:
            ans = ask("請貼上「World of Warcraft」資料夾的位置（例如 C:\\Program Files (x86)\\World of Warcraft），"
                      "直接按 Enter 先跳過：", yes).strip('"')
            if not ans:
                print("  先跳過：之後再雙擊一次 安裝自動上傳.bat 就可以設定。")
                break
            if is_game(pathlib.Path(ans)):
                game = pathlib.Path(ans)
                print(f"遊戲資料夾：{game}")
                break
            print(f"  {ans} 裡面沒有 _forever_ 資料夾，不是遊戲資料夾，請再確認一次。")
    if game:
        SETTINGS.parent.mkdir(parents=True, exist_ok=True)
        SETTINGS.write_text(json.dumps({"game": str(game)}, ensure_ascii=False, indent=1), encoding="utf-8")

    # 2. 插件（安裝包裡的 插件\ 資料夾）：裝進 _forever_\Interface\AddOns，存檔不會動
    addons = ROOT / "插件"
    if game and addons.is_dir():
        names = sorted(p.name for p in addons.iterdir() if p.is_dir())
        dest = game / "_forever_" / "Interface" / "AddOns"
        ans = ask(f"\n要把插件（{'、'.join(names)}）裝進遊戲嗎？已經有的會換成這一份，你的存檔和設定不會動。[Y/n]：", yes)
        if ans.lower() in ("", "y", "yes"):
            dest.mkdir(parents=True, exist_ok=True)
            for n in names:
                shutil.copytree(addons / n, dest / n, dirs_exist_ok=True)
            print(f"  插件裝好了：{dest}（遊戲開著的話要 /reload 或重開遊戲才會載入）")
    # 傷害字型（安裝包裡的 字型\bKAI00M.ttf，和這台裝的一樣）：放進 _forever_\Fonts，重開遊戲生效
    font = ROOT / "字型" / "bKAI00M.ttf"
    if game and font.exists():
        ans = ask("\n要裝阿莫比的傷害字型嗎？（打怪時跳出來的傷害數字換成這個字型，重開遊戲才會生效）[Y/n]：", yes)
        if ans.lower() in ("", "y", "yes"):
            fonts = game / "_forever_" / "Fonts"
            fonts.mkdir(parents=True, exist_ok=True)
            shutil.copy2(font, fonts / font.name)
            print(f"  傷害字型裝好了：{fonts / font.name}")

    # 3. 金鑰（只看有沒有，不印值）
    missing = [k for k in ("UPLOAD_TOKEN", "INSIGHTS_SALT", "ROSTER_KEY") if k not in env_keys()]
    if missing:
        print(f"\n注意：{ROOT / '.env'} 裡沒有 {'、'.join(missing)}，自動上傳會先停著。請用原本那台電腦做的安裝包重新安裝。")
    else:
        print("\n上傳金鑰：有")
    if not (shutil.which("node") or pathlib.Path(node()).exists()):
        print("注意：找不到 Node.js，上傳會失敗。請安裝 Node.js（https://nodejs.org，選 LTS）後再雙擊一次 安裝自動上傳.bat。")

    # 4. 排程
    if "--skip-task" not in argv:
        print("\n新增 Windows 排程「阿莫比自動上傳」…")
        if install() != 0:
            print("排程沒有建成功（上面有原因）。")
            return 1
        print("  好了：每 10 分鐘、還有登入 Windows 時看一次存檔。")

    # 5. 試跑一次給你看
    print("\n現在看到的存檔（試跑，不會上傳）：")
    with single_instance() as ok:
        if ok:
            run_once(True)
    print(f"\n設定好了。之後登出遊戲或 /reload，10 分鐘內會自動上傳。紀錄：{LOG}")
    return 0


def main(argv=None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if sys.stdout is not None:
        try:
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass
    if "--setup" in argv:
        return setup(argv)
    if "--install" in argv:
        return install()
    if "--uninstall" in argv:
        return uninstall()
    with single_instance() as ok:
        if not ok:
            if sys.stdout is not None:
                print("已經有一個在跑了。")
            return 0
        return run_once("--dry-run" in argv)


if __name__ == "__main__":
    sys.exit(main())
