// 普查深度數據：把 DenizensTW 存檔和網站上已有的歷史合併，上傳排行、角色頁、公會、熱點、副本熱度、職業變化的資料。
// 在這台電腦算（public/assets/insights-sync.js），網站只負責存。上傳金鑰讀 D:\魔獸網站\.env（--local 時讀 site\.dev.vars），不會印出來。
//
//   node scripts/upload-insights.mjs <存檔...>              上傳到 https://wowamobi.com
//   node scripts/upload-insights.mjs <存檔...> --dry-run    不連網站，只算一次、列出會上傳什麼
//   node scripts/upload-insights.mjs <存檔...> --local      上傳到本機 npm run dev（--base=http://127.0.0.1:8791 可以換網址）
//
// 好幾個存檔時，依存檔時間從舊到新一個一個上傳：這樣舊存檔裡的等級也會留在時間軸上（例如先 10/18 再 10/19）。
// 同一份存檔重複上傳不會重複計算（比網站上舊的觀察會略過）。
//
// 角色名：老闆決定公開之前，預設在這台電腦換成匿名代號再上傳（網站上沒有任何角色名）。代號的密鑰是 .env 的 INSIGHTS_SALT，
// 第一次執行會自動產生一組存進去（不印出來）。老闆同意公開角色名之後才加 --names（網站上原本的匿名資料要先刪掉、從舊到新重傳）。
import { randomBytes } from "node:crypto";
import { appendFileSync, readFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { FACTION_ZH, inRounds, readSaves } from "../public/assets/denizens.js";
import { phaseOf, syncInsights } from "../public/assets/insights-sync.js";
import { cutRounds, roundsArg } from "./census-rounds.mjs";

const site = join(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const files = args.filter(a => !a.startsWith("--"));
const local = args.includes("--local");
const dry = args.includes("--dry-run");
const names = args.includes("--names");
// --only=Alliance／Horde：只上傳一個陣營（老闆 10/21：兩個陣營的普查輪數要一樣，同一份存檔裡另一邊多跑的輪不上）
const only = (args.find(a => a.startsWith("--only=")) || "").slice(7) || null;
if (only && only !== "Alliance" && only !== "Horde") { console.error("--only 只能是 Alliance 或 Horde"); process.exit(2); }
// --phase=beta／live：只上傳封測或開服那一段（依最後一次看到的時間分，和 insights-sync.js 一樣）
const phase = (args.find(a => a.startsWith("--phase=")) || "").slice(8) || null;
if (phase && phase !== "beta" && phase !== "live") { console.error("--phase 只能是 beta 或 live"); process.exit(2); }
// --rounds=N：開服那段只算前 N 輪（和 upload-census.mjs 同一個切法，census-rounds.mjs）
const rounds = roundsArg(args);
// --fresh：不接網站上原本的歷史，從第一份存檔重新算、整份蓋掉（老闆 11/6 普查改回 7 輪：網站上的深度數據已經混進第 8～11 輪）。
// 每個伺服器＋陣營的資料列（角色 256 包、公會 32 包、彙總）是固定的，全部重寫就等於換掉，不用先刪
const fresh = args.includes("--fresh");
const base = (args.find(a => a.startsWith("--base=")) || "").slice(7) || process.env.AMOBI_BASE || (local ? "http://127.0.0.1:8787" : "https://wowamobi.com");
if (!files.length) {
  console.log("用法：node scripts/upload-insights.mjs <存檔...> [--dry-run] [--local] [--base=網址] [--names] [--only=Alliance|Horde] [--phase=beta|live] [--rounds=N] [--fresh]");
  process.exit(2);
}

const isLocal = local || /127\.0\.0\.1|localhost/.test(base);
const secretsFile = isLocal ? join(site, ".dev.vars") : join(site, "..", ".env");
const secret = key => new RegExp(`^${key}=(.+)$`, "m").exec(readFileSync(secretsFile, "utf8"))?.[1]?.trim();

// 匿名代號的密鑰：沒有就產生一組存進 .env（或本機的 .dev.vars），不印出來
function salt() {
  let v = secret("INSIGHTS_SALT");
  if (!v) {
    v = randomBytes(24).toString("hex");
    appendFileSync(secretsFile, `\n# 普查深度數據的匿名代號密鑰（不要改、不要外流；弄丟了代號會全部變掉）\nINSIGHTS_SALT=${v}\n`);
    console.log(`已產生匿名代號的密鑰，存在 ${isLocal ? "site\\.dev.vars" : "D:\\魔獸網站\\.env"}（INSIGHTS_SALT）`);
  }
  return v;
}

const zones = JSON.parse(readFileSync(join(site, "public", "data", "zones.json"), "utf8"));
const saves = files.map(f => {
  // 和普查彙總一樣（denizens.js 的 buildSlices）：開服後撈到的不重複角色全部算（老闆 11/6 晚上：「現在不要管輪數了」）；
  // 開服前只算最後一次被看到落在某一輪完整普查之內的（inRounds；老闆 10/19 刪掉測試取樣）
  const all = readSaves([{ name: basename(f), data: readFileSync(f) }]).realms;
  if (rounds) cutRounds(all.filter(r => !only || r.faction === only), rounds);
  const keep = r => { const k = new Set(inRounds(r.players, r.scans)); return r.players.filter(p => phaseOf(p.last) === "live" || k.has(p)); };
  const realms = all
    .map(r => { const players = keep(r); return { ...r, players, dropped: r.players.length - players.length }; })
    .map(r => (phase ? { ...r, players: r.players.filter(p => phaseOf(p.last) === phase) } : r))
    .filter(r => r.players.length)
    .filter(r => !only || r.faction === only);
  const snapshot = realms.reduce((m, r) => r.players.reduce((mm, p) => Math.max(mm, p.last || 0), m), 0);
  return { file: f, realms, snapshot };
}).sort((a, b) => a.snapshot - b.snapshot);

const token = dry ? null : secret("UPLOAD_TOKEN");
if (!dry && !token) {
  console.error(local ? "site\\.dev.vars 裡沒有 UPLOAD_TOKEN。" : "D:\\魔獸網站\\.env 裡沒有 UPLOAD_TOKEN，先執行 node scripts/set-upload-token.mjs。");
  process.exit(1);
}

const tw = sec => new Date(sec * 1000 + 8 * 3600e3).toISOString().slice(5, 16).replace("T", " ");
for (const [i, s] of saves.entries()) {
  console.log(`${basename(dirname(s.file))}\\${basename(s.file)}（最後看到 ${tw(s.snapshot)}）`);
  for (const r of s.realms) if (r.dropped) console.log(`  ${r.realm} | ${FACTION_ZH[r.faction]} | 開服前看到、不在任何一輪完整普查內的 ${r.dropped} 人不算（封測、壓測期間的測試取樣）`);
  if (!s.realms.length) { console.log("  沒有完整普查內看到的角色，略過"); continue; }
  try {
    await syncInsights(s.realms, {
      base, token, zones, dryRun: dry, names, salt: names ? null : salt(), fresh: fresh && i === 0,
      log: m => console.log(`  ${m.phase === "beta" ? "封測" : m.phase === "live" ? "亞服" : m.phase} | ${m.realm} | ${FACTION_ZH[m.faction]}`
        + ` | 新角色 ${m.added}、更新 ${m.updated} | 網站上共 ${m.chars} 人（7 天內 ${m.active}）`
        + ` | 看到兩次以上 ${m.multi} 人、算得出升級速度 ${m.speedN} 人 | 第 ${m.uploads} 次上傳 | ${m.names ? "具名" : "匿名代號"}`),
    });
  } catch (err) {
    console.error(`上傳失敗：${err.message}`);
    process.exit(1);
  }
}
if (!dry) console.log(`網址：${base}/census/ranks`);
