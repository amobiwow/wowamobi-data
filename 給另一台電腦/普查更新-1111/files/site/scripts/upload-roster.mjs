// 從命令列上傳公會名單給競拍場（/bid 開單限公會成員；老闆 10/25：「判斷要登錄的人的名字在我的工會，就可以使用了」）。
// 名單來自阿莫比公會名單插件的存檔（AmobiGuildDB.guild，addon/AmobiGuild 在遊戲裡讀公會名單存的；只裝在老闆的電腦）。
// 名字不會傳出去：每個名字先用 ROSTER_KEY 做 HMAC（跟網站 src/bid.js 的 rosterHash 一樣），網站只存這串亂碼；
// 鑰匙 ROSTER_KEY 和站長上傳金鑰 UPLOAD_TOKEN 都在 D:\魔獸網站\.env，不會印出來。tools/auto_upload.py 用。
// 只傳 11/5 07:00 開服後讀到的名單（封測、壓測的角色不算）；只用聯盟的（老闆：「我的公會只有聯盟」），好幾份時用最新的。
// 部落帳號也裝 AmobiGuild 收部落的榮譽擊殺（10/26），那邊的部落公會名單不傳，不然會蓋掉競拍場的聯盟名單。
// 網站每個公會各一份（11/10 起：阿莫比聯盟滿 1000 人，拉克開了「阿莫比聯萌」，兩個公會都要 Discord 認證），每次換掉同一個公會的那份：
// 退出公會的人下次上傳後就不能開單。存檔裡有好幾個聯盟公會的名單（不同帳號、角色）就每個公會傳最新的一份。
// 職業（AmobiGuild 1.4.0 起有）跟著加密後的名字一起傳：Discord「正式公會成員」要比對「名字丨職業」（src/discord-roles.js）。
//
//   node scripts/upload-roster.mjs <AmobiGuild.lua...>             上傳到 https://wowamobi.com
//   node scripts/upload-roster.mjs <AmobiGuild.lua...> --dry-run   只檢查；最後一行印 JSON {guild, members, at, beta, sig}
//   node scripts/upload-roster.mjs <AmobiGuild.lua...> --local     上傳到本機 npm run dev
import { createHash, createHmac } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { rosterKey } from "../public/assets/bid-calc.js";
import { LAUNCH_TS, parseSavedVariables } from "../public/assets/denizens.js";

const site = join(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const files = args.filter(a => !a.startsWith("--"));
const local = args.includes("--local");
const dry = args.includes("--dry-run");
const all = args.includes("--all");   // 測試用：開服前讀到的名單也傳
const base = local ? "http://127.0.0.1:8787" : "https://wowamobi.com";
if (!files.length) {
  console.error("用法：node scripts/upload-roster.mjs <AmobiGuild.lua...> [--dry-run] [--local]");
  process.exit(2);
}

const isMap = v => v instanceof Map;
const list = v => (Array.isArray(v) ? v : isMap(v) ? [...v.values()] : []);
const found = [];
let beta = 0;
for (const f of files) {
  let db;
  try { db = parseSavedVariables(readFileSync(f)).get("AmobiGuildDB"); } catch (e) {
    console.error(`讀不懂 ${f}：${e.message}`);
    continue;
  }
  const g = isMap(db) ? db.get("guild") : null;
  if (!isMap(g)) continue;
  const at = Number(g.get("at")) || 0;
  if (at < LAUNCH_TS && !all) { beta++; continue; }
  const realm = String(g.get("realm") || "");
  const suffixes = realm ? [`-${realm}`, `-${realm.replace(/\s+/g, "")}`] : [];
  const bare = n => {
    for (const s of suffixes) if (n.endsWith(s)) return n.slice(0, -s.length);   // 「名字-伺服器」只留名字
    return n;
  };
  const names = list(g.get("members")).filter(n => typeof n === "string").map(n => bare(n).trim()).filter(Boolean);
  // 職業（AmobiGuild 1.4.0 起；Discord 身分組要比對「名字丨職業」）：rosterKey → 遊戲的職業編號
  const classes = new Map();
  const cg = g.get("classes");
  if (isMap(cg)) for (const [n, c] of cg) if (typeof n === "string" && Number.isInteger(c)) classes.set(rosterKey(bare(n).trim()), c);
  if (names.length) found.push({ file: f, guild: String(g.get("name") || "").trim(), faction: String(g.get("faction") || ""), at, names, classes });
}
found.sort((a, b) => b.at - a.at);
// 每個聯盟公會留最新的一份
const picks = [];
for (const x of found) if (x.guild && x.faction === "Alliance" && !picks.some(p => p.guild === x.guild)) picks.push(x);
if (!picks.length) {
  console.log(found.length ? `只有部落的公會名單（${found.length} 份），不傳（競拍場只用聯盟的公會）`
    : beta ? `只有開服前讀到的公會名單（${beta} 份），不傳` : "存檔裡沒有公會名單（要裝阿莫比公會名單插件 AmobiGuild，在公會裡登入一次）");
  if (dry) console.log(JSON.stringify({ guild: null, members: 0, at: 0, beta, sig: null }));
  process.exit(0);
}
for (const pick of picks) {
  if (pick.names.length > 1000) {
    console.error(`公會「${pick.guild}」名單 ${pick.names.length} 人，超過網站上限 1000 人`);
    process.exit(1);
  }
  pick.keys = [...new Set(pick.names.map(rosterKey))].sort();
  pick.cls = pick.keys.map(k => pick.classes.get(k) ?? null);
  pick.withClass = pick.cls.filter(c => c != null).length;
  const when = new Date((pick.at + 8 * 3600) * 1000).toISOString().slice(5, 16).replace("-", "/").replace("T", " ");
  console.log(`公會「${pick.guild}」${pick.keys.length} 人、${pick.withClass} 人有職業（${when} 在遊戲裡讀到）`
    + (pick.withClass ? "" : "\n  沒有職業：AmobiGuild 要更新到 1.4.0，在遊戲裡再讀一次名單（Discord 身分組只比名字，不受影響）"));
}
const skipped = found.length - picks.length;
if (skipped) console.log(`另外 ${skipped} 份比較舊或是部落的不用`);
const sig = createHash("sha256").update(JSON.stringify(picks.map(p => [p.guild, p.keys, p.cls]))).digest("hex");
if (dry) {
  console.log(JSON.stringify({ guild: picks.map(p => p.guild).join("、"), members: picks.reduce((n, p) => n + p.keys.length, 0),
                               classes: picks.reduce((n, p) => n + p.withClass, 0), at: Math.max(...picks.map(p => p.at)), beta, sig }));
  process.exit(0);
}

const secrets = readFileSync(local ? join(site, ".dev.vars") : join(site, "..", ".env"), "utf8");
const read = k => new RegExp(`^${k}=(.+)$`, "m").exec(secrets)?.[1]?.trim();
const token = read("UPLOAD_TOKEN"), rk = read("ROSTER_KEY");
if (!token || !rk) {
  console.error(`${local ? "site\\.dev.vars" : ".env"} 裡沒有 ${!token ? "UPLOAD_TOKEN" : "ROSTER_KEY"}（ROSTER_KEY 用 node scripts/set-roster-key.mjs 產生）。`);
  process.exit(1);
}
for (const pick of picks) {
  const hashes = pick.keys.map(k => createHmac("sha256", rk).update(k).digest("hex"));
  const classes = Object.fromEntries(hashes.map((h, i) => [h, pick.cls[i]]).filter(([, c]) => c != null));
  const r = await fetch(`${base}/api/bid/roster`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
    body: JSON.stringify({ guild: pick.guild, at: pick.at, hashes, classes }),
  });
  const res = await r.json().catch(() => ({}));
  if (!r.ok) {
    console.error(`「${pick.guild}」上傳失敗：HTTP ${r.status} ${res.error || ""}`);
    process.exit(1);
  }
  const all = Array.isArray(res.guilds) && res.guilds.length > 1 ? `（網站上全部：${res.guilds.map(g => `${g.guild} ${g.count} 人`).join("、")}）` : "";
  console.log(`完成：網站上「${res.guild}」的名單換成 ${res.count} 人${all}。網址：${base}/bid`);
}
