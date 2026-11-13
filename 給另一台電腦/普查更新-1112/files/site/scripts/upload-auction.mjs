// 從命令列上傳拍賣場物價（和普查的 upload-census.mjs 一樣：在這台電腦整理好，只送伺服器名、陣營、時間和數字，沒有任何名字）。
// 先用 tools\amobi_auction.py 把插件的存檔整理成 upload.json，再用這支上傳。上傳金鑰讀 D:\魔獸網站\.env 的 UPLOAD_TOKEN
// （--local 時讀 site\.dev.vars），不會印出來。
//
//   python ..\tools\amobi_auction.py <AmobiAuction.lua...> --json <upload.json>
//   node scripts/upload-auction.mjs <upload.json>              上傳到 https://wowamobi.com
//   node scripts/upload-auction.mjs <upload.json> --dry-run    只檢查、列出會上傳什麼
//   node scripts/upload-auction.mjs <upload.json> --local      上傳到本機 npm run dev（AMOBI_BASE 可以換網址，例如 http://127.0.0.1:8791）
//
// 每次送 1,000 筆（免費方案一次請求的 CPU 只有 10 ms；1,000 筆約 3 ms）。同一份再傳一次不會重複：同一天、同一件物品只留比較新的那筆。
import { readFileSync, statSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const site = join(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const file = args.find(a => !a.startsWith("--"));
const local = args.includes("--local");
const dry = args.includes("--dry-run");
const base = (process.env.AMOBI_BASE || (local ? "http://127.0.0.1:8787" : "https://wowamobi.com")).replace(/\/+$/, "");
const CHUNK = 1000;
const FACTION_ZH = { Alliance: "聯盟", Horde: "部落", Neutral: "中立" };
if (!file) {
  console.log("用法：node scripts/upload-auction.mjs <upload.json> [--dry-run] [--local]");
  process.exit(2);
}

const data = JSON.parse(readFileSync(file, "utf8"));
if (data.v !== 1 || !Array.isArray(data.scans) || !Array.isArray(data.days)) {
  console.error("這不是 tools\\amobi_auction.py 產生的 upload.json。");
  process.exit(1);
}
const groups = new Map();
for (const d of data.days) {
  const k = `${d.phase}|${d.realm}|${d.faction}`;
  const g = groups.get(k) || { ...d, n: 0, items: new Set(), days: new Set() };
  g.n++;
  g.items.add(d.item);
  g.days.add(d.day);
  groups.set(k, g);
}
const full = data.scans.filter(s => s.kind === "full" && !s.partial).length;
console.log(`掃描 ${data.scans.length} 次（全掃描 ${full} 次），每日資料 ${data.days.length.toLocaleString()} 筆：`);
for (const g of groups.values()) {
  const days = [...g.days].sort();
  console.log(`  ${g.phase === "beta" ? "封測" : "正式"} | ${g.realm} | ${FACTION_ZH[g.faction]} | ${g.items.size.toLocaleString()} 種物品 | `
    + `${days[0]}～${days.at(-1)}（${days.length} 天）`);
}
if (!data.scans.length && !data.days.length) { console.error("檔案裡沒有資料。"); process.exit(1); }
if (dry) process.exit(0);

const secrets = readFileSync(local ? join(site, ".dev.vars") : join(site, "..", ".env"), "utf8");
const token = /^UPLOAD_TOKEN=(.+)$/m.exec(secrets)?.[1]?.trim();
if (!token) {
  console.error(local ? "site\\.dev.vars 裡沒有 UPLOAD_TOKEN。" : "D:\\魔獸網站\\.env 裡沒有 UPLOAD_TOKEN，先執行 node scripts/set-upload-token.mjs。");
  process.exit(1);
}

const parts = Math.max(1, Math.ceil(data.days.length / CHUNK));
const files = [{ name: basename(file), size: statSync(file).size }];
let changed = 0, added = 0;
for (let i = 0; i < parts; i++) {
  const body = { v: 1, part: i + 1, files, scans: i === 0 ? data.scans : [], days: data.days.slice(i * CHUNK, (i + 1) * CHUNK) };
  const r = await fetch(`${base}/api/auction`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
  const res = await r.json().catch(() => ({}));
  if (!r.ok) {
    console.error(`第 ${i + 1}／${parts} 批上傳失敗：HTTP ${r.status} ${res.error || ""}（前面的批次已經寫進去了，重傳整份不會重複）`);
    process.exit(1);
  }
  changed += res.daysChanged || 0;
  added += res.scansAdded || 0;
  if (parts > 1) process.stdout.write(`  第 ${i + 1}／${parts} 批完成\r`);
}
if (parts > 1) process.stdout.write("\n");
console.log(`完成：新的掃描 ${added} 次，每日資料寫入或更新 ${changed.toLocaleString()} 筆（沒變的不會重寫）。`);
console.log(`網址：${base}/items/<物品編號>`);
