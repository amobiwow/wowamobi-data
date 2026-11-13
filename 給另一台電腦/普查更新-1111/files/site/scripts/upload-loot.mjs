// 從命令列上傳首領掉落（AmobiLoot 存檔；老闆 10/24：「副本掉落要不要一起撈」，tools/auto_upload.py 用）。
// 解析和 /report 上傳頁一模一樣（public/assets/report.js 的 extractLoot），送到同一個 POST /api/loot；
// 帶站長上傳金鑰（D:\魔獸網站\.env 的 UPLOAD_TOKEN，不會印出來），物品頁直接算數。同一場擊殺重傳不會重複算。
// 只傳 11/5 07:00 開服後的擊殺（老闆 10/24：「封測跟壓測都不用在管了」）。
//
// 1.6.0：也讀阿莫比公會名單插件的存檔 AmobiGuild.lua——公會成員的小幫手用插件訊息傳來的首領擊殺（inbox 的 K1 那幾筆，
// 格式見 addon/AmobiCompanion/Share.lua）。這些算「那個人回報的」，不算站長的：每個人分開送，帶 x-amobi-relay＝
// 名字的加密代號（.env 的 ROSTER_KEY 做 HMAC；名字不送），網站照樣要兩個人回報過才列。
//
//   node scripts/upload-loot.mjs <AmobiLoot.lua 或 AmobiGuild.lua...>             上傳到 https://wowamobi.com
//   node scripts/upload-loot.mjs <...> --dry-run   只檢查；最後一行印 JSON {kills, items, beta, relayed, people, sig}
//   node scripts/upload-loot.mjs <...> --local     上傳到本機 npm run dev
import { createHash, createHmac } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { LAUNCH_TS, parseSavedVariables } from "../public/assets/denizens.js";
import { extractLoot } from "../public/assets/report.js";

const site = join(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const files = args.filter(a => !a.startsWith("--"));
const local = args.includes("--local");
const dry = args.includes("--dry-run");
const all = args.includes("--all");   // 測試用：開服前的也傳（網站不收未來時間的擊殺，開服前只能用現在的時間測）
const base = local ? "http://127.0.0.1:8787" : "https://wowamobi.com";
const CHUNK = 1000;   // POST /api/loot 一次最多 1000 場
if (!files.length) {
  console.error("用法：node scripts/upload-loot.mjs <AmobiLoot.lua 或 AmobiGuild.lua...> [--dry-run] [--local]");
  process.exit(2);
}

const isMap = v => v instanceof Map;
const list = v => (Array.isArray(v) ? v : isMap(v) ? [...v.values()] : []);
const bare = name => String(name || "").replace(/-.*$/, "");

// 小幫手傳來的一筆：K1^伺服器^首領^地圖^難度^人數^時間^副本分身^有沒有打開屍體^物品:數量,…（物品和數量是 36 進位）
function relayKill(body) {
  const f = String(body).split("^");
  if (f.length !== 10 || f[0] !== "K1") return null;
  const n = (x, b = 10) => (x === "" ? null : Number.parseInt(x, b));
  const items = f[9] ? f[9].split(",").map(p => p.split(":").map(x => Number.parseInt(x, 36))) : [];
  if (items.some(([id, q]) => !(id > 0) || !(q > 0))) return null;
  const k = { enc: n(f[2]), map: n(f[3]), diff: n(f[4]), size: n(f[5]), t: n(f[6]), realm: f[1], copy: f[7] || null,
              full: f[8] === "1", items: items.slice(0, 40) };
  return k.enc > 0 && k.t > 0 ? k : null;
}

let client = null, beta = 0;
const own = new Map(), relayed = new Map();   // relayed: 名字 → (擊殺 → 內容)
const keyOf = k => `${k.realm}|${k.enc}|${k.t}`;
const better = (a, b) => (!a || b.items.length > a.items.length || (b.full && !a.full) ? b : a);   // 同一場傳了好幾次：留記得比較多的
for (const f of files) {
  const sv = parseSavedVariables(readFileSync(f));
  const guild = sv.get("AmobiGuildDB");
  if (!sv.has("AmobiLootDB") && isMap(guild)) {
    for (const e of list(guild.get("inbox"))) {
      if (!isMap(e)) continue;
      const k = relayKill(e.get("body"));
      if (!k) continue;
      if (k.t < LAUNCH_TS && !all) { beta++; continue; }
      const who = bare(e.get("from"));
      if (!relayed.has(who)) relayed.set(who, new Map());
      const m = relayed.get(who);
      m.set(keyOf(k), better(m.get(keyOf(k)), k));
    }
    continue;
  }
  const data = extractLoot(sv);
  client ??= data.client;
  for (const k of data.kills) {
    if (k.t < LAUNCH_TS && !all) { beta++; continue; }
    own.set(keyOf(k), k);   // 好幾個帳號記到同一場只送一次
  }
}
const byTime = m => [...m.values()].sort((a, b) => a.t - b.t);
const mine = byTime(own);
const groups = [...relayed].map(([who, m]) => ({ who, kills: byTime(m) })).sort((a, b) => (a.who < b.who ? -1 : 1));
const relayN = groups.reduce((a, g) => a + g.kills.length, 0);
const everything = [...mine, ...groups.flatMap(g => g.kills)];
const items = everything.reduce((a, k) => a + k.items.length, 0);
const sig = createHash("sha256").update(JSON.stringify([mine, groups.map(g => [createHash("sha256").update(g.who).digest("hex"), g.kills])])).digest("hex");
const bosses = new Set(everything.map(k => k.enc)).size;
console.log(`開服後的首領擊殺：自己記的 ${mine.length} 場、公會成員的小幫手傳來的 ${relayN} 場（${groups.length} 個人），`
  + `共 ${bosses} 個首領、掉落 ${items} 件` + (beta ? `；開服前（封測、壓測）的 ${beta} 場不傳` : ""));
if (dry) {
  console.log(JSON.stringify({ kills: mine.length + relayN, items, beta, relayed: relayN, people: groups.length, sig }));
  process.exit(0);
}
if (!everything.length) process.exit(0);

const secrets = readFileSync(local ? join(site, ".dev.vars") : join(site, "..", ".env"), "utf8");
const read = k => new RegExp(`^${k}=(.+)$`, "m").exec(secrets)?.[1]?.trim();
const token = read("UPLOAD_TOKEN"), rosterKey = read("ROSTER_KEY");
if (!token) {
  console.error(local ? "site\\.dev.vars 裡沒有 UPLOAD_TOKEN。" : ".env 裡沒有 UPLOAD_TOKEN。");
  process.exit(1);
}
if (groups.length && !rosterKey) {
  console.error(`${local ? "site\\.dev.vars" : ".env"} 裡沒有 ROSTER_KEY（公會成員傳來的要用它把名字變成代號），先不傳。`);
  process.exit(1);
}
let fresh = 0, merged = 0, drops = 0, rejected = 0;
async function post(kills, relay) {
  for (let i = 0; i < kills.length; i += CHUNK) {
    const headers = { "content-type": "application/json", authorization: `Bearer ${token}` };
    if (relay) headers["x-amobi-relay"] = relay;
    const r = await fetch(`${base}/api/loot`, { method: "POST", headers, body: JSON.stringify({ client, kills: kills.slice(i, i + CHUNK) }) });
    const res = await r.json().catch(() => ({}));
    if (!r.ok && r.status !== 400) {
      console.error(`上傳失敗：HTTP ${r.status} ${res.error || ""}（重傳整份不會重複算）`);
      process.exit(1);
    }
    if (!r.ok) { rejected += kills.slice(i, i + CHUNK).length; continue; }   // 400：裡面沒有認得的首領
    fresh += res.fresh || 0; merged += res.merged || 0; drops += res.drops || 0; rejected += res.rejected || 0;
  }
}
if (mine.length) await post(mine, null);
for (const g of groups) await post(g.kills, createHmac("sha256", rosterKey).update(`loot:${g.who}`).digest("hex").slice(0, 16));
console.log(`完成：新的擊殺 ${fresh} 場、和之前（或別人回報）同一場 ${merged} 場、掉落 ${drops} 件`
  + (rejected ? `；${rejected} 場不是地城清單或團隊副本的首領，網站沒有收` : "") + "。");
console.log(`網址：${base}/report`);
