#!/usr/bin/env python3
"""
讀取 Denizens TW（或原版 Denizens）的 SavedVariables 存檔，輸出 JSON、CSV 和一份中文報告。

用法：
    python tools/parse_denizens.py <DenizensTW.lua> [更多存檔...] [--out 輸出資料夾]

- 多個存檔會依「伺服器 + 陣營 + 角色名」合併去重（不同玩家交來的資料可以一起丟）。
- 不執行任何 Lua：檔案只當資料解析，只接受 WoW 存檔會寫出的 Lua 子集
  （表格、字串、數字、true/false/nil、註解）。
- 只用 Python 標準函式庫。
"""
from __future__ import annotations

import argparse
import csv
import json
import pathlib
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

TW = timezone(timedelta(hours=8))
ACTIVE_DAYS = 7


# ---------------------------------------------------------------------------
# Lua 資料解析（SavedVariables 子集）
# ---------------------------------------------------------------------------

class LuaSyntaxError(ValueError):
    pass


TOKEN_RE = re.compile(rb"""
    (?P<ws>[ \t\r\n]+)
  | (?P<lcomment>--\[(?P<lceq>=*)\[[\s\S]*?\](?P=lceq)\])
  | (?P<comment>--[^\n]*)
  | (?P<lstring>\[(?P<lseq>=*)\[[\s\S]*?\](?P=lseq)\])
  | (?P<dstring>"(?:[^"\\\n]|\\[\s\S])*")
  | (?P<sstring>'(?:[^'\\\n]|\\[\s\S])*')
  | (?P<number>0[xX][0-9a-fA-F]+(?:\.[0-9a-fA-F]*)?(?:[pP][+-]?[0-9]+)?|(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<punct>[{}\[\]=,;\-])
""", re.VERBOSE)

ESC_RE = re.compile(rb"""\\(?:(?P<simple>[abfnrtv\\"'])|(?P<nl>\r\n|\n\r|\n|\r)|(?P<dec>[0-9]{1,3})|x(?P<hex>[0-9a-fA-F]{2})|(?P<z>z\s*)|u\{(?P<u>[0-9a-fA-F]+)\})""")
SIMPLE_ESC = {b"a": b"\a", b"b": b"\b", b"f": b"\f", b"n": b"\n", b"r": b"\r", b"t": b"\t",
              b"v": b"\v", b"\\": b"\\", b'"': b'"', b"'": b"'"}


def _unescape(raw: bytes) -> str:
    if b"\\" not in raw:
        return raw.decode("utf-8", "replace")

    def rep(m):
        if m.group("simple"):
            return SIMPLE_ESC[m.group("simple")]
        if m.group("nl") is not None:
            return b"\n"
        if m.group("dec"):
            v = int(m.group("dec"))
            if v > 255:
                raise LuaSyntaxError(f"跳脫字元超出範圍：\\{v}")
            return bytes([v])
        if m.group("hex"):
            return bytes([int(m.group("hex"), 16)])
        if m.group("z") is not None:
            return b""
        return chr(int(m.group("u"), 16)).encode("utf-8")

    return ESC_RE.sub(rep, raw).decode("utf-8", "replace")


def _number(text: str):
    t = text.lower()
    if t.startswith("0x"):
        if "." in t or "p" in t:
            return float.fromhex(t)
        return int(t, 16)
    if "." in t or "e" in t:
        return float(t)
    return int(t)


class _Parser:
    def __init__(self, data: bytes):
        self.data = data
        self.pos = 3 if data.startswith(b"\xef\xbb\xbf") else 0
        self.tok = self.nxt = None
        self._advance()
        self._advance()

    def _line(self, pos):
        return self.data.count(b"\n", 0, pos) + 1

    def _scan(self):
        data, n = self.data, len(self.data)
        while self.pos < n:
            m = TOKEN_RE.match(data, self.pos)
            if not m:
                line = self._line(self.pos)
                if data[self.pos:self.pos + 1] in (b'"', b"'"):
                    raise LuaSyntaxError(f"第 {line} 行：字串沒有結束（檔案可能不完整，例如遊戲當掉或複製到一半）")
                raise LuaSyntaxError(f"第 {line} 行：看不懂的字元 {data[self.pos:self.pos + 12]!r}")
            start, self.pos = self.pos, m.end()
            kind = m.lastgroup
            kind = {"lceq": "lcomment", "lseq": "lstring"}.get(kind, kind)
            if kind in ("ws", "comment", "lcomment"):
                continue
            text = m.group(0)
            if kind == "dstring" or kind == "sstring":
                return ("string", _unescape(text[1:-1]), start)
            if kind == "lstring":
                eq = len(re.match(rb"\[(=*)\[", text).group(1))
                body = text[2 + eq:-(2 + eq)]
                if body.startswith(b"\r\n"):
                    body = body[2:]
                elif body.startswith(b"\n"):
                    body = body[1:]
                return ("string", body.decode("utf-8", "replace"), start)
            if kind == "number":
                return ("number", _number(text.decode("ascii")), start)
            if kind == "name":
                return ("name", text.decode("ascii"), start)
            return ("punct", text.decode("ascii"), start)
        return ("eof", None, self.pos)

    def _advance(self):
        self.tok, self.nxt = self.nxt, self._scan()

    def _error(self, msg):
        raise LuaSyntaxError(f"第 {self._line(self.tok[2])} 行：{msg}")

    def _expect(self, value):
        if self.tok[0] != "punct" or self.tok[1] != value:
            self._error(f"這裡應該是「{value}」，卻看到 {self.tok[1]!r}")
        self._advance()

    def parse_file(self):
        out = {}
        while self.tok[0] != "eof":
            if self.tok[0] != "name":
                self._error(f"應該是變數名稱，卻看到 {self.tok[1]!r}")
            name = self.tok[1]
            self._advance()
            self._expect("=")
            out[name] = self.parse_value()
            if self.tok[0] == "punct" and self.tok[1] == ";":
                self._advance()
        return out

    def parse_value(self):
        kind, value, _ = self.tok
        if kind in ("number", "string"):
            self._advance()
            return value
        if kind == "name":
            if value in ("true", "false", "nil"):
                self._advance()
                return {"true": True, "false": False, "nil": None}[value]
            self._error(f"不支援的值：{value}")
        if kind == "punct" and value == "{":
            return self.parse_table()
        if kind == "punct" and value == "-":
            self._advance()
            if self.tok[0] != "number":
                self._error("負號後面應該是數字")
            v = -self.tok[1]
            self._advance()
            return v
        self._error(f"看不懂的值：{value!r}")

    def parse_table(self):
        self._expect("{")
        items, nexti = [], 1
        while not (self.tok[0] == "punct" and self.tok[1] == "}"):
            if self.tok[0] == "eof":
                self._error("表格沒有結束（檔案可能被截斷）")
            if self.tok[0] == "punct" and self.tok[1] == "[":
                self._advance()
                key = self.parse_value()
                self._expect("]")
                self._expect("=")
                val = self.parse_value()
            elif self.tok[0] == "name" and self.nxt[0] == "punct" and self.nxt[1] == "=":
                key = self.tok[1]
                self._advance()
                self._advance()
                val = self.parse_value()
            else:
                key, nexti = nexti, nexti + 1
                val = self.parse_value()
            items.append((key, val))
            if self.tok[0] == "punct" and self.tok[1] in (",", ";"):
                self._advance()
            elif not (self.tok[0] == "punct" and self.tok[1] == "}"):
                self._error("表格欄位之間少了逗號")
        self._advance()
        if items and all(isinstance(k, int) for k, _ in items) and \
                sorted(k for k, _ in items) == list(range(1, len(items) + 1)):
            return [v for _, v in sorted(items, key=lambda kv: kv[0])]
        table = {}
        for k, v in items:
            if v is not None:
                table[k] = v
        return table


def parse_savedvariables(data: bytes) -> dict:
    return _Parser(data).parse_file()


def as_list(x):
    if isinstance(x, list):
        return x
    if isinstance(x, dict):
        return [x[k] for k in sorted(x, key=lambda k: (not isinstance(k, int), k))]
    return []


# ---------------------------------------------------------------------------
# 名稱對照（客戶端語言 → 語言無關的代碼 → 繁中顯示名）
# ---------------------------------------------------------------------------

CLASS_ZH = {"WARRIOR": "戰士", "PALADIN": "聖騎士", "HUNTER": "獵人", "ROGUE": "盜賊", "PRIEST": "牧師",
            "SHAMAN": "薩滿", "MAGE": "法師", "WARLOCK": "術士", "DRUID": "德魯伊"}
CLASS_ALIASES = {
    "WARRIOR": ["Warrior", "戰士", "战士"], "PALADIN": ["Paladin", "聖騎士", "圣骑士"],
    "HUNTER": ["Hunter", "獵人", "猎人"], "ROGUE": ["Rogue", "盜賊", "盗贼", "潜行者"],
    "PRIEST": ["Priest", "牧師", "牧师"], "SHAMAN": ["Shaman", "薩滿", "萨满", "萨满祭司"],
    "MAGE": ["Mage", "法師", "法师"], "WARLOCK": ["Warlock", "術士", "术士"],
    "DRUID": ["Druid", "德魯伊", "德鲁伊"],
}
# Skyborne 的官方繁中譯名「天裔精靈」出自暴雪繁中新聞《魔獸世界：永恆》- 天裔精靈視覺更新的未來（2026-10-07）
RACE_ZH = {"HUMAN": "人類", "DWARF": "矮人", "NIGHTELF": "夜精靈", "GNOME": "地精", "ORC": "獸人",
           "UNDEAD": "不死族", "TAUREN": "牛頭人", "TROLL": "食人妖", "SKYBORNE": "天裔精靈"}
RACE_ALIASES = {
    "HUMAN": ["Human", "人類", "人类"], "DWARF": ["Dwarf", "矮人"],
    "NIGHTELF": ["Night Elf", "夜精靈", "暗夜精灵"],
    "GNOME": ["Gnome", "地精", "侏儒"],    # 繁中的「地精」= Gnome（簡中的地精是 Goblin，Forever 沒有 Goblin）
    "ORC": ["Orc", "獸人", "兽人"], "UNDEAD": ["Undead", "不死族", "亡灵"],
    "TAUREN": ["Tauren", "牛頭人", "牛头人"], "TROLL": ["Troll", "食人妖", "巨魔"],
}
FACTION_ZH = {"Alliance": "聯盟", "Horde": "部落"}

# 角色名稱語言：規則在 tools/name_lang.json，網站用同一份，兩邊數字才會一致。
NAME_RULES = json.loads(pathlib.Path(__file__).with_name("name_lang.json").read_text(encoding="utf-8"))
_NAME_SCRIPTS = [(code, [tuple(int(x, 16) for x in span.split("-")) for span in NAME_RULES["scripts"][code]])
                 for code in NAME_RULES["order"]]
_ZH_TRAD, _ZH_SIMP = set(NAME_RULES["zh_traditional_only"]), set(NAME_RULES["zh_simplified_only"])


def name_lang(name) -> str:
    """角色名用的是哪一種文字：ko、ja、zh_t、zh_s、zh_u、ru、th、latin、other。不是國籍。"""
    base = str(name or "").split("-", 1)[0]          # 跨伺服器角色是「角色名-伺服器」
    for code, spans in _NAME_SCRIPTS:
        if any(lo <= ord(ch) <= hi for ch in base for lo, hi in spans):
            if code != "zh":
                return code
            trad = any(ch in _ZH_TRAD for ch in base)
            simp = any(ch in _ZH_SIMP for ch in base)
            return "zh_t" if trad and not simp else "zh_s" if simp and not trad else "zh_u"
    return "other"
CLASS_LOOKUP = {a.casefold(): t for t, names in CLASS_ALIASES.items() for a in names}
RACE_LOOKUP = {a.casefold(): t for t, names in RACE_ALIASES.items() for a in names}


def map_class(raw: str, token: str | None):
    token = (token or "").upper()
    if token in CLASS_ZH:
        return token
    return CLASS_LOOKUP.get((raw or "").strip().casefold())


def map_race(raw: str):
    key = (raw or "").strip().casefold()
    if key in RACE_LOOKUP:
        return RACE_LOOKUP[key]
    # 兩個陣營各有一支（High Order / Windshaper），客戶端可能顯示全名或簡稱
    if "skyborne" in key or "天裔" in key:
        return "SKYBORNE"
    return None


# ---------------------------------------------------------------------------
# 擷取與合併
# ---------------------------------------------------------------------------

def tw_time(ts):
    if not isinstance(ts, (int, float)) or ts <= 0:
        return ""
    return datetime.fromtimestamp(ts, TW).strftime("%Y-%m-%d %H:%M")


def extract(sv: dict, source: str):
    if "DenizensTWDB" in sv:
        db, kind = sv["DenizensTWDB"], "DenizensTW"
    elif "DenizensDB" in sv:
        db, kind = sv["DenizensDB"], "Denizens"
    else:
        raise ValueError(f"{source}：找不到 DenizensTWDB 或 DenizensDB，這不是 Denizens 的存檔")
    if not isinstance(db, dict):
        raise ValueError(f"{source}：存檔內容不是表格")
    realms = db.get("realms") or {}
    client = db.get("client") if isinstance(db.get("client"), dict) else {}
    out = []
    for key, r in (realms.items() if isinstance(realms, dict) else []):
        if not isinstance(r, dict):
            continue
        realm, _, faction = str(key).rpartition(" - ")
        if not realm:
            realm, faction = str(key), ""
        players = []
        for name, p in (r.get("players") or {}).items():
            if not isinstance(p, dict):
                continue
            players.append({
                "realm": realm, "faction": faction, "name": str(name),
                "level": p.get("lvl"), "class_raw": p.get("class") or "", "token": p.get("token") or "",
                "race_raw": p.get("race") or "", "sex": p.get("sex"), "guild": p.get("guild") or "",
                "area": p.get("area") or "", "first": p.get("first"), "last": p.get("last"),
                "seen": p.get("seen") or 0, "source": source,
            })
        out.append({"key": str(key), "realm": realm, "faction": faction, "players": players,
                    "scans": [s for s in as_list(r.get("scans")) if isinstance(s, dict)]})
    return {"kind": kind, "version": db.get("version"), "client": client, "realms": out}


def merge(extracts):
    """同一個伺服器+陣營+角色名，保留最後看到的那筆，首次看到取最早、次數相加。"""
    realms = {}
    for ex in extracts:
        for r in ex["realms"]:
            slot = realms.setdefault(r["key"], {"key": r["key"], "realm": r["realm"], "faction": r["faction"],
                                                "players": {}, "scans": []})
            slot["scans"].extend(r["scans"])
            for p in r["players"]:
                cur = slot["players"].get(p["name"])
                if cur is None:
                    slot["players"][p["name"]] = dict(p)
                    continue
                newer = (p["last"] or 0) >= (cur["last"] or 0)
                merged = dict(p if newer else cur)
                firsts = [x for x in (p["first"], cur["first"]) if isinstance(x, (int, float))]
                merged["first"] = min(firsts) if firsts else None
                merged["last"] = max(p["last"] or 0, cur["last"] or 0) or None
                merged["seen"] = (p["seen"] or 0) + (cur["seen"] or 0)
                merged["token"] = merged["token"] or p["token"] or cur["token"]
                slot["players"][p["name"]] = merged
    for slot in realms.values():
        slot["players"] = sorted(slot["players"].values(), key=lambda p: p["name"])
        slot["scans"].sort(key=lambda s: s.get("at") or 0)
    return sorted(realms.values(), key=lambda r: r["key"])


def enrich(realms):
    unmapped = {"class": Counter(), "race": Counter()}
    for r in realms:
        for p in r["players"]:
            ct, rt = map_class(p["class_raw"], p["token"]), map_race(p["race_raw"])
            p["class_token"], p["class_zh"] = ct or "", CLASS_ZH.get(ct, p["class_raw"])
            p["race_token"], p["race_zh"] = rt or "", RACE_ZH.get(rt, p["race_raw"])
            if not ct and p["class_raw"]:
                unmapped["class"][p["class_raw"]] += 1
            if not rt and p["race_raw"]:
                unmapped["race"][p["race_raw"]] += 1
            p["first_tw"], p["last_tw"] = tw_time(p["first"]), tw_time(p["last"])
            p["name_lang"] = name_lang(p["name"])
    return unmapped


# ---------------------------------------------------------------------------
# 輸出
# ---------------------------------------------------------------------------

CSV_FIELDS = ["realm", "faction", "name", "name_lang", "level", "class_token", "class_zh", "class_raw",
              "race_token", "race_zh", "race_raw", "sex", "guild", "area",
              "first_tw", "last_tw", "first", "last", "seen", "source"]


def bar(share, width=20):
    n = round(share * width)
    return "█" * n + "·" * (width - n)


def pct(n, total):
    return f"{n / total * 100:.1f}%" if total else "-"


def table(rows, headers, aligns):
    out = ["| " + " | ".join(headers) + " |",
           "|" + "|".join("---:" if a == "r" else "---" for a in aligns) + "|"]
    out += ["| " + " | ".join(str(c) for c in row) + " |" for row in rows]
    return out


def active_players(r):
    """「7 天內看到」的角色（以這個伺服器最後一次看到任何人的時間為準）；都沒有時退回全部。"""
    players = r["players"]
    snapshot = max((p["last"] or 0 for p in players), default=0)
    active = [p for p in players if p["last"] and snapshot - p["last"] <= ACTIVE_DAYS * 86400]
    return active or players


def realm_section(r, lines):
    players = r["players"]
    snapshot = max((p["last"] or 0 for p in players), default=0)
    active = [p for p in players if p["last"] and snapshot - p["last"] <= ACTIVE_DAYS * 86400]
    day = [p for p in players if p["last"] and snapshot - p["last"] <= 86400]
    fz = FACTION_ZH.get(r["faction"], r["faction"])
    lines += [f"## {r['realm']} · {fz}", ""]
    lines += [f"快照時間（最後一次看到任何人）：{tw_time(snapshot)}（台灣時間）", ""]
    lines += table([[len(players), len(active), len(day)]], ["累計看過", "7 天內看到", "24 小時內看到"], ["r", "r", "r"])
    lines += ["", "以下分布都以「7 天內看到」的角色計算。", ""]
    base = active or players
    n = len(base)

    for title, key, zh in (("職業", "class_token", CLASS_ZH), ("種族", "race_token", RACE_ZH)):
        counts = Counter(p[key] or ("?" + (p["class_raw"] if key == "class_token" else p["race_raw"])) for p in base)
        top = max(counts.values(), default=1)
        rows = [[zh.get(k, k), c, pct(c, n), bar(c / top)] for k, c in counts.most_common()]
        lines += [f"### {title}", ""] + table(rows, [title, "人數", "比例", ""], ["l", "r", "r", "l"]) + [""]

    buckets = Counter()
    for p in base:
        lv = p["level"] if isinstance(p["level"], int) else 0
        b = max(0, (lv - 1) // 5)
        buckets[b] += 1
    top = max(buckets.values(), default=1)
    rows = [[f"{b * 5 + 1}–{b * 5 + 5}", c, pct(c, n), bar(c / top)] for b, c in sorted(buckets.items())]
    lines += ["### 等級分布（每 5 級）", ""] + table(rows, ["等級", "人數", "比例", ""], ["l", "r", "r", "l"]) + [""]

    langs = Counter(p.get("name_lang") or name_lang(p["name"]) for p in base)
    if langs:
        top = max(langs.values())
        rows = [[NAME_RULES["labels"].get(k, k), NAME_RULES["regions"].get(k, ""), c, pct(c, n), bar(c / top)]
                for k, c in langs.most_common()]
        lines += ["### 名字語言（推估玩家來自哪裡）", ""]
        lines += table(rows, ["名字語言", "推估地區", "人數", "比例", ""], ["l", "l", "r", "r", "l"])
        lines += ["", "> " + NAME_RULES["caveat"], ""]

    guilds = Counter(p["guild"] for p in base if p["guild"])
    if guilds:
        rows = [[i + 1, g, c] for i, (g, c) in enumerate(guilds.most_common(10))]
        lines += [f"### 人數最多的公會（共 {len(guilds)} 個公會，{pct(sum(guilds.values()), n)} 的角色有公會）", ""]
        lines += table(rows, ["#", "公會", "人數"], ["r", "l", "r"]) + [""]

    areas = Counter(p["area"] for p in base if p["area"])
    if areas:
        rows = [[a, c] for a, c in areas.most_common(10)]
        lines += ["### 最常出現的區域（最後一次被看到的位置）", ""] + table(rows, ["區域", "人數"], ["l", "r"]) + [""]

    scans = [s for s in r["scans"] if not s.get("cancelled")]
    if scans:
        # 插件的「找到」在普查途中用過誰的視窗時會被清掉重算、偏低；
        # 「最後一次被看到的時間落在這一輪內」的人數也是下限，兩者取大的比較接近。
        def found_of(s):
            at, secs = s.get("at"), s.get("secs")
            start = s.get("started") or (at - secs if isinstance(at, int) and isinstance(secs, int) else None)
            inside = sum(1 for p in players if start and at and p["last"] and start <= p["last"] <= at)
            return max(s.get("found") or 0, inside)
        rows = []
        for s in scans[-20:]:
            secs = s.get("secs")
            rows.append([tw_time(s.get("at")), found_of(s), s.get("new", ""), s.get("sent", ""),
                         f"{secs // 60} 分 {secs % 60:02d} 秒" if isinstance(secs, int) else "",
                         {"auto": "自動", "click": "點擊"}.get(s.get("mode"), s.get("mode", "")),
                         s.get("capped", 0) or ""])
        lines += [f"### 普查紀錄（最近 {len(rows)} 輪）", ""]
        lines += table(rows, ["完成時間", "找到", "新增", "查詢次數", "耗時", "模式", "仍超過 50"],
                       ["l", "r", "r", "r", "r", "l", "r"]) + [""]
        sent = sum(s.get("sent") or 0 for s in scans)
        secs = sum(s.get("secs") or 0 for s in scans)
        if sent and secs:
            lines += [f"平均每次查詢 {secs / sent:.1f} 秒；每輪平均 {sum(found_of(s) for s in scans) / len(scans):.0f} 人。", ""]
        lines += ["> 「找到」取插件記的人數，和「最後一次被看到在這一輪內」的人數，兩者較大的那個。"
                  "普查途中用過誰的視窗時，插件記的會偏低。", ""]


def write_outputs(realms, extracts, unmapped, out_dir: pathlib.Path, sources):
    out_dir.mkdir(parents=True, exist_ok=True)
    with open(out_dir / "players.csv", "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.DictWriter(fh, fieldnames=CSV_FIELDS, extrasaction="ignore")
        w.writeheader()
        for r in realms:
            w.writerows(r["players"])

    meta = {
        "generated_at": datetime.now(TW).isoformat(timespec="seconds"),
        "sources": [str(s) for s in sources],
        "clients": [ex["client"] for ex in extracts if ex["client"]],
        "formats": sorted({ex["kind"] for ex in extracts}),
        "note": "記錄的是「掃描時被看到」的角色，不是伺服器人口。對外只發布彙總數字。",
    }
    for r in realms:
        base = active_players(r)
        r["summary"] = {"active": len(base),
                        "name_langs": dict(Counter(p.get("name_lang") or name_lang(p["name"]) for p in base))}
    meta["name_lang_rules"] = f"tools/name_lang.json v{NAME_RULES.get('version', '?')}"
    payload = {"meta": meta, "realms": realms,
               "unmapped": {k: dict(v) for k, v in unmapped.items()}}
    (out_dir / "denizens.json").write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")

    lines = ["# Denizens 存檔解析報告", "",
             f"產生時間：{datetime.now(TW).strftime('%Y-%m-%d %H:%M')}（台灣時間）", ""]
    lines += ["來源檔案：", ""] + [f"- `{s}`" for s in sources] + [""]
    for c in meta["clients"]:
        lines.append(f"- 客戶端：{c.get('version', '?')} build {c.get('build', '?')}、語言 {c.get('locale', '?')}、"
                     f"插件 {c.get('addonVersion', '?')}" + ("、**點擊模式**" if c.get("gatedBuild") else ""))
    lines += ["", "> 這份資料記錄的是「掃描時被看到」的角色，**不是伺服器人口**。離線的人看不到；"
              "刪角、改名、轉服也分辨不出來。「7 天內看到」比較接近真實數字，「累計看過」只是只會往上長的上限。", ""]
    lines += ["## 總覽", ""]
    rows = []
    for r in realms:
        snap = max((p["last"] or 0 for p in r["players"]), default=0)
        act = sum(1 for p in r["players"] if p["last"] and snap - p["last"] <= ACTIVE_DAYS * 86400)
        rows.append([r["realm"], FACTION_ZH.get(r["faction"], r["faction"]), len(r["players"]), act, tw_time(snap)])
    lines += table(rows, ["伺服器", "陣營", "累計看過", "7 天內", "快照時間"], ["l", "l", "r", "r", "l"]) + [""]
    for r in realms:
        realm_section(r, lines)
    lines += ["## 資料品質", ""]
    if unmapped["class"] or unmapped["race"]:
        for kind, label in (("class", "職業"), ("race", "種族")):
            for raw, n in unmapped[kind].most_common():
                lines.append(f"- 對照表裡沒有的{label}名稱：`{raw}`（{n} 人）→ 請補進 `tools/parse_denizens.py` 的對照表")
    else:
        lines.append("- 所有職業、種族名稱都對應得上。")
    cross = sum(1 for r in realms for p in r["players"] if "-" in p["name"])
    if cross:
        lines.append(f"- 名字帶「-伺服器」的跨伺服器角色：{cross} 人")
    lines.append("")
    (out_dir / "報告.md").write_text("\n".join(lines), encoding="utf-8")


def main(argv=None):
    ap = argparse.ArgumentParser(description="解析 Denizens / Denizens TW 的 SavedVariables 存檔")
    ap.add_argument("files", nargs="+", help="一個或多個 DenizensTW.lua / Denizens.lua")
    ap.add_argument("--out", help="輸出資料夾（預設：第一個檔案旁邊的「解析結果」）")
    args = ap.parse_args(argv)
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    sources = [pathlib.Path(f) for f in args.files]
    extracts = []
    for src in sources:
        try:
            sv = parse_savedvariables(src.read_bytes())
        except LuaSyntaxError as e:
            sys.exit(f"{src}：存檔格式錯誤 - {e}")
        extracts.append(extract(sv, src.name))

    realms = merge(extracts)
    unmapped = enrich(realms)
    out_dir = pathlib.Path(args.out) if args.out else sources[0].parent / "解析結果"
    write_outputs(realms, extracts, unmapped, out_dir, sources)

    total = sum(len(r["players"]) for r in realms)
    print(f"讀了 {len(sources)} 個存檔，{len(realms)} 個伺服器/陣營，共 {total} 個角色。")
    for r in realms:
        print(f"  {r['realm']} · {FACTION_ZH.get(r['faction'], r['faction'])}：{len(r['players'])} 人，{len(r['scans'])} 輪普查")
    if unmapped["class"] or unmapped["race"]:
        print("  注意：有對照不到的名稱，見報告「資料品質」一節。")
    print(f"輸出：{out_dir}")
    for name in ("報告.md", "players.csv", "denizens.json"):
        print(f"  - {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
