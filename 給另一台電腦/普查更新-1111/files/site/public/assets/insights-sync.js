// 普查深度數據的上傳端：把 DenizensTW 存檔和網站上已經累積的歷史合併，算好排行、公會、熱點、副本熱度、職業變化，
// 再上傳到 D1（ins_rows、ins_names）。在站長的電腦執行（scripts/upload-insights.mjs、upload-census.mjs；之後也可以給上傳頁用），
// Worker 只負責存和讀，不用在伺服器上算（免費方案每個請求只有 10 毫秒 CPU）。
//
// 為什麼要累積：插件每個角色只存「最後一次看到」的等級、公會、區域。每次上傳都記下（角色, 等級, 公會, 時間），
// 疊幾次之後才算得出：第一次看到他到幾級的時間、升級速度、公會進出、各區域每天被看到的人次。
//
// 隱私：角色資料只存 /誰 公開看得到的欄位和我們看到的時間，不存所在區域（區域只拿來算熱點的人次）；
// 申請移除的角色（ins_hidden）一開始就排除，不進任何排行、公會名單、統計。

import { isFullRound, LAUNCH_TS } from "./denizens.js";
import { NB_CHAR, NB_GUILD, bucketOf, nameKey, twDate } from "./insights-keys.js";

// 階段：依「最後一次看到」的時間分。cap＝這個階段的等級上限（封測 30、開服 60），排行「最先到滿等」用。
// 之後有新的階段（例如新賽季、新伺服器群）在這裡加一筆就好。
export const PHASES = [
  { id: "beta", from: 0, cap: 30 },
  { id: "live", from: LAUNCH_TS, cap: 60 },
];
export const phaseOf = t => PHASES.reduce((cur, p) => (t >= p.from ? p : cur), PHASES[0]).id;
export const capOf = id => (PHASES.find(p => p.id === id) || PHASES[PHASES.length - 1]).cap;

export const CLASS_ORDER = ["WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"];
const DAY = 86400;
const ACTIVE = 7 * DAY;          // 公會人數、職業變化：7 天內看到的角色（和普查頁一樣）
const MIN_SPAN = 12 * 3600;      // 升級速度：第一次和最後一次看到至少隔 12 小時才算
const MIN_PCT_N = 30;            // 算得出速度的角色少於 30 個時，不寫「比幾 % 的人快」
const RAW_DAYS = 14;             // 熱點、副本的每日人次留 14 天
const WINDOW_DAYS = 7;           // 對外顯示最近 7 天
const H_MAX = 120;               // 每個角色的等級紀錄最多留幾筆
const TOP = 100, TOP_CLASS = 50, TOP_FIELD = 8;
const SLOT_NAMES = ["凌晨 0–6 點", "早上 6–12 點", "下午 12–18 點", "晚上 18–24 點"];
export { SLOT_NAMES };

const int = v => (Number.isFinite(v) ? Math.round(v) : 0);
const bandOf = lvl => Math.max(0, Math.min(11, Math.floor((Math.max(1, lvl) - 1) / 5)));
const r1 = x => Math.round(x * 10) / 10;
const r2 = x => Math.round(x * 100) / 100;
const twHour = sec => new Date(sec * 1000 + 8 * 3600 * 1000).getUTCHours();

// ---------------------------------------------------------------------------
// 合併：一個存檔角色 → 網站上的角色紀錄
// ---------------------------------------------------------------------------

/**
 * 角色紀錄：{ n 名字, c 職業, r 種族, l 等級, g 公會, f 第一次看到, t 最後一次看到, o 被看到幾次（上傳次數）,
 *            h [[時間, 等級], ...] 每個等級第一次出現在上傳裡的時間, gh [[時間, 公會], ...] 公會變動 }
 * 回傳這次是不是新的觀察（存檔裡的時間比網站上的新）。
 */
export function observe(state, p) {
  const t = int(p.last);
  if (!t) return null;
  const key = nameKey(p.name);
  const lvl = Number.isInteger(p.level) ? p.level : 0;
  let e = state.get(key);
  // 公會 null＝小幫手讀不到（AmobiGuild 收的看到的玩家，denizens.js）：留網站上原本的
  const g = typeof p.guild === "string" ? p.guild : (p.guild == null && e ? e.g : "");
  const c = p.class_token || "", r = p.race_token || "";
  const first = int(p.first) || t;
  const fresh = () => ({ n: p.name, c, r, l: lvl, g, f: Math.min(first, t), t, o: 1, h: lvl ? [[t, lvl]] : [], gh: [[t, g]] });
  if (!e) {
    e = fresh();
    state.set(key, e);
    return { e, t, lvl, isNew: true };
  }
  if (t <= e.t) {   // 舊的觀察：只可能讓「第一次看到」更早
    if (first < e.f) e.f = first;
    return null;
  }
  const lastL = e.h.length ? e.h[e.h.length - 1][1] : 0;
  // 等級變低或職業變了：多半是刪角重練（同名），從頭記
  if ((lvl && lvl < lastL) || (c && e.c && c !== e.c)) {
    const n = fresh();
    n.f = t;
    n.rs = t;
    state.set(key, n);
    return { e: n, t, lvl, isNew: true };
  }
  if (lvl > lastL) e.h.push([t, lvl]);
  if (e.h.length > H_MAX) e.h.splice(1, e.h.length - H_MAX);
  if (g !== e.gh[e.gh.length - 1][1]) e.gh.push([t, g]);
  if (e.gh.length > H_MAX) e.gh.splice(1, e.gh.length - H_MAX);
  e.n = p.name;
  if (lvl) e.l = lvl;
  e.g = g;
  e.t = t;
  e.o = (e.o || 1) + 1;
  if (c) e.c = c;
  if (r) e.r = r;
  if (first < e.f) e.f = first;
  return { e, t, lvl, isNew: false };
}

// ---------------------------------------------------------------------------
// 每日人次（練功熱點、副本熱度）：只累計，不記是誰
// ---------------------------------------------------------------------------

export function emptyRaw() {
  return { v: 1, days: {}, cov: {}, rounds: [] };
}

function addObservation(raw, zones, area, t, lvl) {
  const day = twDate(t);
  const d = (raw.days[day] ||= { z: {}, d: {} });
  const zone = (zones && zones.areas[area]) || "?";
  const b = bandOf(lvl || 1);
  const row = (d.z[zone] ||= Array(12).fill(0));
  row[b]++;
  const kind = zone === "?" ? "?" : zones.zones[zone]?.kind;
  if (kind === "dungeon" || kind === "raid") {
    const x = (d.d[zone] ||= [0, 0, 0, 0, 0]);
    x[Math.floor(twHour(t) / 6)]++;
    x[4] += lvl || 0;
  }
}

/** 普查涵蓋的時數（每天、每 6 小時一段）：副本熱度要除以這個，才不會「有普查的時段人比較多」。 */
function addCoverage(raw, scans) {
  const done = new Set(raw.rounds);
  for (const s of scans) {
    if (s.get("cancelled") || !isFullRound(s)) continue;
    const at = int(s.get("at")), secs = int(s.get("secs"));
    const start = int(s.get("started")) || (at && secs ? at - secs : 0);
    if (!at || !start || start >= at || done.has(at)) continue;
    done.add(at);
    raw.rounds.push(at);
    for (let x = start; x < at;) {
      const slotEnd = (Math.floor((x + 8 * 3600) / (6 * 3600)) + 1) * 6 * 3600 - 8 * 3600;
      const y = Math.min(at, slotEnd);
      const day = twDate(x);
      const cov = (raw.cov[day] ||= [0, 0, 0, 0]);
      cov[Math.floor(twHour(x) / 6)] = r2(cov[Math.floor(twHour(x) / 6)] + (y - x) / 3600);
      x = y;
    }
  }
  raw.rounds = raw.rounds.sort((a, b) => a - b).slice(-500);
}

function pruneRaw(raw, today) {
  const cut = twDate(Date.parse(today + "T00:00:00Z") / 1000 - (RAW_DAYS - 1) * DAY);
  for (const k of Object.keys(raw.days)) if (k < cut) delete raw.days[k];
  for (const k of Object.keys(raw.cov)) if (k < cut) delete raw.cov[k];
}

const daysBack = (today, n) => twDate(Date.parse(today + "T00:00:00Z") / 1000 - n * DAY);

function zoneSummary(raw, zones, today, cap) {
  const from = daysBack(today, WINDOW_DAYS - 1);
  const sum = {};
  let total = 0;
  for (const [day, d] of Object.entries(raw.days)) {
    if (day < from || day > today) continue;
    for (const [z, row] of Object.entries(d.z)) {
      const s = (sum[z] ||= Array(12).fill(0));
      row.forEach((v, i) => { s[i] += v; total += v; });
    }
  }
  // 種類：field 野外練功地圖、start 出生地（各種族 1～10 級那張）、city 主城、dungeon 地城、raid 團隊副本、pvp 戰場、unknown 對不到
  const kindOf = z => (z === "?" ? "unknown" : zones?.zones[z]?.kind || "unknown");
  const byCount = (a, b2) => b2[1] - a[1] || (a[0] < b2[0] ? -1 : 1);
  const nb = Math.ceil(cap / 5);
  const bands = [];
  for (let b = 0; b < nb; b++) {
    const kinds = { field: 0, start: 0, city: 0, dungeon: 0, raid: 0, pvp: 0, unknown: 0 };
    const field = [], dungeons = [];
    let n = 0;
    for (const [z, row] of Object.entries(sum)) {
      if (!row[b]) continue;
      n += row[b];
      const k = kindOf(z);
      kinds[k] += row[b];
      if (k === "field") field.push([z, row[b]]);
      if (k === "dungeon" || k === "raid") dungeons.push([z, row[b], zones?.zones[z]?.map ?? null, k]);
    }
    // top：野外練功地圖（不含主城、出生地、副本、戰場）；dungeons：這一段在哪些地城、團隊副本被看到（全部列）
    bands.push({ lo: b * 5 + 1, hi: b * 5 + 5, n, kinds, top: field.sort(byCount).slice(0, TOP_FIELD), dungeons: dungeons.sort(byCount) });
  }
  const overall = Object.entries(sum).filter(([z]) => kindOf(z) === "field")
    .map(([z, row]) => {
      const n = row.reduce((a, v) => a + v, 0);
      const peak = row.indexOf(Math.max(...row));
      return [z, n, peak * 5 + 1];
    })
    .sort((a, b) => b[1] - a[1]).slice(0, 12);
  return { from, to: today, obs: total, bands, top: overall };
}

function dungeonSummary(raw, zones, today) {
  const from = daysBack(today, WINDOW_DAYS - 1);
  const cov = [0, 0, 0, 0];
  for (const [day, c] of Object.entries(raw.cov)) if (day >= from && day <= today) c.forEach((h, i) => { cov[i] = r2(cov[i] + h); });
  const acc = {};
  const pvp = {};
  for (const [day, d] of Object.entries(raw.days)) {
    if (day < from || day > today) continue;
    for (const [z, x] of Object.entries(d.d)) {
      const a = (acc[z] ||= [0, 0, 0, 0, 0]);
      x.forEach((v, i) => { a[i] += v; });
    }
    for (const [z, row] of Object.entries(d.z)) {
      if (zones?.zones[z]?.kind === "pvp") pvp[z] = (pvp[z] || 0) + row.reduce((a, v) => a + v, 0);
    }
  }
  const list = Object.entries(acc).map(([z, a]) => {
    const n = a[0] + a[1] + a[2] + a[3];
    return { name: z, id: zones?.zones[z]?.map ?? null, kind: zones?.zones[z]?.kind || "dungeon", n, avg: n ? r1(a[4] / n) : null, s: a.slice(0, 4) };
  }).sort((a, b) => b.n - a.n);
  return { from, to: today, cov, list, pvp: Object.entries(pvp).sort((a, b) => b[1] - a[1]) };
}

// ---------------------------------------------------------------------------
// 排行、速度、公會、職業變化
// ---------------------------------------------------------------------------

/** 第一次看到他到達 lvl 級（含以上）的時間；從來沒看到就 null。 */
const reachedAt = (e, lvl) => (e.h.find(x => x[1] >= lvl) || [null])[0];

/** 升級速度（每天幾級）：從第一次看到到現在（到滿等的就算到第一次看到滿等），至少隔 12 小時、而且第一次看到時還沒滿等。 */
export function speedOf(e, cap) {
  if (!e.h.length) return null;
  const [t0, l0] = e.h[0];
  if (l0 >= cap) return null;
  const tc = reachedAt(e, cap);
  const end = tc ?? e.t;
  const l1 = tc ? cap : e.l;
  const span = end - t0;
  if (span < MIN_SPAN) return null;
  return { sp: r2((l1 - l0) / (span / DAY)), l0, l1, days: r1(span / DAY) };
}

function derive(state, cap) {
  const all = [...state.values()];
  // 升級速度＋百分位
  const fast = [];
  for (const e of all) {
    delete e.sp; delete e.sd; delete e.p; delete e.rc; delete e.rm; delete e.a;
    const s = speedOf(e, cap);
    if (s) { e.sp = s.sp; e.sd = s.days; fast.push([e, s]); }
  }
  const speeds = fast.map(([, s]) => s.sp).sort((a, b) => a - b);
  if (speeds.length >= MIN_PCT_N) {
    for (const [e, s] of fast) {
      let lo = 0, hi = speeds.length;   // 比他慢的人數（嚴格小於）
      while (lo < hi) { const mid = (lo + hi) >> 1; if (speeds[mid] < s.sp) lo = mid + 1; else hi = mid; }
      e.p = Math.floor(lo / speeds.length * 100);
    }
  }
  fast.sort((a, b) => b[1].sp - a[1].sp || (a[0].n < b[0].n ? -1 : 1));

  // 最先到滿等（第一次看到他滿等的時間）：只排普查期間升上來的（第一次看到時還沒滿等）；
  // 第一次看到就已經滿等的只算人數（封測開始前就練滿了，看不出誰先）
  const capped = all.map(e => [e, reachedAt(e, cap)]).filter(([, t]) => t)
    .sort((a, b) => a[1] - b[1] || (a[0].n < b[0].n ? -1 : 1));
  const during = capped.filter(([e]) => e.h[0][1] < cap);
  for (const [e] of capped) if (e.h[0][1] >= cap) e.a = 1;
  during.forEach(([e], i) => { e.rm = i + 1; });

  // 同職業：等級高的在前，同等級的比較早到的在前
  const byClass = {}, clsN = {}, clsCap = {};
  for (const e of all) if (e.c) (byClass[e.c] ||= []).push(e);
  for (const [c, list] of Object.entries(byClass)) {
    list.sort((a, b) => b.l - a.l || (reachedAt(a, a.l) ?? a.t) - (reachedAt(b, b.l) ?? b.t) || (a.n < b.n ? -1 : 1));
    list.forEach((e, i) => { e.rc = i + 1; });
    clsN[c] = list.length;
    clsCap[c] = list.filter(e => e.l >= cap).length;
  }

  const ranks = {
    cap,
    capN: during.length,
    capAlready: capped.length - during.length,
    capList: during.slice(0, TOP).map(([e, t]) => [e.n, e.c, e.r, twDate(t), e.g, e.h[0][1]]),
    fastN: fast.length,
    minSpanHours: MIN_SPAN / 3600,
    fast: fast.slice(0, TOP).map(([e, s]) => [e.n, e.c, e.r, s.sp, s.l0, s.l1, s.days, e.g]),
    clsN, clsCap,
    byClass: Object.fromEntries(CLASS_ORDER.filter(c => byClass[c]).map(c => [c,
      byClass[c].slice(0, TOP_CLASS).map(e => [e.n, e.r, e.l, twDate(reachedAt(e, e.l) ?? e.t), e.g])])),
  };
  return ranks;
}

function classSummary(active, cap) {
  const nb = Math.ceil(cap / 5);
  const bands = Array.from({ length: nb }, (_, b) => [b * 5 + 1, b * 5 + 5, Array(CLASS_ORDER.length).fill(0)]);
  const all = Array(CLASS_ORDER.length).fill(0);
  for (const e of active) {
    const ci = CLASS_ORDER.indexOf(e.c);
    if (ci < 0 || !e.l) continue;
    bands[Math.min(nb - 1, bandOf(e.l))][2][ci]++;
    all[ci]++;
  }
  return { cap, order: CLASS_ORDER, n: all.reduce((a, b) => a + b, 0), all, bands };
}

function guildData(state, active, prevGuilds, today, snapshot, cap) {
  const members = new Map();
  for (const e of active) if (e.g) {
    if (!members.has(e.g)) members.set(e.g, []);
    members.get(e.g).push(e);
  }
  // 公會進出：角色的公會紀錄裡，第一次之後的每一次變動（30 天內）
  const events = new Map();
  const cut = snapshot - 30 * DAY;
  for (const e of state.values()) {
    for (let i = 1; i < e.gh.length; i++) {
      const [t, cur] = e.gh[i], prev = e.gh[i - 1][1];
      if (t < cut) continue;
      if (cur) (events.get(cur) || events.set(cur, []).get(cur)).push([t, e.n, e.c, 1, prev]);
      if (prev) (events.get(prev) || events.set(prev, []).get(prev)).push([t, e.n, e.c, -1, cur]);
    }
  }
  const list = [], entries = [];
  for (const [g, ms] of members) {
    ms.sort((a, b) => b.l - a.l || (a.n < b.n ? -1 : 1));
    const n = ms.length;
    const avg = r1(ms.reduce((a, e) => a + (e.l || 0), 0) / n);
    const capN = ms.filter(e => e.l >= cap).length;
    const cls = CLASS_ORDER.map(c => ms.filter(e => e.c === c).length);
    const prev = prevGuilds.get(g);
    const series = (prev?.s || []).filter(p => p[0] !== today);
    series.push([today, n, avg]);
    series.sort((a, b) => (a[0] < b[0] ? -1 : 1));
    if (series.length > 60) series.splice(0, series.length - 60);
    // 成長：和 7 天前（沒有 7 天的話，最早的、至少前一天）比
    const weekAgo = daysBack(today, 7);
    const base = [...series].reverse().find(p => p[0] <= weekAgo) || series.find(p => p[0] < today);
    const grow = base ? n - base[1] : null;
    const growDays = base ? Math.round((Date.parse(today) - Date.parse(base[0])) / 86400000) : null;
    const ev = (events.get(g) || []).sort((a, b) => b[0] - a[0]).slice(0, 40)
      .map(([t, name, c, k, other]) => [twDate(t), name, c, k, other]);
    list.push([g, n, avg, capN, cls, grow, growDays]);
    entries.push({ g, n, avg, cap: capN, cls, grow, growDays, s: series, m: ms.map(e => [e.n, e.c, e.r, e.l]), ev });
  }
  list.sort((a, b) => b[1] - a[1] || b[2] - a[2] || (a[0] < b[0] ? -1 : 1));
  return { index: { cap, order: CLASS_ORDER, n: list.length, members: list.reduce((a, x) => a + x[1], 0), list }, entries };
}

// ---------------------------------------------------------------------------
// 一個「階段＋伺服器＋陣營」：舊資料＋存檔 → 要寫回 D1 的所有列
// ---------------------------------------------------------------------------

/**
 * prev：{ chars: Map(nkey → 紀錄), guilds: Map(公會 → 紀錄), raw, meta }（網站上已有的；第一次上傳全是空的）
 * players：這個階段＋伺服器＋陣營的存檔角色（denizens.js readSaves 的格式）；scans：存檔裡的普查紀錄
 * hidden：Set(nkey) 申請移除的角色
 */
export function buildGroup({ phase, realm, faction, prev, players, scans, zones, names = false, hidden = new Set(), now = Date.now() / 1000 }) {
  const cap = capOf(phase);
  const state = prev.chars;
  for (const k of hidden) state.delete(k);
  const raw = prev.raw || emptyRaw();
  const newNames = [];
  let fresh = 0, updated = 0;
  for (const p of players) {
    const key = nameKey(p.name);
    if (hidden.has(key)) continue;
    const res = observe(state, p);
    if (!res) continue;
    if (res.isNew) { fresh++; newNames.push([res.e.n, res.e.c]); } else updated++;
    // 小幫手看到的（不是 /who 查到的）不算練功熱點、副本熱度：那兩個是用普查的時數算比例（addCoverage）
    if (p.via !== "seen") addObservation(raw, zones, p.area, res.t, res.lvl);
  }
  addCoverage(raw, scans);

  let snapshot = 0;
  for (const e of state.values()) snapshot = Math.max(snapshot, e.t);
  const today = twDate(snapshot || int(now));
  pruneRaw(raw, today);
  const active = [...state.values()].filter(e => snapshot - e.t <= ACTIVE);
  const ranks = derive(state, cap);
  const guilds = guildData(state, active, prev.guilds, today, snapshot, cap);
  const pm = prev.meta || {};
  const meta = {
    phase, realm, faction, cap, snapshot, date: today, names,
    chars: state.size, active: active.length,
    multi: [...state.values()].filter(e => (e.o || 1) >= 2).length,
    speedN: ranks.fastN, capN: ranks.capN, clsN: ranks.clsN,
    // 同一份存檔重傳（沒有新的觀察）不算一次上傳，只重算彙總
    uploads: (pm.uploads || 0) + (fresh + updated ? 1 : 0),
    firstUpload: pm.firstUpload || int(now), lastUpload: fresh + updated || !pm.lastUpload ? int(now) : pm.lastUpload,
    firstSeen: [...state.values()].reduce((m, e) => Math.min(m, e.f), Infinity),
    added: fresh, updated,
  };
  if (!Number.isFinite(meta.firstSeen)) meta.firstSeen = null;

  // 分包
  const cb = new Map();
  for (let i = 0; i < NB_CHAR; i++) cb.set(String(i).padStart(3, "0"), []);
  for (const [key, e] of state) cb.get(bucketOf(key, NB_CHAR)).push(e);
  const gb = new Map();
  for (let i = 0; i < NB_GUILD; i++) gb.set(String(i).padStart(3, "0"), []);
  for (const g of guilds.entries) gb.get(bucketOf(nameKey(g.g), NB_GUILD)).push(g);

  const rows = [
    ...[...cb].map(([k, list]) => ({ kind: "c", k, data: list })),
    ...[...gb].map(([k, list]) => ({ kind: "g", k, data: list })),
    { kind: "r", k: "raw", data: raw },
    { kind: "b", k: "ranks", data: ranks },
    { kind: "b", k: "guilds", data: guilds.index },
    { kind: "b", k: "zones", data: zoneSummary(raw, zones, today, cap) },
    { kind: "b", k: "dungeons", data: dungeonSummary(raw, zones, today) },
    { kind: "b", k: "classes", data: classSummary(active, cap) },
    { kind: "b", k: "meta", data: meta },   // 最後寫：網頁看到新的 meta 時，其他資料都已經是新的
  ];
  return { rows, newNames, meta, state };
}

/** 存檔（readSaves 的 realms）依階段＋伺服器＋陣營分組。 */
export function groupSaves(realms) {
  const groups = new Map();
  for (const r of realms) {
    if (r.faction !== "Alliance" && r.faction !== "Horde") continue;
    for (const p of r.players) {
      if (!p.last) continue;
      const phase = phaseOf(p.last);
      const key = `${phase}|${r.realm}|${r.faction}`;
      if (!groups.has(key)) groups.set(key, { phase, realm: r.realm, faction: r.faction, players: [], scans: [] });
      groups.get(key).players.push(p);
    }
    for (const s of r.scans) {
      const phase = phaseOf(Number(s.get("at")) || 0);
      const g = groups.get(`${phase}|${r.realm}|${r.faction}`);
      if (g) g.scans.push(s);
    }
  }
  return [...groups.values()];
}

// ---------------------------------------------------------------------------
// 和網站溝通（站長的上傳金鑰）
// ---------------------------------------------------------------------------

function client({ base, token, fetch: f = globalThis.fetch }) {
  return async (method, path, body) => {
    const r = await f(base + path, {
      method,
      headers: { authorization: `Bearer ${token}`, ...(body ? { "content-type": "application/json" } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(`${method} ${path.split("?")[0]}：HTTP ${r.status} ${j.error || ""}`);
    return j;
  };
}

const qs = o => new URLSearchParams(o).toString();

async function loadPrev(call, g) {
  const base = { phase: g.phase, realm: g.realm, faction: g.faction };
  const prev = { chars: new Map(), guilds: new Map(), raw: null, meta: null };
  for (const kind of ["c", "g", "r", "b"]) {
    let after = "";
    for (;;) {
      const j = await call("GET", `/api/insights/state?${qs({ ...base, kind, after, limit: 64 })}`);
      for (const row of j.rows) {
        if (kind === "c") for (const e of row.data) prev.chars.set(nameKey(e.n), e);
        else if (kind === "g") for (const x of row.data) prev.guilds.set(x.g, x);
        else if (kind === "r" && row.k === "raw") prev.raw = row.data;
        else if (kind === "b" && row.k === "meta") prev.meta = row.data;
      }
      if (!j.more) break;
      after = j.rows[j.rows.length - 1].k;
    }
  }
  return prev;
}

/** 把列切成每個請求不超過 maxBytes（Worker 免費方案 CPU 有限，一次不要解析太多）。 */
function chunks(rows, maxBytes = 400_000, maxRows = 48) {
  const out = [];
  let cur = [], size = 0;
  for (const row of rows) {
    const s = JSON.stringify(row.data);
    if (cur.length && (size + s.length > maxBytes || cur.length >= maxRows)) { out.push(cur); cur = []; size = 0; }
    cur.push({ kind: row.kind, k: row.k, data: s });
    size += s.length;
  }
  if (cur.length) out.push(cur);
  return out;
}

// ---------------------------------------------------------------------------
// 匿名代號：老闆決定公開角色名之前，角色名在這台電腦就換成代號（#＋12 位十六進位），網站上不會有任何角色名。
// 代號＝HMAC-SHA256(只放在這台電腦的密鑰, 名字小寫)，同一個名字每次都得到同一個代號（歷史才接得起來），
// 沒有密鑰的人沒辦法拿名字去猜代號。密鑰弄丟了代號就會全部變掉，要刪掉網站上的深度數據重傳。
// ---------------------------------------------------------------------------

const hex = buf => [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, "0")).join("");

export async function pseudonymizer(salt) {
  if (!salt || salt.length < 16) throw new Error("沒有匿名代號用的密鑰（INSIGHTS_SALT）");
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", enc.encode(salt), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return async name => "#" + hex(await crypto.subtle.sign("HMAC", key, enc.encode(nameKey(name)))).slice(0, 12);
}
export const isPseudonym = n => typeof n === "string" && /^#[0-9a-f]{12}$/.test(n);

/**
 * 同步一份（或已合併的多份）存檔到網站。realms：readSaves 的結果；zones：public/data/zones.json。
 * names：true 才上傳真的角色名（老闆同意公開之後）；預設用匿名代號，salt 是代號的密鑰。
 * dryRun：不連網站，從空的歷史算一次（看會上傳什麼）。fresh：不讀網站上的歷史、從空的開始算，上傳的資料列整份蓋掉網站上的。回傳每組的 meta。
 */
export async function syncInsights(realms, { base, token, zones, fetch, log = () => {}, dryRun = false, fresh = false, now, names = false, salt } = {}) {
  const call = dryRun ? null : client({ base, token, fetch });
  const pseudo = names ? null : await pseudonymizer(salt);
  const hidden = new Map();
  if (!dryRun) {
    const j = await call("GET", "/api/insights/hidden");
    for (const h of j.hidden) {
      const k = `${h.realm}|${h.faction}`;
      if (!hidden.has(k)) hidden.set(k, new Set());
      hidden.get(k).add(pseudo ? nameKey(await pseudo(h.nkey)) : h.nkey);
    }
  }
  const out = [];
  for (const g of groupSaves(realms)) {
    const prev = dryRun || fresh ? { chars: new Map(), guilds: new Map(), raw: null, meta: null } : await loadPrev(call, g);
    if (prev.meta && Boolean(prev.meta.names) !== names) {
      throw new Error(`${g.realm} ${g.faction} 網站上的深度數據是${prev.meta.names ? "具名" : "匿名"}的，這次是${names ? "具名" : "匿名"}，`
        + "兩種不能混在一起：先刪掉網站上的深度數據（DELETE /api/insights），再把存檔從舊到新重傳一次");
    }
    const players = pseudo ? await Promise.all(g.players.map(async p => ({ ...p, name: await pseudo(p.name) }))) : g.players;
    const built = buildGroup({ ...g, players, prev, zones, names, hidden: hidden.get(`${g.realm}|${g.faction}`) || new Set(), now: now ?? Date.now() / 1000 });
    const where = { phase: g.phase, realm: g.realm, faction: g.faction };
    if (!dryRun) {
      // 搜尋用的名字表只有具名時才寫
      for (let i = 0; names && i < built.newNames.length; i += 1000) {
        await call("POST", "/api/insights/names", { ...where, names: built.newNames.slice(i, i + 1000) });
      }
      for (const part of chunks(built.rows)) await call("POST", "/api/insights/rows", { ...where, rows: part });
    }
    log(built.meta);
    out.push({ ...built.meta, rows: built.rows, state: built.state });
  }
  return out;
}
