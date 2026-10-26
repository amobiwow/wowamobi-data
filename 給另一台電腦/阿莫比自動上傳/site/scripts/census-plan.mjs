// 普查自動上傳前的檢查（tools/auto_upload.py 用；老闆 10/24：「普查照規則（完整輪、兩個陣營輪數一樣），對不上就先不傳」）。
// 讀存檔、讀網站上現有的普查彙總（GET /api/census）和等待區（GET /api/census/staged，站長金鑰），
// 算出每一段（封測／開服）每個伺服器＋陣營：存檔的是不是新的、網站上公開的幾輪、等待區有哪些版本。只印 JSON，不上傳任何東西。
//
//   node scripts/census-plan.mjs <存檔...>                   和 https://wowamobi.com 比
//   node scripts/census-plan.mjs --status                    只印等待區和公開的輪數（不用存檔）
//   node scripts/census-plan.mjs <存檔...> --site=<檔案.json> [--staged=<檔案.json>]   和存好的回應比（測試用）
//   AMOBI_BASE=http://127.0.0.1:8787 或 --local              和本機 npm run dev 比（金鑰讀 site\.dev.vars）
//
// 每個伺服器＋陣營：網站上沒有、或存檔的比較新（snapshot 一樣大也算，和 POST /api/census 一樣）→ 上傳後用存檔的輪數；
// 網站上的比較新 → 網站不會換，用網站的輪數。輪數＝沒有取消、查全部等級的輪（denizens.js 的 buildSlices，和網站一樣）。
// 一台電腦部落、一台聯盟（老闆 10/24）：存檔先放網站的等待區，兩個陣營有一樣輪數的版本時網站才一起公開（src/census.js）。
import { readFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { buildSlices, readSaves, setNameRules } from "../public/assets/denizens.js";

const site = join(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const files = args.filter(a => !a.startsWith("--"));
const opt = name => (args.find(a => a.startsWith(`--${name}=`)) || "").slice(name.length + 3) || null;
const local = args.includes("--local");
const base = process.env.AMOBI_BASE || (local ? "http://127.0.0.1:8787" : "https://wowamobi.com");
const status = args.includes("--status");
if (!files.length && !status) {
  console.error("用法：node scripts/census-plan.mjs <存檔...> | --status [--site=<檔案.json>] [--staged=<檔案.json>] [--local]");
  process.exit(2);
}

async function get(path, owner = false) {
  const headers = { "cache-control": "no-cache" };
  if (owner) {
    const isLocal = local || /127\.0\.0\.1|localhost/.test(base);
    const secrets = readFileSync(isLocal ? join(site, ".dev.vars") : join(site, "..", ".env"), "utf8");
    const token = /^UPLOAD_TOKEN=(.+)$/m.exec(secrets)?.[1]?.trim();
    if (!token) { console.error(".env 裡沒有 UPLOAD_TOKEN"); process.exit(1); }
    headers.authorization = `Bearer ${token}`;
  }
  const r = await fetch(base + path, { headers });
  if (!r.ok) { console.error(`讀不到網站上的普查資料（${path}）：HTTP ${r.status}`); process.exit(1); }
  return r.json();
}
const readJson = f => JSON.parse(readFileSync(f, "utf8"));

const st = opt("staged") ? readJson(opt("staged")) : opt("site") ? { staged: [], site: [] } : await get("/api/census/staged", true);
if (status) {
  console.log(JSON.stringify({ staged: st.staged || [], site: st.site || [] }));
  process.exit(0);
}

setNameRules(JSON.parse(readFileSync(join(site, "public", "data", "name_lang.json"), "utf8")));
const realms = readSaves(files.map(f => ({ name: basename(f), data: readFileSync(f) }))).realms;
const mine = buildSlices(realms).filter(s => s.faction === "Alliance" || s.faction === "Horde");

const online = opt("site") ? readJson(opt("site")) : await get("/api/census");
const key = s => `${s.phase}|${s.realm}|${s.faction}`;
const have = new Map((online.slices || []).map(s => [key(s), { rounds: s.data?.rounds?.n ?? 0, snapshot: s.snapshot, week: s.data?.counts?.week ?? 0,
  ats: (s.data?.scans || []).map(x => x.at).filter(Number.isInteger) }]));
const waiting = new Map();
for (const s of st.staged || []) {
  if (!waiting.has(key(s))) waiting.set(key(s), []);
  waiting.get(key(s)).push({ rounds: s.rounds, snapshot: s.snapshot });
}
// 網站上這個伺服器＋陣營最近幾輪裡，有幾輪是這台的存檔沒有的（另一台電腦傳的）。網站一次是整份換掉、不是相加，
// 這台傳上去會把那幾輪蓋掉（老闆 10/24：另一台電腦也要自動上傳）。只比這台存檔最早那一輪之後的（更早的可能被插件刪了，插件最多留 500 筆）
const foreignOf = (s, old) => {
  const mineAts = s.scans.map(x => x.at).filter(Number.isInteger);
  if (!old || !mineAts.length) return old ? old.ats.length : 0;
  const set = new Set(mineAts), from = Math.min(...mineAts);
  return old.ats.filter(at => at >= from && !set.has(at)).length;
};

const phases = [];
for (const phase of ["beta", "live"]) {
  const before = { Alliance: 0, Horde: 0 }, after = { Alliance: 0, Horde: 0 };
  for (const [k, v] of have) {
    const [p, , faction] = k.split("|");
    if (p === phase && faction in before) { before[faction] += v.rounds; after[faction] += v.rounds; }
  }
  const slices = [];
  for (const s of mine.filter(s => s.phase === phase)) {
    const old = have.get(key(s));
    let action = !old ? "added" : s.snapshot > old.snapshot ? "replaced" : s.snapshot === old.snapshot ? "same" : "kept-newer";
    if (action === "added" || action === "replaced" || action === "same") after[s.faction] += s.rounds.n - (old?.rounds ?? 0);
    const staged = waiting.get(key(s)) || [];
    if ((action === "added" || action === "replaced") && staged.some(w => w.rounds === s.rounds.n && w.snapshot === s.snapshot)) action = "staged-same";
    slices.push({ realm: s.realm, faction: s.faction, rounds: s.rounds.n, week: s.counts.week, snapshot: s.snapshot, action,
      foreign: action === "kept-newer" ? 0 : foreignOf(s, old), staged,
      site: old ? { rounds: old.rounds, snapshot: old.snapshot, week: old.week } : null });
  }
  // 存檔和網站一樣（snapshot 和輪數都一樣）、或已經放在等待區的，就不用再送
  const changed = slices.some(s => s.action === "added" || s.action === "replaced" || (s.action === "same" && s.rounds !== s.site.rounds));
  // 等待區裡另一個陣營（這台存檔沒有的）有哪些輪數
  const others = {};
  for (const [k, list] of waiting) {
    const [p, realm, faction] = k.split("|");
    if (p === phase && !slices.some(s => s.realm === realm && s.faction === faction)) others[`${realm}|${faction}`] = list.map(w => w.rounds);
  }
  if (slices.length) phases.push({ phase, changed, before, after, slices, others });
}
console.log(JSON.stringify({ phases }));
