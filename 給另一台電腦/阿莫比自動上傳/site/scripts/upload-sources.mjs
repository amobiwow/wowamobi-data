// 從命令列上傳物品來源（老闆 10/27：「物品的資料 能補他們來源的單位跟地圖座標嗎」→ 小幫手 1.11.0「一起做」；tools/auto_upload.py 用）。
// 讀阿莫比公會名單插件的存檔 AmobiGuild.lua：玩家的小幫手用密語插件訊息傳來的（inbox 裡 S1^ 開頭的那幾筆，格式見
// addon/AmobiCompanion/Sources.lua），站長自己這台記的也在裡面（own＝true）。
// 每個回報的人分開送到 POST /api/sources（帶 .env 的 UPLOAD_TOKEN，不會印出來）；回報的人只送 x-amobi-relay＝名字的加密代號
// （.env 的 ROSTER_KEY 做 HMAC，名字不送），站長自己記的不帶（網站算 owner）。同一筆重傳不會重複算。
// 只傳 11/5 07:00 開服後記的（--all 測試用，開服前的也傳）。
//
//   node scripts/upload-sources.mjs <AmobiGuild.lua...>              上傳到 https://wowamobi.com
//   node scripts/upload-sources.mjs <...> --dry-run   只檢查；最後一行印 JSON {entries, batches, people, beta, sig}
//   node scripts/upload-sources.mjs <...> --local     上傳到本機 npm run dev
import { createHash, createHmac } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { LAUNCH_TS, parseSavedVariables } from "../public/assets/denizens.js";

const site = join(dirname(fileURLToPath(import.meta.url)), "..");
const CHUNK = 100;   // POST /api/sources 一次最多送幾筆（網站最多收 300 筆、5000 項）

const isMap = v => v instanceof Map;
const list = v => (Array.isArray(v) ? v : isMap(v) ? [...v.values()] : []);
const bare = name => String(name || "").replace(/-.*$/, "");
const n36 = x => (x === "" || x == null ? null : Number.parseInt(x, 36));

// 一筆 S1^伺服器^陣營^一項~一項~…（數字 36 進位）→ {realm, faction, entries}；看不懂的項目略過
export function parseSources(body) {
  const f = String(body).split("^");
  if (f[0] !== "S1" || f.length !== 4 || !f[1]) return null;
  const entries = [];
  for (const raw of f[3] ? f[3].split("~") : []) {
    const p = raw.split(":");
    const k = p[0], t = n36(p[1]), id = n36(p[2]);
    if (!(t > 0) || !(id > 0)) continue;
    if (k === "v" && p.length === 9) {
      const items = (p[8] ? p[8].split(",") : []).map(s => {
        const [item, price, stack, lim, cost] = s.split(".");
        return { item: n36(item), price: n36(price) ?? 0, stack: n36(stack) ?? 1, lim: lim === "1" ? 1 : 0,
                 cost: (cost || "").replace(/(^|\+)([ic])([0-9a-z]+)\*([0-9a-z]+)/g, (_, s0, c, i, q) => `${s0}${c}${n36(i)}*${n36(q)}`)
                   .replace(/(^|\+)t([^*+]+)\*([0-9a-z]+)/g, (_, s0, name, q) => `${s0}t${name}*${n36(q)}`) };
      }).filter(it => it.item > 0);
      entries.push({ k, t, id, map: n36(p[3]) ?? 0, x: n36(p[4]), y: n36(p[5]), zone: p[6], name: p[7], items });
    } else if (k === "q" && p.length === 13) {
      const pairs = s => (s ? s.split(",") : []).map(x => x.split(".").map(n36)).filter(([a, b]) => a > 0 && b > 0);
      entries.push({ k, t, id, step: p[3], giver: p[4].replace(/^([no])([0-9a-z]+)$/, (_, c, i) => `${c}${n36(i)}`), map: n36(p[5]) ?? 0,
                     x: n36(p[6]), y: n36(p[7]), zone: p[8], name: p[9], title: p[10], choices: pairs(p[11]), rewards: pairs(p[12]) });
    } else if ((k === "m" || k === "o") && p.length === 10) {
      const pts = (p[8] ? p[8].split(",") : []).map(x => x.split(".").map(n36)).filter(xy => xy.length === 2 && xy.every(Number.isFinite));
      const items = (p[9] ? p[9].split(",") : []).map(x => x.split(".").map(n36)).filter(v => v.length === 3 && v.every(z => z > 0));
      entries.push({ k, t, id, map: n36(p[3]) ?? 0, inst: n36(p[4]) ?? 0, zone: p[5], name: p[6], n: n36(p[7]), pts, items });
    }
  }
  return { realm: f[1], faction: f[2], entries };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  const files = args.filter(a => !a.startsWith("--"));
  const local = args.includes("--local"), dry = args.includes("--dry-run"), all = args.includes("--all");
  const base = local ? "http://127.0.0.1:8787" : "https://wowamobi.com";
  if (!files.length) {
    console.error("用法：node scripts/upload-sources.mjs <AmobiGuild.lua...> [--dry-run] [--local] [--all]");
    process.exit(2);
  }
  const byWho = new Map();   // "owner" 或名字 → (rid → 一筆)
  let beta = 0;
  for (const f of files) {
    const guild = parseSavedVariables(readFileSync(f)).get("AmobiGuildDB");
    if (!isMap(guild)) continue;
    for (const e of list(guild.get("inbox"))) {
      if (!isMap(e) || !/^S1\^/.test(String(e.get("body") || ""))) continue;
      const who = e.get("own") === true ? "owner" : bare(e.get("from"));
      if (!who || who === "?") continue;
      const b = parseSources(e.get("body"));
      if (!b) continue;
      const entries = b.entries.filter(x => all || x.t >= LAUNCH_TS);
      beta += b.entries.length - entries.length;
      if (!entries.length) continue;
      if (!byWho.has(who)) byWho.set(who, new Map());
      byWho.get(who).set(String(e.get("id")), { rid: String(e.get("id")), realm: b.realm, faction: b.faction, entries });
    }
  }
  const groups = [...byWho].map(([who, m]) => ({ who, batches: [...m.values()].sort((a, b) => (a.rid < b.rid ? -1 : 1)) }))
    .sort((a, b) => (a.who < b.who ? -1 : 1));
  const count = k => groups.reduce((a, g) => a + g.batches.reduce((s, b) => s + b.entries.filter(x => !k || x.k === k).length, 0), 0);
  const total = count(), nb = groups.reduce((a, g) => a + g.batches.length, 0);
  const sig = createHash("sha256").update(JSON.stringify(groups.map(g => [createHash("sha256").update(g.who).digest("hex"), g.batches]))).digest("hex");
  console.log(`開服後的物品來源：${nb} 筆（${groups.length} 個人）：商人 ${count("v")}、任務 ${count("q")}、怪物 ${count("m")}、寶箱 ${count("o")} 項`
    + (beta ? `；開服前的 ${beta} 項不傳` : ""));
  if (dry) {
    console.log(JSON.stringify({ entries: total, batches: nb, people: groups.length, beta, sig }));
    process.exit(0);
  }
  if (!total) process.exit(0);
  const secrets = readFileSync(local ? join(site, ".dev.vars") : join(site, "..", ".env"), "utf8");
  const read = k => new RegExp(`^${k}=(.+)$`, "m").exec(secrets)?.[1]?.trim();
  const token = read("UPLOAD_TOKEN"), rosterKey = read("ROSTER_KEY");
  if (!token) {
    console.error(local ? "site\\.dev.vars 裡沒有 UPLOAD_TOKEN。" : ".env 裡沒有 UPLOAD_TOKEN。");
    process.exit(1);
  }
  if (groups.some(g => g.who !== "owner") && !rosterKey) {
    console.error(`${local ? "site\\.dev.vars" : ".env"} 裡沒有 ROSTER_KEY（玩家傳來的要用它把名字變成代號），先不傳。`);
    process.exit(1);
  }
  const sum = { fresh: 0, dup: 0, entries: 0, rejected: 0 };
  for (const g of groups) {
    const headers = { "content-type": "application/json", authorization: `Bearer ${token}` };
    if (g.who !== "owner") headers["x-amobi-relay"] = createHmac("sha256", rosterKey).update(`src:${g.who}`).digest("hex").slice(0, 16);
    for (let i = 0; i < g.batches.length; i += CHUNK) {
      const r = await fetch(`${base}/api/sources`, { method: "POST", headers, body: JSON.stringify({ batches: g.batches.slice(i, i + CHUNK) }) });
      const res = await r.json().catch(() => ({}));
      if (!r.ok && r.status !== 400) {
        console.error(`上傳失敗：HTTP ${r.status} ${res.error || ""}（重傳整份不會重複算）`);
        process.exit(1);
      }
      if (!r.ok) { sum.rejected += g.batches.slice(i, i + CHUNK).length; continue; }
      for (const k of Object.keys(sum)) sum[k] += res[k] || 0;
    }
  }
  console.log(`完成：新的 ${sum.fresh} 筆（${sum.entries} 項）、之前傳過的 ${sum.dup} 筆` + (sum.rejected ? `、看不懂沒收 ${sum.rejected} 項` : "") + "。");
}
