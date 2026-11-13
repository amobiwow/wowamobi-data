#!/usr/bin/env python3
"""
讀取阿莫比拍賣場插件（AmobiAuction）的 SavedVariables 存檔，整理成網站物品頁「拍賣場價格」用的資料，再由
site/scripts/upload-auction.mjs 上傳到 D1。也寫一份中文報告。

用法：
    python tools/amobi_auction.py <AmobiAuction.lua> [更多存檔...] [--out 輸出資料夾] [--json 上傳檔]

- 多個存檔（不同電腦、不同帳號）一起丟：同一次掃描（同伺服器、同陣營、同一秒、同一種）只算一次。
- 陣營：在藏寶海灣、加基森、永望鎮的中立拍賣場掃的算「Neutral」（中立），其他照角色的陣營。
- 時間一律用「完成」的時間：全掃描讀完、瀏覽關掉拍賣場前最後一次看到（網站只寫完成時間）；同一次掃描用開始的時間認。
- 每件物品、每個伺服器＋陣營、每一天（台灣時間）一筆：
    用那天「最後一次全掃描」裡的數字（上架數量、拍賣筆數、最低一口價、中位數、第 10／25／75 百分位）；那天的全掃描都沒有這件，
    才用瀏覽記到的（點分類看到的數量和最低價；點進去看過全部拍賣的才有筆數、中位數、百分位）。low＝那天所有記錄裡最低的一口價。
- 百分位是插件 1.1.0 起才記（存檔的物品欄位 8 格）；1.0.0 的存檔（5 格）照樣讀，百分位空著。
- 沒讀完的全掃描（拍賣場關掉、斷線）列在報告裡，數字不用。
- 階段：台灣時間 2026-11-05 07:00 開服之前是 beta（封測），之後是 live（和網站的 LAUNCH_AT 一樣）。
- 輸出只有伺服器名、陣營、時間和數字，沒有任何玩家、賣家的名字（插件本來就不存）。
- 不執行任何 Lua：存檔用 parse_denizens.py 的解析器當資料讀。只用 Python 標準函式庫。
- 公會成員的小幫手傳來的（1.6.0，阿莫比公會名單插件的存檔 AmobiGuild.lua 的 inbox）也照樣讀：
  一筆「M1^伺服器^陣營^faction/neutral^full^開始^讀完^拍賣筆數^物品數^物品資料」，物品資料的數字是 36 進位。
  報告裡只寫「公會成員 N」，不寫名字。
"""
from __future__ import annotations

import argparse
import glob
import json
import pathlib
import sys
from collections import defaultdict
from datetime import datetime

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from parse_denizens import TW, LuaSyntaxError, as_list, parse_savedvariables, table, tw_time  # noqa: E402

LAUNCH = int(datetime(2026, 11, 5, 7, 0, tzinfo=TW).timestamp())   # 正式開服（site/wrangler.jsonc 的 LAUNCH_AT）
SITE = pathlib.Path(__file__).resolve().parent.parent / "site"
ITEMS = SITE / "public" / "data" / "items" / "index.json"
FACTIONS = {"Alliance", "Horde"}
FACTION_ZH = {"Alliance": "聯盟", "Horde": "部落", "Neutral": "中立"}
KIND_ZH = {"full": "全掃描", "browse": "瀏覽"}
CHECK_GAP = 30 * 60          # 秒：全掃描和瀏覽相差 30 分鐘內，拿來核對最低價


def tw_day(t: int) -> str:
    return datetime.fromtimestamp(t, TW).strftime("%Y-%m-%d")


def phase(t: int) -> str:
    return "live" if t >= LAUNCH else "beta"


def money(c) -> str:
    if c is None:
        return "-"
    g, s, k = c // 10000, c // 100 % 100, c % 100
    return " ".join(p for p in (f"{g:,}金" if g else "", f"{s}銀" if s else "", f"{k}銅" if k or not (g or s) else "") if p)


# ---------------------------------------------------------------------------
# 讀存檔
# ---------------------------------------------------------------------------

def decode(data: str) -> dict[int, tuple]:
    """「編號,數量,筆數,最低一口價,中位數[,第10,第25,第75百分位];…」→ {編號: (數量, 筆數, 最低, 中位數, p10, p25, p75)}，
    不知道的是 None（1.0.0 的存檔只有前 5 格，百分位是 None）。"""
    out = {}
    for part in data.split(";"):
        if not part:
            continue
        f = part.split(",")
        if len(f) not in (5, 8) or not f[0].isdigit() or not f[1].isdigit():
            raise ValueError(f"看不懂的物品資料：{part[:40]}")
        vals = tuple(int(x) if x else None for x in f[1:])
        out[int(f[0])] = vals + (None,) * (7 - len(vals))
    return out


def decode36(data: str) -> dict[int, tuple]:
    """小幫手傳來的物品資料：和 decode 一樣的 8 格，數字是 36 進位。"""
    out = {}
    for part in data.split(";"):
        if not part:
            continue
        f = part.split(",")
        if len(f) != 8 or not f[0].isalnum():
            raise ValueError(f"看不懂的物品資料：{part[:40]}")
        vals = tuple(int(x, 36) if x else None for x in f[1:])
        out[int(f[0], 36)] = vals
    return out


def extract_relay(db: dict, source: str):
    """阿莫比公會名單插件收到的：公會成員的小幫手傳來的拍賣場全掃描。"""
    scans, skipped, who = [], 0, {}
    for e in as_list(db.get("inbox")):
        body = e.get("body") if isinstance(e, dict) else None
        if not isinstance(body, str) or not body.startswith("M1^"):
            continue
        f = body.split("^")
        try:
            if len(f) != 10 or f[2] not in FACTIONS or f[4] != "full":
                raise ValueError("格式不對")
            t, end = int(f[5]), int(f[6])
            items = decode36(f[9])
        except ValueError:
            skipped += 1
            continue
        n = who.setdefault(e.get("from"), len(who) + 1)
        end = end if end >= t else t
        scans.append({"realm": f[1], "faction": "Neutral" if f[3] == "neutral" else f[2], "t": t, "end": end, "day": tw_day(end),
                      "kind": "full", "phase": phase(end), "items": items, "auctions": int(f[7] or 0), "partial": False,
                      "how": "relay", "zone": "", "bad": 0, "sold": 0, "nobuyout": 0, "secs": None,
                      "source": f"{source}（公會成員 {n}）"})
    return {"source": source, "scans": scans, "skipped": skipped, "sample": None, "stats": {}, "client": {}}


def extract(sv: dict, source: str):
    if not isinstance(sv.get("AmobiAuctionDB"), dict) and isinstance(sv.get("AmobiGuildDB"), dict):
        return extract_relay(sv["AmobiGuildDB"], source)
    db = sv.get("AmobiAuctionDB")
    if not isinstance(db, dict):
        raise ValueError(f"{source}：找不到 AmobiAuctionDB，這不是阿莫比拍賣場插件的存檔")
    scans, skipped = [], 0
    for s in as_list(db.get("scans")):
        ok = (isinstance(s, dict) and s.get("kind") in KIND_ZH and isinstance(s.get("t"), (int, float))
              and isinstance(s.get("realm"), str) and s["realm"] and s.get("faction") in FACTIONS and isinstance(s.get("data"), str))
        if not ok:
            skipped += 1
            continue
        t = int(s["t"])
        end = next((int(s[k]) for k in ("done", "last") if isinstance(s.get(k), (int, float)) and s[k] >= t), t)
        faction = "Neutral" if s.get("ah") == "neutral" else s["faction"]
        scans.append({"realm": s["realm"], "faction": faction, "t": t, "end": end, "day": tw_day(end), "kind": s["kind"], "phase": phase(end),
                      "items": decode(s["data"]), "auctions": s.get("auctions"), "partial": bool(s.get("partial")),
                      "how": s.get("how"), "zone": s.get("zone") or "", "bad": s.get("bad") or 0, "sold": s.get("sold") or 0,
                      "nobuyout": s.get("nobuyout") or 0, "secs": s.get("secs"), "source": source})
    sample = db.get("sample") if isinstance(db.get("sample"), dict) else None
    return {"source": source, "scans": scans, "skipped": skipped, "sample": sample,
            "stats": db.get("stats") if isinstance(db.get("stats"), dict) else {},
            "client": db.get("client") if isinstance(db.get("client"), dict) else {}}


def merge(extracts):
    """同一次掃描（伺服器、陣營、時間、種類都一樣）只留一份；真的撞在同一秒的，留物品比較多的。"""
    best = {}
    for x in extracts:
        for s in x["scans"]:
            key = (s["realm"], s["faction"], s["t"], s["kind"])
            if key not in best or len(s["items"]) > len(best[key]["items"]):
                best[key] = s
    return [best[k] for k in sorted(best)]


# ---------------------------------------------------------------------------
# 每件物品、每天一筆
# ---------------------------------------------------------------------------

def daily(scans):
    groups = defaultdict(list)                     # (物品, 伺服器, 陣營, 日) → [(種類優先, 時間, 數字)]
    for s in scans:
        if s["partial"]:
            continue
        rank = 2 if s["kind"] == "full" else 1
        for item, nums in s["items"].items():
            groups[(item, s["realm"], s["faction"], s["day"])].append((rank, s["end"], s["kind"], nums))
    rows = []
    for (item, realm, faction, day), obs in sorted(groups.items()):
        rank, t, kind, (qty, n, low_one, med, p10, p25, p75) = max(obs, key=lambda o: (o[0], o[1]))
        lows = [o[3][2] for o in obs if o[3][2] is not None]
        row = {"item": item, "realm": realm, "faction": faction, "phase": phase(t), "day": day, "t": t, "kind": kind,
               "qty": qty, "n": n, "min": low_one, "med": med, "low": min(lows) if lows else None}
        if p10 is not None:
            row.update(p10=p10, p25=p25, p75=p75)
        rows.append(row)
    return rows


def checks(scans):
    """全掃描的最低價 vs 30 分鐘內瀏覽看到的最低價：一致的比例（拿來確認一口價是整筆還是單價）。"""
    same = diff = 0
    examples = []
    fulls = [s for s in scans if s["kind"] == "full" and not s["partial"]]
    for b in (s for s in scans if s["kind"] == "browse"):
        near = [f for f in fulls if (f["realm"], f["faction"]) == (b["realm"], b["faction"]) and abs(f["end"] - b["end"]) <= CHECK_GAP]
        if not near:
            continue
        f = min(near, key=lambda f: abs(f["end"] - b["end"]))
        for item, nums in b["items"].items():
            fn = f["items"].get(item)
            if not fn or nums[2] is None or fn[2] is None:
                continue
            if fn[2] == nums[2]:
                same += 1
            else:
                diff += 1
                if len(examples) < 8:
                    examples.append((item, fn[2], nums[2], fn[0]))
    return same, diff, examples


# ---------------------------------------------------------------------------
# 報告
# ---------------------------------------------------------------------------

def item_names(path):
    try:
        data = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    f = data["fields"]
    i, n = f.index("id"), f.index("name")
    return {row[i]: row[n] for row in data["items"]}


def report(scans, rows, extracts, sources, names):
    lines = ["# 拍賣場物價彙整", "", f"產生時間：{datetime.now(TW).strftime('%Y-%m-%d %H:%M')}（台灣時間）", "",
             "## 讀了哪些存檔", ""]
    for src, x in zip(sources, extracts):
        c = x["client"]
        lines.append(f"- {src}：掃描 {len(x['scans'])} 次（遊戲 {c.get('version', '?')}.{c.get('build', '?')}、插件 {c.get('addon', '?')}）"
                     + (f"，看不懂而略過 {x['skipped']} 筆" if x["skipped"] else ""))
    lines += ["", f"合併後（同一次掃描只算一次）：{len(scans)} 次掃描，網站資料 {len(rows):,} 筆（每件物品、每個伺服器＋陣營、每天一筆）。", ""]

    lines += ["## 每個伺服器＋陣營", ""]
    groups = defaultdict(list)
    for s in scans:
        groups[(s["phase"], s["realm"], s["faction"])].append(s)
    trows = []
    for (ph, realm, faction), ss in sorted(groups.items()):
        full = [s for s in ss if s["kind"] == "full" and not s["partial"]]
        last = max(ss, key=lambda s: s["end"])
        trows.append([("正式" if ph == "live" else "封測"), realm, FACTION_ZH[faction], len(full), len(ss) - len(full),
                      tw_time(last["end"]), f"{len(last['items']):,}"])
    lines += table(trows, ["階段", "伺服器", "陣營", "全掃描", "瀏覽／沒讀完", "最近一次", "最近一次物品數"],
                   ["l", "l", "l", "r", "r", "l", "r"])

    lines += ["", "## 每一次掃描", ""]
    srows = [[tw_time(s["end"]), s["realm"], FACTION_ZH[s["faction"]], KIND_ZH[s["kind"]] + ("（沒讀完）" if s["partial"] else "")
              + ("（別的插件要的）" if s["how"] == "other" else ""), s["zone"], f"{s['auctions']:,}" if s["auctions"] is not None else "-",
              f"{len(s['items']):,}", s["secs"] if s["secs"] is not None else "-"] for s in scans]
    lines += table(srows, ["完成時間", "伺服器", "陣營", "種類", "地點", "拍賣筆數", "物品數", "秒"], ["l", "l", "l", "l", "l", "r", "r", "r"])

    latest = [s for s in scans if s["kind"] == "full" and not s["partial"]]
    if latest:
        s = max(latest, key=lambda s: (len(s["items"]), s["end"]))
        top = sorted(s["items"].items(), key=lambda kv: -kv[1][0])[:15]
        lines += ["", f"## 上架數量最多的物品（{tw_time(s['end'])} {s['realm']} {FACTION_ZH[s['faction']]}）", ""]
        lines += table([[names.get(i, f"#{i}"), i, f"{v[0]:,}", v[1] if v[1] is not None else "-", money(v[2]), money(v[4]), money(v[3]), money(v[6])]
                        for i, v in top],
                       ["物品", "編號", "數量", "筆數", "最低一口價", "最便宜 10%", "中位數", "最貴 25%"], ["l", "r", "r", "r", "r", "r", "r", "r"])

    lines += ["", "## 資料品質", ""]
    same, diff, examples = checks(scans)
    if same + diff:
        lines.append(f"- 全掃描的最低價和 30 分鐘內瀏覽看到的一樣：{same} 件，不一樣：{diff} 件"
                     + ("（多數不一樣時，一口價的算法可能要改）" if diff > same else "（中間有人買賣就會不一樣）"))
        for item, fmin, bmin, qty in examples:
            lines.append(f"  - {names.get(item, f'#{item}')}（{item}）：全掃描 {money(fmin)}、瀏覽 {money(bmin)}（全掃描數量 {qty}）")
    else:
        lines.append("- 還沒有全掃描和瀏覽時間接近的記錄，無法核對最低價（掃完全部後點幾個分類就有）。")
    for x in extracts:
        smp = x["sample"]
        if smp and as_list(smp.get("rows")):
            lines.append(f"- 原始數字樣本（{x['source']}，{tw_time(smp.get('t'))}；物品、數量、一口價、最低出價、目前出價）：")
            for r in as_list(smp["rows"])[:6]:
                r = as_list(r)
                if len(r) >= 3 and r[1]:
                    lines.append(f"  - {names.get(r[0], f'#{r[0]}')}：{r[1]} 個、一口價 {money(r[2])}（每個 {money(round(r[2] / r[1]))}）"
                                 + (f"、最低出價 {money(r[3])}" if len(r) > 3 and r[3] else ""))
    partial = [s for s in scans if s["partial"]]
    if partial:
        lines.append(f"- 沒讀完、數字不用的全掃描：{len(partial)} 次（" + "、".join(tw_time(s["end"]) for s in partial) + "）")
    bad = sum(s["bad"] for s in scans)
    if bad:
        lines.append(f"- 看不懂而略過的拍賣：{bad} 筆")
    for x in extracts:
        st = x["stats"]
        notes = [f"{label} {st[k]} 次" for k, label in (("timeouts", "伺服器沒給清單"), ("autoTimeouts", "其中自動掃描沒回應"), ("empty", "清單是空的"),
                                                    ("errors", "插件出錯"), ("hidden", "秘密值")) if st.get(k)]
        if notes:
            lines.append(f"- {x['source']}：" + "、".join(notes) + (f"（最後一次錯誤：{st.get('lastError')}）" if st.get("errors") else ""))
    lines.append("")
    return "\n".join(lines)


def main(argv=None):
    ap = argparse.ArgumentParser(description="彙整阿莫比拍賣場插件（AmobiAuction）的存檔")
    ap.add_argument("files", nargs="+", help="一個或多個 AmobiAuction.lua")
    ap.add_argument("--out", help="報告的資料夾（預設：第一個檔案旁邊的「拍賣場彙整」）")
    ap.add_argument("--json", help="上傳用的 JSON（預設：報告資料夾裡的 upload.json）")
    ap.add_argument("--items", default=str(ITEMS), help="網站的物品資料庫（報告裡的物品名稱）")
    args = ap.parse_args(argv)
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    sources = []
    for f in args.files:                # Windows 的命令列不會自己展開 *
        hits = sorted(glob.glob(f)) if any(c in f for c in "*?[") else [f]
        if not hits:
            sys.exit(f"找不到：{f}")
        sources += [pathlib.Path(h) for h in hits]
    extracts = []
    for n, src in enumerate(sources):
        try:
            sv = parse_savedvariables(src.read_bytes())
            extracts.append(extract(sv, f"{n + 1}:{src.parent.name}/{src.name}"))
        except LuaSyntaxError as e:
            sys.exit(f"{src}：存檔格式錯誤 - {e}")
        except ValueError as e:
            sys.exit(f"{src}：{e}")

    scans = merge(extracts)
    rows = daily(scans)
    out_dir = pathlib.Path(args.out) if args.out else sources[0].parent / "拍賣場彙整"
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "報告.md").write_text(report(scans, rows, extracts, sources, item_names(args.items)), encoding="utf-8")
    upload = pathlib.Path(args.json) if args.json else out_dir / "upload.json"
    payload = {
        "v": 1,
        "generated": datetime.now(TW).isoformat(timespec="seconds"),
        "scans": [{"realm": s["realm"], "faction": s["faction"], "t": s["t"], "end": s["end"], "day": s["day"], "kind": s["kind"], "phase": s["phase"],
                   "auctions": s["auctions"], "items": len(s["items"]), **({"partial": True} if s["partial"] else {})} for s in scans],
        "days": rows,
    }
    upload.parent.mkdir(parents=True, exist_ok=True)
    upload.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")

    full = sum(1 for s in scans if s["kind"] == "full" and not s["partial"])
    print(f"讀了 {len(sources)} 個存檔：掃描 {len(scans)} 次（全掃描 {full} 次），網站資料 {len(rows):,} 筆。")
    for realm, faction in sorted({(s["realm"], s["faction"]) for s in scans}):
        ss = [s for s in scans if (s["realm"], s["faction"]) == (realm, faction)]
        last = max(ss, key=lambda s: s["end"])
        print(f"  {realm}・{FACTION_ZH[faction]}：{len(ss)} 次，最近一次 {tw_time(last['end'])}（{len(last['items']):,} 種物品）")
    print("輸出：")
    print(f"  - {upload}")
    print(f"  - {out_dir / '報告.md'}")
    return {"scans": len(scans), "days": len(rows)}


if __name__ == "__main__":
    main()
