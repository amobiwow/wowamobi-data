// 從命令列上傳普查彙總（和上傳頁一樣：在這台電腦解析、去重、彙總，只送彙總數字，不送角色名）。
// 上傳金鑰讀 D:\魔獸網站\.env 的 UPLOAD_TOKEN（--local 時讀 site\.dev.vars），不會印出來。
//
//   node scripts/upload-census.mjs <存檔...>                  上傳到 https://wowamobi.com
//   node scripts/upload-census.mjs <存檔...> --dry-run        只解析、列出會上傳什麼
//   node scripts/upload-census.mjs <存檔...> --local          上傳到本機 npm run dev
//
// 同一個陣營有兩台電腦的存檔時，一次把兩個存檔都列上去，會先合併去重再上傳；不同陣營分開上傳也可以。
//
// 上傳完彙總，接著上傳普查深度數據（排行、公會、熱點、副本熱度、職業變化；scripts/upload-insights.mjs，角色名換成匿名代號）。
// 加 --no-insights 可以只傳彙總。
//
// --stage：先放網站的等待區（POST /api/census?stage=1，不公開；一台電腦部落、一台聯盟時用，老闆 10/24），
//          同一個伺服器兩個陣營都有一樣輪數的版本時網站才一起公開。這時不傳深度數據（公開後 tools/auto_upload.py 再傳）。
// --json：最後一行印網站的回應（JSON），給 tools/auto_upload.py 讀。
import { spawnSync } from "node:child_process";
import { readFileSync, statSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { buildSlices, FACTION_ZH, inRounds, readSaves, setNameRules } from "../public/assets/denizens.js";

const site = join(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const files = args.filter(a => !a.startsWith("--"));
const local = args.includes("--local");
const dry = args.includes("--dry-run");
const stage = args.includes("--stage");
const asJson = args.includes("--json");
const base = process.env.AMOBI_BASE || (local ? "http://127.0.0.1:8787" : "https://wowamobi.com");
if (!files.length) {
  console.log("用法：node scripts/upload-census.mjs <存檔...> [--dry-run] [--local] [--no-insights] [--only=Alliance|Horde] [--phase=beta|live]");
  process.exit(2);
}

setNameRules(JSON.parse(readFileSync(join(site, "public", "data", "name_lang.json"), "utf8")));
// --only=Alliance／Horde：只上傳一個陣營（老闆 10/21：兩個陣營的普查輪數要一樣，同一份存檔裡另一邊多跑的輪不上）
const only = (args.find(a => a.startsWith("--only=")) || "").slice(7) || null;
if (only && only !== "Alliance" && only !== "Horde") { console.error("--only 只能是 Alliance 或 Horde"); process.exit(2); }
// --phase=beta／live：只上傳封測或開服那一段（tools/auto_upload.py 用：一段兩個陣營輪數對不上時，另一段照傳）
const phase = (args.find(a => a.startsWith("--phase=")) || "").slice(8) || null;
if (phase && phase !== "beta" && phase !== "live") { console.error("--phase 只能是 beta 或 live"); process.exit(2); }
const realms = readSaves(files.map(f => ({ name: basename(f), data: readFileSync(f) }))).realms
  .filter(r => !only || r.faction === only);
const slices = buildSlices(realms).filter(s => (s.faction === "Alliance" || s.faction === "Horde") && (!phase || s.phase === phase));
// 只算最後一次被看到落在某一輪完整普查之內的角色（denizens.js 的 inRounds；老闆 10/19）：列出每個伺服器篩掉幾人
for (const r of realms.filter(r => r.faction === "Alliance" || r.faction === "Horde")) {
  const kept = inRounds(r.players, r.scans).length;
  if (kept < r.players.length) console.log(`${r.realm} | ${FACTION_ZH[r.faction]} | 存檔 ${r.players.length} 人，不在任何一輪完整普查內的 ${r.players.length - kept} 人不算（測試期間、輪和輪之間看到的）`);
}
for (const s of slices) {
  console.log(`${s.phase === "beta" ? "封測" : "亞服"} | ${s.realm} | ${FACTION_ZH[s.faction]} | 7 天內 ${s.counts.week} 人`
    + (s.phase === "beta" ? ` | 首頁「10/19 倒數三天」（10/18 18:00 起）${s.counts.camp ?? 0} 人` : "")
    + ` | 名字語言 ${Object.values(s.windows.week.langs || {}).reduce((a, b) => a + b, 0)} 人分成 ${Object.keys(s.windows.week.langs || {}).length} 類`);
}
if (!slices.length) { console.error("存檔裡沒有聯盟或部落的資料。"); process.exit(1); }
if (dry) process.exit(0);

const isLocal = local || /127\.0\.0\.1|localhost/.test(base);   // AMOBI_BASE 指到本機 npm run dev 時也用本機的金鑰
const secrets = readFileSync(isLocal ? join(site, ".dev.vars") : join(site, "..", ".env"), "utf8");
const token = /^UPLOAD_TOKEN=(.+)$/m.exec(secrets)?.[1]?.trim();
if (!token) {
  console.error(local ? "site\\.dev.vars 裡沒有 UPLOAD_TOKEN。" : "D:\\魔獸網站\\.env 裡沒有 UPLOAD_TOKEN，先執行 node scripts/set-upload-token.mjs。");
  process.exit(1);
}
const r = await fetch(`${base}/api/census${stage ? "?stage=1" : ""}`, {
  method: "POST",
  headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
  body: JSON.stringify({ slices, files: files.map(f => ({ name: basename(f), size: statSync(f).size })) }),
});
const body = await r.json().catch(() => ({}));
if (!r.ok) { console.error(`上傳失敗：HTTP ${r.status} ${body.error || ""}`); process.exit(1); }
const act = { added: "新增", replaced: "取代網站上的資料", "kept-newer": "網站上的比較新，略過",
              staged: "放進等待區（還沒公開）", same: "和網站上的一樣，略過" };
for (const x of body.results) console.log(`完成：${x.realm} ${FACTION_ZH[x.faction]}${x.rounds !== undefined ? ` ${x.rounds} 輪` : ""} ${act[x.action] || x.action}`);
for (const x of body.moved || []) console.log(`已公開：${x.realm} ${FACTION_ZH[x.faction]} ${x.rounds} 輪（兩個陣營輪數一樣，網站一起公開）`);
console.log(`網址：${base}/`);
if (asJson) console.log(JSON.stringify(body));

if (!args.includes("--no-insights") && !stage) {
  console.log("\n普查深度數據：");
  const r = spawnSync(process.execPath, [join(site, "scripts", "upload-insights.mjs"), ...files, ...(local ? ["--local"] : []), ...(only ? [`--only=${only}`] : []), ...(phase ? [`--phase=${phase}`] : [])], { stdio: "inherit" });
  if (r.status !== 0) { console.error("深度數據上傳失敗（彙總已經上傳好了），可以之後再執行 node scripts/upload-insights.mjs <存檔...>"); process.exit(1); }
}
