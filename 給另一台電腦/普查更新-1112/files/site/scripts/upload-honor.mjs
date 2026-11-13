// 從命令列上傳全服戰績（老闆 11/8：「不可能全部人都裝我的UI…有其他辦法嗎」→「繼續」；tools/auto_upload.py 用）。
// 讀阿莫比公會名單插件的存檔 AmobiGuild.lua 的 honor 表：小幫手 1.21.0 用遊戲的「觀察」查到的身邊玩家（兩個陣營）的
// 總榮譽擊殺、今天的榮譽擊殺、軍銜（R1，格式見 addon/AmobiCompanion/Honor.lua；AmobiGuild 1.6.0 併成每人一筆）。
// 送到 POST /api/pvp/honor（帶 .env 的 UPLOAD_TOKEN，不會印出來），一次 1000 人；網站每人留最新查到的，重傳不會重複算。
// 遊戲給的 9 個數字照觀察視窗（Blizzard_InspectUI/Camelot/InspectPVPFrame.lua）的用法解：
//   第 1 個今天的榮譽擊殺、第 5 個總榮譽擊殺、第 7 個軍銜、第 8、9 個軍銜進度；全部也原樣存一份（raw）。
// 只傳 11/5 07:00 開服後查到的（--all 測試用，開服前的也傳）。
//
//   node scripts/upload-honor.mjs <AmobiGuild.lua...>              上傳到 https://wowamobi.com
//   node scripts/upload-honor.mjs <...> --dry-run   只檢查；最後一行印 JSON {players, alliance, horde, beta, sig}
//   node scripts/upload-honor.mjs <...> --local     上傳到本機 npm run dev
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
const CHUNK = 1000;

const isMap = v => v instanceof Map;
const entries = v => (isMap(v) ? [...v.entries()] : []);
const n36 = x => (x === "" || x == null ? null : Number.parseInt(x, 36));

// AmobiGuildDB.honor → [{realm, name, faction, cls, lv, guild, life, today, rank, cur, next, raw, t}]
export function readHonor(guild) {
  const out = [];
  for (const [realm, r] of entries(guild?.get("honor"))) {
    if (!isMap(r)) continue;
    for (const [name, p] of entries(r.get("players"))) {
      if (!isMap(p)) continue;
      const v = String(p.get("v") || "").split(",").map(n36);
      const t = Number(p.get("last")), fa = p.get("fa");
      if (!Number.isInteger(t) || (fa !== "A" && fa !== "H") || !Number.isInteger(v[4])) continue;
      const lv = Number(p.get("lvl"));
      out.push({ realm: String(realm), name: String(name), faction: fa === "H" ? "Horde" : "Alliance",
                 cls: p.get("token") || null, lv: Number.isInteger(lv) && lv > 0 ? lv : null, guild: p.get("guild") || null,
                 life: v[4], today: v[0], rank: v[6], cur: v[7], next: v[8],
                 raw: v.map(x => (Number.isInteger(x) ? String(x) : "")).join(","), t });
    }
  }
  return out;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (!files.length) {
    console.error("用法：node scripts/upload-honor.mjs <AmobiGuild.lua...> [--dry-run] [--local] [--all]");
    process.exit(2);
  }
  const byKey = new Map();
  let beta = 0;
  for (const f of files) {
    const guild = parseSavedVariables(readFileSync(f)).get("AmobiGuildDB");
    if (!isMap(guild)) continue;
    for (const p of readHonor(guild)) {
      if (p.t < LAUNCH_TS && !all) { beta++; continue; }
      const k = `${p.realm}|${p.name}`, old = byKey.get(k);
      if (!old || p.t > old.t) byKey.set(k, p);
    }
  }
  const players = [...byKey.values()].sort((a, b) => (a.realm + a.name < b.realm + b.name ? -1 : 1));
  const ally = players.filter(p => p.faction === "Alliance").length, horde = players.length - ally;
  const sig = createHash("sha256").update(JSON.stringify(players)).digest("hex");
  console.log(`小幫手查到的戰績：${players.length} 人（聯盟 ${ally}、部落 ${horde}）` + (beta ? `；開服前的 ${beta} 人不傳` : ""));
  if (dry) {
    console.log(JSON.stringify({ players: players.length, alliance: ally, horde, beta, sig }));
    process.exit(0);
  }
  if (!players.length) process.exit(0);
  const secrets = readFileSync(local ? join(site, ".dev.vars") : join(site, "..", ".env"), "utf8");
  const token = new RegExp("^UPLOAD_TOKEN=(.+)$", "m").exec(secrets)?.[1]?.trim();
  if (!token) {
    console.error(local ? "site\\.dev.vars 裡沒有 UPLOAD_TOKEN。" : ".env 裡沒有 UPLOAD_TOKEN。");
    process.exit(1);
  }
  let changed = 0, rejected = 0;
  for (let i = 0; i < players.length; i += CHUNK) {
    const r = await fetch(`${base}/api/pvp/honor`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
      body: JSON.stringify({ players: players.slice(i, i + CHUNK) }),
    });
    const res = await r.json().catch(() => ({}));
    if (!r.ok && r.status !== 400) {
      console.error(`上傳失敗：HTTP ${r.status} ${res.error || ""}（重傳整份不會重複算）`);
      process.exit(1);
    }
    if (!r.ok) { rejected += players.slice(i, i + CHUNK).length; continue; }
    changed += res.changed || 0;
    rejected += res.rejected || 0;
  }
  console.log(`完成：更新 ${changed} 人（其他人和網站上的一樣新）` + (rejected ? `、格式不對沒收 ${rejected} 人` : "") + "。");
}
