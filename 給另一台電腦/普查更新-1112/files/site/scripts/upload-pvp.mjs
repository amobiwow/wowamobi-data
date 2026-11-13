// 從命令列上傳榮譽擊殺（老闆 10/26，只針對阿莫比所在的亞服 PvP 規則聯盟；tools/auto_upload.py 用）。
// 讀阿莫比公會名單插件的存檔 AmobiGuild.lua：小幫手的角色用密語插件訊息傳來的（inbox 裡 H3^、H2^、H1^ 開頭的那幾筆，
// 格式見 addon/AmobiCompanion/Share.lua、PvP.lua），站長自己記的也在裡面（寄件人是自己）。
// 每個回報的人分開送到 POST /api/pvp（帶 .env 的 UPLOAD_TOKEN，不會印出來）；網站每筆回報存一列，重傳不會重複算
// （同一場擊殺的多人回報，排行頁讀的時候合併）。
// 只傳 11/5 07:00 開服後的（--all 測試用，開服前的也傳）。
//
//   node scripts/upload-pvp.mjs <AmobiGuild.lua...>              上傳到 https://wowamobi.com
//   node scripts/upload-pvp.mjs <...> --dry-run   只檢查；最後一行印 JSON {kills, people, beta, sig}
//   node scripts/upload-pvp.mjs <...> --local     上傳到本機 npm run dev
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { LAUNCH_TS, parseSavedVariables } from "../public/assets/denizens.js";

const site = join(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const files = args.filter(a => !a.startsWith("--"));
const local = args.includes("--local");
const dry = args.includes("--dry-run");
const all = args.includes("--all");
const base = local ? "http://127.0.0.1:8787" : "https://wowamobi.com";
const CHUNK = 1000;   // POST /api/pvp 一次最多 1000 次

const isMap = v => v instanceof Map;
const list = v => (Array.isArray(v) ? v : isMap(v) ? [...v.values()] : []);
const bare = name => String(name || "").replace(/-.*$/, "");

// 一筆（數字 36 進位）：
//   H3^伺服器^陣營^職業^公會^時間:地圖:副本地圖:區域:對方名字:軍銜:榮譽:隊伍人數:等級,…（小幫手 1.7.2 起，聯盟、部落都收）
//   H2^伺服器^職業^公會^…（1.7.1：同上但沒有陣營，那時只有聯盟）
//   H1^伺服器^時間:地圖:副本地圖:對方名字:軍銜:榮譽:隊伍人數,…（1.7.0：聯盟，沒有職業、公會、區域、等級）
export function parsePvp(body) {
  const f = String(body).split("^");
  const n = x => (x === "" ? 0 : Number.parseInt(x, 36));
  let head, rows, cols;
  if ((f[0] === "H3" && f.length === 6) || (f[0] === "H2" && f.length === 5)) {
    const h = f[0] === "H3" ? f.splice(2, 1)[0] : "Alliance";   // 拿掉陣營那格，後面和 H2 一樣
    head = { realm: f[1], faction: h, cls: f[2] || null, guild: f[3] || null };
    rows = f[4];
    cols = p => ({ t: n(p[0]), map: n(p[1]), inst: n(p[2]), zone: p[3] || null, victim: p[4], rank: p[5] || null,
                   honor: n(p[6]), size: n(p[7]), level: n(p[8]) || null });
  } else if (f[0] === "H1" && f.length === 3) {
    head = { realm: f[1], faction: "Alliance", cls: null, guild: null };
    rows = f[2];
    cols = p => ({ t: n(p[0]), map: n(p[1]), inst: n(p[2]), zone: null, victim: p[3], rank: p[4] || null,
                   honor: n(p[5]), size: n(p[6]), level: null });
  } else {
    return [];
  }
  if (!head.realm || !rows) return [];
  const width = f[0] === "H1" ? 7 : 9;
  const out = [];
  for (const row of rows.split(",")) {
    const p = row.split(":");
    if (p.length !== width) continue;
    const k = { ...head, ...cols(p) };
    if (k.t > 0 && k.victim && [k.map, k.inst, k.honor, k.size].every(Number.isFinite)) out.push(k);
  }
  return out;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (!files.length) {
    console.error("用法：node scripts/upload-pvp.mjs <AmobiGuild.lua...> [--dry-run] [--local] [--all]");
    process.exit(2);
  }
  const byWho = new Map();   // 回報的人 → (擊殺 → 內容)
  let beta = 0;
  for (const f of files) {
    const guild = parseSavedVariables(readFileSync(f)).get("AmobiGuildDB");
    if (!isMap(guild)) continue;
    for (const e of list(guild.get("inbox"))) {
      if (!isMap(e) || !/^H[123]\^/.test(String(e.get("body") || ""))) continue;
      const who = bare(e.get("from"));
      if (!who || who === "?") continue;
      for (const k of parsePvp(e.get("body"))) {
        if (k.t < LAUNCH_TS && !all) { beta++; continue; }
        if (!byWho.has(who)) byWho.set(who, new Map());
        byWho.get(who).set(`${k.realm}|${k.victim}|${k.t}`, k);
      }
    }
  }
  const groups = [...byWho].map(([who, m]) => ({ who, kills: [...m.values()].sort((a, b) => a.t - b.t) }))
    .sort((a, b) => (a.who < b.who ? -1 : 1));
  const total = groups.reduce((a, g) => a + g.kills.length, 0);
  const sig = createHash("sha256").update(JSON.stringify(groups)).digest("hex");
  console.log(`開服後的榮譽擊殺回報：${total} 次（${groups.length} 個人）` + (beta ? `；開服前的 ${beta} 次不傳` : ""));
  if (dry) {
    console.log(JSON.stringify({ kills: total, people: groups.length, beta, sig }));
    process.exit(0);
  }
  if (!total) process.exit(0);
  const secrets = readFileSync(local ? join(site, ".dev.vars") : join(site, "..", ".env"), "utf8");
  const token = new RegExp("^UPLOAD_TOKEN=(.+)$", "m").exec(secrets)?.[1]?.trim();
  if (!token) {
    console.error(local ? "site\\.dev.vars 裡沒有 UPLOAD_TOKEN。" : ".env 裡沒有 UPLOAD_TOKEN。");
    process.exit(1);
  }
  const sum = { fresh: 0, dup: 0, limited: 0, rejected: 0 };
  for (const g of groups) {
    for (let i = 0; i < g.kills.length; i += CHUNK) {
      const r = await fetch(`${base}/api/pvp`, {
        method: "POST",
        headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
        body: JSON.stringify({ reporter: g.who, kills: g.kills.slice(i, i + CHUNK) }),
      });
      const res = await r.json().catch(() => ({}));
      if (!r.ok && r.status !== 400) {
        console.error(`上傳失敗：HTTP ${r.status} ${res.error || ""}（重傳整份不會重複算）`);
        process.exit(1);
      }
      if (!r.ok) { sum.rejected += g.kills.slice(i, i + CHUNK).length; continue; }
      for (const k of Object.keys(sum)) sum[k] += res[k] || 0;
    }
  }
  console.log(`完成：新的回報 ${sum.fresh} 次、之前傳過的 ${sum.dup} 次`
    + (sum.limited ? `、超過每小時上限沒收 ${sum.limited} 次` : "") + (sum.rejected ? `、格式不對沒收 ${sum.rejected} 次` : "") + "。");
}
