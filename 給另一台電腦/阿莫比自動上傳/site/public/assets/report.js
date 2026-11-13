// 回報掉落（/report）：在瀏覽器裡解析掉落記錄插件的存檔 AmobiLoot.lua，只把首領擊殺和掉落的數字送到 /api/loot。
// 送出去的：伺服器名稱、首領、副本、難度、人數、時間、副本分身編號、有沒有打開屍體、物品和數量。不送 GUID、小怪的掉落、物品名稱。
import { LuaSyntaxError, parseSavedVariables } from "./denizens.js?v=2aca4898";

const $ = id => document.getElementById(id);
const STORE = "amobi-upload-key";   // 站長上傳頁記住的上傳金鑰：有的話一起送，站長的回報直接算數
const isMap = v => v instanceof Map;
const list = v => (Array.isArray(v) ? v : isMap(v) ? [...v.values()] : []);
const num = v => (typeof v === "number" && Number.isFinite(v) ? v : null);

// 物品表 {物品編號: 數量}（Lua 的表讀進來是 Map；剛好是 1..n 的會變成陣列）
function counts(t) {
  const out = new Map();
  const add = (k, v) => { const id = Number(k), n = num(v); if (Number.isInteger(id) && id > 0 && n > 0) out.set(id, Math.round(n)); };
  if (isMap(t)) for (const [k, v] of t) add(k, v);
  else if (Array.isArray(t)) t.forEach((v, i) => add(i + 1, v));
  return out;
}

/** AmobiLootDB → 每一場首領擊殺：[{enc, map, diff, size, t, realm, copy, full, items: [[物品, 數量]]}] */
export function extractLoot(sv) {
  const db = sv.get("AmobiLootDB");
  if (!isMap(db)) throw new Error("這個檔案裡沒有 AmobiLootDB，不是阿莫比掉落記錄插件的存檔");
  // 屍體、寶箱的掉落：插件記下時就標好是哪一次擊殺（enc＋kt）
  const attached = new Map();
  if (isMap(db.get("loot"))) {
    for (const rec of db.get("loot").values()) {
      if (!isMap(rec) || !["boss", "chest"].includes(rec.get("how"))) continue;
      const key = `${rec.get("enc")}|${rec.get("kt")}`;
      if (!attached.has(key)) attached.set(key, []);
      attached.get(key).push(rec);
    }
  }
  const client = isMap(db.get("client")) ? db.get("client") : new Map();
  const kills = [];
  for (const k of list(db.get("kills"))) {
    if (!isMap(k)) continue;
    const enc = num(k.get("enc")), t = num(k.get("t"));
    if (!enc || !t) continue;
    const recs = attached.get(`${enc}|${t}`) || [];
    const items = new Map();
    for (const rec of recs) for (const [id, n] of counts(rec.get("items"))) items.set(id, (items.get(id) || 0) + n);
    for (const [id, n] of [...counts(k.get("rolls")), ...counts(k.get("awarded"))]) items.set(id, Math.max(items.get(id) || 0, n));
    const copy = k.get("copy") ?? recs.map(r => r.get("copy")).find(c => c !== undefined && c !== null);
    kills.push({ enc, map: num(k.get("map")), diff: num(k.get("diff")), size: num(k.get("size")), t: Math.floor(t),
                 realm: typeof k.get("realm") === "string" ? k.get("realm") : "", copy: copy === undefined || copy === null ? null : String(copy),
                 full: recs.length > 0, items: [...items].slice(0, 40) });
  }
  return { kills, client: { build: String(client.get("build") ?? ""), version: String(client.get("version") ?? ""),
                            addon: String(client.get("addon") ?? "") } };
}

function show(html, kind = "") {
  const el = $("rp-result");
  el.hidden = false;
  el.className = "rp-result" + (kind ? " " + kind : "");
  el.innerHTML = html;
}

async function upload(file) {
  let data;
  try {
    data = extractLoot(parseSavedVariables(await file.arrayBuffer()));
  } catch (err) {
    const why = err instanceof LuaSyntaxError ? `存檔格式錯誤：${err.message}` : err.message;
    show(`<b>${file.name}</b>：${why}`, "bad");
    return;
  }
  if (!data.kills.length) {
    show(`<b>${file.name}</b>：還沒有記到首領擊殺。打完首領、登出以後再上傳。`, "bad");
    return;
  }
  const n = data.kills.length, items = data.kills.reduce((a, k) => a + k.items.length, 0);
  show(`<b>${file.name}</b>：${n} 場首領擊殺、${items} 件掉落，上傳中…`);
  const headers = { "content-type": "application/json" };
  try { const key = localStorage.getItem(STORE) || sessionStorage.getItem(STORE); if (key) headers.authorization = `Bearer ${key}`; } catch { /* 沒有就算了 */ }
  // 一次最多送 1000 場（新的先送）
  const kills = data.kills.sort((a, b) => b.t - a.t).slice(0, 1000);
  try {
    const r = await fetch("/api/loot", { method: "POST", headers, body: JSON.stringify({ client: data.client, kills }) });
    const res = await r.json().catch(() => ({}));
    if (!r.ok) { show(`<b>${file.name}</b>：${res.error || `上傳失敗（${r.status}）`}`, "bad"); return; }
    const beta = res.kills - res.live;
    show(`<b>${file.name}</b>：上傳好了，謝謝！${res.kills} 場首領擊殺裡，新的 ${res.fresh} 場、和別人回報的同一場 ${res.merged} 場；`
      + `${res.drops} 件掉落。${beta > 0 ? `其中 ${beta} 場是開服前（封測、壓測）的，會存著但不放上物品頁。` : ""}`
      + `${res.rejected ? `另外 ${res.rejected} 場不是地城清單或團隊副本的首領，沒有收。` : ""}`, "ok");
    stats();
  } catch {
    show(`<b>${file.name}</b>：連不上網站，請稍後再試`, "bad");
  }
}

async function stats() {
  try {
    const s = await (await fetch("/api/loot/stats")).json();
    if (s.kills > 0) $("rp-stats").textContent = `開服後大家一共記到 ${s.kills.toLocaleString("en-US")} 場首領擊殺（${s.bosses} 個首領）、${s.drops.toLocaleString("en-US")} 件掉落，${s.people} 位玩家幫忙回報。`;
  } catch { /* 讀不到就維持原本的字 */ }
}

function init() {
  const input = $("rp-file"), drop = $("rp-drop");
  if (!input) return;
  const run = async files => { for (const f of files) await upload(f); };
  input.addEventListener("change", () => run([...input.files]));
  drop.addEventListener("dragover", e => { e.preventDefault(); drop.classList.add("on"); });
  drop.addEventListener("dragleave", () => drop.classList.remove("on"));
  drop.addEventListener("drop", e => { e.preventDefault(); drop.classList.remove("on"); run([...e.dataTransfer.files]); });
  stats();
}
if (typeof document !== "undefined") {   // 測試會在 Node 裡直接載入 extractLoot
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
}
