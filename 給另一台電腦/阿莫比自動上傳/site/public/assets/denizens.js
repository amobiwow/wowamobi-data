// Denizens TW（與原版 Denizens）存檔解析，tools/parse_denizens.py 的 JS 版。
// 解析、合併去重、名稱對照的規則都和 Python 版一致；最後多一步：依開服時間分成
// 開服前（beta）與開服後（live），每個「伺服器＋陣營」各算一份彙總。
//
// 在站長的瀏覽器裡執行：存檔不會離開那台電腦，送到網站的只有彙總數字（沒有角色名）。
// Node 也能 import：scripts/verify-census.mjs 用它和 Python 版對答案。
//
// 不執行任何 Lua：檔案只當資料解析，只接受 WoW 存檔會寫出的 Lua 子集
// （表格、字串、數字、true/false/nil、註解）。

export const LAUNCH_TS = 1793833200; // 2026-11-05 07:00 台灣時間（2026-11-04T23:00:00Z）
export const ACTIVE_DAYS = 7;
// 開服前首頁的「10/19 倒數三天」：10/18 18:00 起到 10/22 05:00 壓力測試開始前（台灣時間），這段期間被 /who 查到過的角色。
// 原本從 10/19 00:00 算；老闆 10/19 指示「如實把資料公佈上去，包含取樣時間」，所以存檔裡 10/18 18:10 起看到的角色都算，
// 首頁另外照實標出取樣時間（資料裡最早到最晚看到人的時間）。範圍跟著彙總一起上傳（windows.camp.range）。
// 10/23 延到封測關閉（10/24 01:00）：壓測之後封測重新開放，老闆要把 10/23 撈的兩輪也算進首頁的封測數據
export const CAMPAIGN = {
  start: Date.parse("2026-10-18T18:00:00+08:00") / 1000,
  end: Date.parse("2026-10-24T01:00:00+08:00") / 1000,
};

// 沒跑完、插件沒記進 scans 的輪次（老闆 10/23：「沒跑完的也算一輪」；網站上當正常的輪，不另外註明：「不用註明阿，我就已經跟你說當正常兩輪更新了」）。
// 時間照存檔裡角色被看到的時間核對（資料\公測1023_兩輪）：最早看到～最晚看到，之後零星看到的不算在內。
// 聯盟 10/23 第 2 輪：10:59:56 從 1 級查起，11:40 查到 30 級，12:03:21 停；
// 部落 10/23 第 2 輪：17:54:24 從 1 級查起，18:40 查到 30 級，19:08:04 遊戲關掉（之後 20:25 零星看到的 23 人不算）。
// readSaves 讀存檔時補進那個伺服器＋陣營的 scans（mode "partial"），普查彙總、深度數據、上傳頁都照一般的輪算
export const PARTIAL_ROUNDS = [
  { realm: "Classic Beta PvP", faction: "Alliance", started: 1792724396, at: 1792728201 },
  { realm: "Classic Beta PvP", faction: "Horde", started: 1792749264, at: 1792753684 },
];

export class LuaSyntaxError extends Error {}

// ---------------------------------------------------------------------------
// Lua 資料解析（SavedVariables 子集）
// ---------------------------------------------------------------------------

const EOF = 0, STR = 1, NUM = 2, NAME = 3, PUNCT = 4;
const NUM_RE = /0[xX][0-9a-fA-F]+(?:\.[0-9a-fA-F]*)?(?:[pP][+-]?[0-9]+)?|(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?/y;
const SIMPLE_ESC = { a: 7, b: 8, f: 12, n: 10, r: 13, t: 9, v: 11, "\\": 92, '"': 34, "'": 39 };
const repr = v => (v === null || v === undefined ? "None" : JSON.stringify(v));

function hexFloat(t) {
  const m = /^0x([0-9a-f]*)(?:\.([0-9a-f]*))?(?:p([+-]?\d+))?$/.exec(t);
  const frac = m[2] || "";
  let v = parseInt((m[1] || "0") + frac, 16);
  return v * 2 ** (Number(m[3] || 0) - 4 * frac.length);
}

function luaNumber(text) {
  const t = text.toLowerCase();
  if (t.startsWith("0x")) return t.includes(".") || t.includes("p") ? hexFloat(t) : parseInt(t, 16);
  return Number(t);
}

function unescapeLua(raw) {
  const enc = new TextEncoder();
  const parts = [];
  let lit = 0, i = 0;
  while ((i = raw.indexOf("\\", i)) !== -1) {
    const c = raw[i + 1];
    let bytes = null, len = 0;
    if (c !== undefined && Object.hasOwn(SIMPLE_ESC, c)) {
      bytes = [SIMPLE_ESC[c]]; len = 2;
    } else if (c === "\r" || c === "\n") {
      const two = raw.slice(i + 1, i + 3);
      bytes = [10]; len = two === "\r\n" || two === "\n\r" ? 3 : 2;
    } else if (c >= "0" && c <= "9") {
      const d = /^[0-9]{1,3}/.exec(raw.slice(i + 1, i + 4))[0];
      if (Number(d) > 255) throw new LuaSyntaxError(`跳脫字元超出範圍：\\${Number(d)}`);
      bytes = [Number(d)]; len = 1 + d.length;
    } else if (c === "x" && /^[0-9a-fA-F]{2}$/.test(raw.slice(i + 2, i + 4))) {
      bytes = [parseInt(raw.slice(i + 2, i + 4), 16)]; len = 4;
    } else if (c === "z") {
      let j = i + 2;
      while (j < raw.length && " \t\n\r\f\v".includes(raw[j])) j++;
      bytes = []; len = j - i;
    } else if (c === "u") {
      const m = /^u\{([0-9a-fA-F]+)\}/.exec(raw.slice(i + 1));
      if (m) { bytes = [...enc.encode(String.fromCodePoint(parseInt(m[1], 16)))]; len = 1 + m[0].length; }
    }
    if (bytes === null) { i += 1; continue; } // not an escape: keep the backslash, like Python's re.sub
    if (i > lit) parts.push(enc.encode(raw.slice(lit, i)));
    parts.push(Uint8Array.from(bytes));
    i += len;
    lit = i;
  }
  if (raw.length > lit) parts.push(enc.encode(raw.slice(lit)));
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0;
  for (const p of parts) { out.set(p, o); o += p.length; }
  return new TextDecoder("utf-8").decode(out);
}

/** Parse a SavedVariables file (string or bytes) into a Map of its top-level variables. */
export function parseSavedVariables(input) {
  const text = typeof input === "string" ? input : new TextDecoder("utf-8").decode(input);
  const n = text.length;
  let pos = text.charCodeAt(0) === 0xfeff ? 1 : 0;
  let tt, tv, tp; // current token
  let nt, nv, np; // next token

  const lineAt = p => {
    let line = 1;
    for (let i = text.indexOf("\n"); i !== -1 && i < p; i = text.indexOf("\n", i + 1)) line++;
    return line;
  };
  const longOpen = p => { // p at "[": number of "=" in "[==[", or -1
    let q = p + 1, eq = 0;
    while (text.charCodeAt(q) === 61) { eq++; q++; }
    return text.charCodeAt(q) === 91 ? eq : -1;
  };

  function scan() {
    while (pos < n) {
      const c = text.charCodeAt(pos);
      if (c === 32 || c === 9 || c === 13 || c === 10) { pos++; continue; }
      const start = pos;
      if (c === 45 && text.charCodeAt(pos + 1) === 45) { // comment
        if (text.charCodeAt(pos + 2) === 91) {
          const eq = longOpen(pos + 2);
          if (eq >= 0) {
            const close = "]" + "=".repeat(eq) + "]";
            const end = text.indexOf(close, pos + 4 + eq);
            if (end !== -1) { pos = end + close.length; continue; }
          }
        }
        const nl = text.indexOf("\n", pos);
        pos = nl === -1 ? n : nl;
        continue;
      }
      if (c === 91) { // long string, or a plain "["
        const eq = longOpen(pos);
        if (eq >= 0) {
          const close = "]" + "=".repeat(eq) + "]";
          const end = text.indexOf(close, pos + 2 + eq);
          if (end !== -1) {
            let body = text.slice(pos + 2 + eq, end);
            if (body.startsWith("\r\n")) body = body.slice(2);
            else if (body.startsWith("\n")) body = body.slice(1);
            pos = end + close.length;
            nt = STR; nv = body; np = start;
            return;
          }
        }
      }
      if (c === 34 || c === 39) { // "..." or '...'
        let q = pos + 1, esc = false;
        for (;;) {
          const d = q < n ? text.charCodeAt(q) : -1;
          if (d === -1 || d === 10) throw new LuaSyntaxError(`第 ${lineAt(start)} 行：字串沒有結束（檔案可能不完整，例如遊戲當掉或複製到一半）`);
          if (d === c) break;
          if (d === 92) { esc = true; q += 2; continue; }
          q++;
        }
        const raw = text.slice(pos + 1, q);
        pos = q + 1;
        nt = STR; nv = esc ? unescapeLua(raw) : raw; np = start;
        return;
      }
      if ((c >= 48 && c <= 57) || c === 46) {
        NUM_RE.lastIndex = pos;
        const m = NUM_RE.exec(text);
        if (m) {
          pos += m[0].length;
          nt = NUM; nv = luaNumber(m[0]); np = start;
          return;
        }
      }
      if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c === 95) {
        let q = pos + 1;
        for (; q < n; q++) {
          const d = text.charCodeAt(q);
          if (!((d >= 65 && d <= 90) || (d >= 97 && d <= 122) || (d >= 48 && d <= 57) || d === 95)) break;
        }
        nt = NAME; nv = text.slice(pos, q); np = start; pos = q;
        return;
      }
      if (c === 123 || c === 125 || c === 91 || c === 93 || c === 61 || c === 44 || c === 59 || c === 45) {
        pos++;
        nt = PUNCT; nv = text[start]; np = start;
        return;
      }
      throw new LuaSyntaxError(`第 ${lineAt(pos)} 行：看不懂的字元 ${repr(text.slice(pos, pos + 12))}`);
    }
    nt = EOF; nv = null; np = pos;
  }

  const advance = () => { tt = nt; tv = nv; tp = np; scan(); };
  const fail = msg => new LuaSyntaxError(`第 ${lineAt(tp)} 行：${msg}`);
  const isPunct = v => tt === PUNCT && tv === v;
  const expect = v => { if (!isPunct(v)) throw fail(`這裡應該是「${v}」，卻看到 ${repr(tv)}`); advance(); };

  function parseValue() {
    if (tt === NUM || tt === STR) { const v = tv; advance(); return v; }
    if (tt === NAME) {
      if (tv === "true" || tv === "false" || tv === "nil") {
        const v = tv === "true" ? true : tv === "false" ? false : null;
        advance();
        return v;
      }
      throw fail(`不支援的值：${tv}`);
    }
    if (isPunct("{")) return parseTable();
    if (isPunct("-")) {
      advance();
      if (tt !== NUM) throw fail("負號後面應該是數字");
      const v = 0 - tv;
      advance();
      return v;
    }
    throw fail(`看不懂的值：${repr(tv)}`);
  }

  function parseTable() {
    expect("{");
    const keys = [], vals = [];
    let nexti = 1;
    while (!isPunct("}")) {
      if (tt === EOF) throw fail("表格沒有結束（檔案可能被截斷）");
      let key, val;
      if (isPunct("[")) {
        advance();
        key = parseValue();
        expect("]");
        expect("=");
        val = parseValue();
      } else if (tt === NAME && nt === PUNCT && nv === "=") {
        key = tv;
        advance();
        advance();
        val = parseValue();
      } else {
        key = nexti++;
        val = parseValue();
      }
      keys.push(key);
      vals.push(val);
      if (isPunct(",") || isPunct(";")) advance();
      else if (!isPunct("}")) throw fail("表格欄位之間少了逗號");
    }
    advance();
    // A table whose keys are exactly 1..n becomes an array (nil kept); anything else a Map (nil dropped).
    if (keys.length && keys.every(k => typeof k === "number" && Number.isInteger(k))) {
      const sorted = [...keys].sort((a, b) => a - b);
      if (sorted.every((k, i) => k === i + 1)) {
        const arr = new Array(keys.length);
        keys.forEach((k, i) => { arr[k - 1] = vals[i]; });
        return arr;
      }
    }
    const table = new Map();
    keys.forEach((k, i) => { if (vals[i] !== null) table.set(k, vals[i]); });
    return table;
  }

  scan();
  advance();
  const out = new Map();
  while (tt !== EOF) {
    if (tt !== NAME) throw fail(`應該是變數名稱，卻看到 ${repr(tv)}`);
    const name = tv;
    advance();
    expect("=");
    out.set(name, parseValue());
    if (isPunct(";")) advance();
  }
  return out;
}

// ---------------------------------------------------------------------------
// Python 語意的小工具
// ---------------------------------------------------------------------------

const truthy = v => !(v === null || v === undefined || v === false || v === 0 || v === "" || Number.isNaN(v)
  || (v instanceof Map && v.size === 0) || (Array.isArray(v) && v.length === 0));
const or = (a, b) => (truthy(a) ? a : b);
const isNum = v => typeof v === "number" && !Number.isNaN(v);
const num0 = v => (isNum(v) ? v : 0);
const get = (t, k) => (t instanceof Map ? t.get(k) : undefined);

/** Compare strings by code point, like Python (JS compares UTF-16 units). */
export function cmpCodePoint(a, b) {
  const n = Math.min(a.length, b.length);
  for (let i = 0; i < n; i++) {
    const x = a.charCodeAt(i), y = b.charCodeAt(i);
    if (x !== y) {
      if (x >= 0xd800 && x <= 0xdfff && y >= 0xe000) return 1;
      if (y >= 0xd800 && y <= 0xdfff && x >= 0xe000) return -1;
      return x - y;
    }
  }
  return a.length - b.length;
}

function asList(x) {
  if (Array.isArray(x)) return x;
  if (x instanceof Map) {
    const isInt = k => typeof k === "number" && Number.isInteger(k);
    return [...x.keys()].sort((a, b) => {
      if (isInt(a) !== isInt(b)) return isInt(a) ? -1 : 1;
      if (typeof a === "string" && typeof b === "string") return cmpCodePoint(a, b);
      return a < b ? -1 : a > b ? 1 : 0;
    }).map(k => x.get(k));
  }
  return [];
}

/** Counter.most_common: by count, ties keep first-seen order. */
function mostCommon(map, k = Infinity) {
  return [...map.entries()].sort((a, b) => b[1] - a[1]).slice(0, k);
}

// ---------------------------------------------------------------------------
// 名稱對照（客戶端語言 → 語言無關的代碼 → 繁中顯示名）
// ---------------------------------------------------------------------------

export const CLASS_ZH = { WARRIOR: "戰士", PALADIN: "聖騎士", HUNTER: "獵人", ROGUE: "盜賊", PRIEST: "牧師",
  SHAMAN: "薩滿", MAGE: "法師", WARLOCK: "術士", DRUID: "德魯伊" };
const CLASS_ALIASES = {
  WARRIOR: ["Warrior", "戰士", "战士"], PALADIN: ["Paladin", "聖騎士", "圣骑士"],
  HUNTER: ["Hunter", "獵人", "猎人"], ROGUE: ["Rogue", "盜賊", "盗贼", "潜行者"],
  PRIEST: ["Priest", "牧師", "牧师"], SHAMAN: ["Shaman", "薩滿", "萨满", "萨满祭司"],
  MAGE: ["Mage", "法師", "法师"], WARLOCK: ["Warlock", "術士", "术士"],
  DRUID: ["Druid", "德魯伊", "德鲁伊"],
};
// Skyborne 的官方繁中譯名「天裔精靈」出自暴雪繁中新聞《魔獸世界：永恆》- 天裔精靈視覺更新的未來（2026-10-07）
export const RACE_ZH = { HUMAN: "人類", DWARF: "矮人", NIGHTELF: "夜精靈", GNOME: "地精", ORC: "獸人",
  UNDEAD: "不死族", TAUREN: "牛頭人", TROLL: "食人妖", SKYBORNE: "天裔精靈" };
const RACE_ALIASES = {
  HUMAN: ["Human", "人類", "人类"], DWARF: ["Dwarf", "矮人"],
  NIGHTELF: ["Night Elf", "夜精靈", "暗夜精灵"],
  GNOME: ["Gnome", "地精", "侏儒"], // 繁中的「地精」= Gnome（簡中的地精是 Goblin，Forever 沒有 Goblin）
  ORC: ["Orc", "獸人", "兽人"], UNDEAD: ["Undead", "不死族", "亡灵"],
  TAUREN: ["Tauren", "牛頭人", "牛头人"], TROLL: ["Troll", "食人妖", "巨魔"],
};
export const FACTION_ZH = { Alliance: "聯盟", Horde: "部落" };
const lookup = aliases => new Map(Object.entries(aliases).flatMap(([t, names]) => names.map(a => [a.toLowerCase(), t])));
const CLASS_LOOKUP = lookup(CLASS_ALIASES);
const RACE_LOOKUP = lookup(RACE_ALIASES);

export function mapClass(raw, token) {
  const t = String(or(token, "")).toUpperCase();
  if (Object.hasOwn(CLASS_ZH, t)) return t;
  return CLASS_LOOKUP.get(String(or(raw, "")).trim().toLowerCase()) ?? null;
}

export function mapRace(raw) {
  const key = String(or(raw, "")).trim().toLowerCase();
  if (RACE_LOOKUP.has(key)) return RACE_LOOKUP.get(key);
  // 兩個陣營各有一支（High Order / Windshaper），客戶端可能顯示全名或簡稱
  if (key.includes("skyborne") || key.includes("天裔")) return "SKYBORNE";
  return null;
}

// ---------------------------------------------------------------------------
// 角色名用哪一種文字（推估玩家來自哪裡，不是國籍）。規則在 tools/name_lang.json，網站用它的複本
// public/data/name_lang.json（verify-census.mjs 會檢查兩份一樣），算法和 parse_denizens.py 的 name_lang() 相同。
// ---------------------------------------------------------------------------

let NAME_RULES = null, NAME_SCRIPTS = [], ZH_TRAD = new Set(), ZH_SIMP = new Set();

/** 載入名字語言規則（name_lang.json 的內容）。沒載入時彙總裡不會有 langs。 */
export function setNameRules(rules) {
  NAME_RULES = rules;
  NAME_SCRIPTS = rules.order.map(code => [code, rules.scripts[code].map(span => span.split("-").map(x => parseInt(x, 16)))]);
  ZH_TRAD = new Set(rules.zh_traditional_only);
  ZH_SIMP = new Set(rules.zh_simplified_only);
}

/** ko、ja、zh_t、zh_s、zh_u、ru、th、latin、other（看名字用哪種文字）。 */
export function nameLang(name) {
  const base = [...String(name || "").split("-")[0]];   // 跨伺服器角色是「角色名-伺服器」，以碼點逐字看
  for (const [code, spans] of NAME_SCRIPTS) {
    if (base.some(ch => { const cp = ch.codePointAt(0); return spans.some(([lo, hi]) => lo <= cp && cp <= hi); })) {
      if (code !== "zh") return code;
      const trad = base.some(ch => ZH_TRAD.has(ch)), simp = base.some(ch => ZH_SIMP.has(ch));
      return trad && !simp ? "zh_t" : simp && !trad ? "zh_s" : "zh_u";
    }
  }
  return "other";
}

// ---------------------------------------------------------------------------
// 擷取與合併
// ---------------------------------------------------------------------------

export function extract(sv, source) {
  let db, kind;
  if (sv.has("DenizensTWDB")) { db = sv.get("DenizensTWDB"); kind = "DenizensTW"; }
  else if (sv.has("DenizensDB")) { db = sv.get("DenizensDB"); kind = "Denizens"; }
  else throw new Error(`${source}：找不到 DenizensTWDB 或 DenizensDB，這不是 Denizens 的存檔`);
  if (!(db instanceof Map)) throw new Error(`${source}：存檔內容不是表格`);
  const realms = or(db.get("realms"), new Map());
  const client = db.get("client") instanceof Map ? db.get("client") : new Map();
  const out = [];
  for (const [key, r] of realms instanceof Map ? realms : []) {
    if (!(r instanceof Map)) continue;
    const k = String(key);
    const cut = k.lastIndexOf(" - ");
    let realm = cut === -1 ? "" : k.slice(0, cut);
    let faction = cut === -1 ? k : k.slice(cut + 3);
    if (!realm) { realm = k; faction = ""; }
    const players = [];
    const list = or(r.get("players"), new Map());
    for (const [name, p] of list instanceof Map ? list : []) {
      if (!(p instanceof Map)) continue;
      players.push({
        realm, faction, name: String(name),
        level: p.get("lvl") ?? null, class_raw: or(p.get("class"), ""), token: or(p.get("token"), ""),
        race_raw: or(p.get("race"), ""), sex: p.get("sex") ?? null, guild: or(p.get("guild"), ""),
        area: or(p.get("area"), ""), first: p.get("first") ?? null, last: p.get("last") ?? null,
        seen: or(p.get("seen"), 0), source,
      });
    }
    out.push({ key: k, realm, faction, players, scans: asList(r.get("scans")).filter(s => s instanceof Map) });
  }
  return { kind, version: db.get("version") ?? null, client: Object.fromEntries(client), realms: out };
}

/** 同一個伺服器＋陣營＋角色名，保留最後看到的那筆，首次看到取最早、次數相加。 */
export function merge(extracts) {
  const realms = new Map();
  for (const ex of extracts) {
    for (const r of ex.realms) {
      let slot = realms.get(r.key);
      if (!slot) {
        slot = { key: r.key, realm: r.realm, faction: r.faction, players: new Map(), scans: [] };
        realms.set(r.key, slot);
      }
      slot.scans.push(...r.scans);
      for (const p of r.players) {
        const cur = slot.players.get(p.name);
        if (!cur) { slot.players.set(p.name, { ...p }); continue; }
        const newer = num0(p.last) >= num0(cur.last);
        const merged = { ...(newer ? p : cur) };
        const firsts = [p.first, cur.first].filter(isNum);
        merged.first = firsts.length ? Math.min(...firsts) : null;
        merged.last = Math.max(num0(p.last), num0(cur.last)) || null;
        merged.seen = num0(p.seen) + num0(cur.seen);
        merged.token = or(merged.token, or(p.token, cur.token));
        slot.players.set(p.name, merged);
      }
    }
  }
  const out = [...realms.values()].map(slot => ({
    ...slot,
    players: [...slot.players.values()].sort((a, b) => cmpCodePoint(a.name, b.name)),
    scans: slot.scans.sort((a, b) => num0(a.get("at")) - num0(b.get("at"))),
  }));
  return out.sort((a, b) => cmpCodePoint(a.key, b.key));
}

export function enrich(realms) {
  const unmapped = { class: new Map(), race: new Map() };
  for (const r of realms) {
    for (const p of r.players) {
      const ct = mapClass(p.class_raw, p.token), rt = mapRace(p.race_raw);
      p.class_token = ct || "";
      p.class_zh = CLASS_ZH[ct] ?? p.class_raw;
      p.race_token = rt || "";
      p.race_zh = RACE_ZH[rt] ?? p.race_raw;
      if (!ct && truthy(p.class_raw)) unmapped.class.set(p.class_raw, (unmapped.class.get(p.class_raw) || 0) + 1);
      if (!rt && truthy(p.race_raw)) unmapped.race.set(p.race_raw, (unmapped.race.get(p.race_raw) || 0) + 1);
    }
  }
  return unmapped;
}

/** 把 PARTIAL_ROUNDS 補進存檔的 scans：存檔裡要有那段時間看到的人（舊存檔沒有就不加），也還沒有記到同一段的輪 */
function addPartialRounds(realms) {
  for (const pr of PARTIAL_ROUNDS) {
    const r = realms.find(x => x.realm === pr.realm && x.faction === pr.faction);
    if (!r || !r.players.some(p => truthy(p.last) && p.last >= pr.started && p.last <= pr.at)) continue;
    const startOf = s => (isNum(s.get("started")) ? s.get("started") : num0(s.get("at")) - num0(s.get("secs")));
    if (r.scans.some(s => num0(s.get("at")) >= pr.started && startOf(s) <= pr.at)) continue;
    r.scans.push(new Map([["started", pr.started], ["at", pr.at], ["secs", pr.at - pr.started], ["levels", "1-60"], ["mode", "partial"]]));
    r.scans.sort((a, b) => num0(a.get("at")) - num0(b.get("at")));
  }
}

/** Read one or more save files (bytes or text) the same way parse_denizens.py does. */
export function readSaves(files) {
  const extracts = files.map(f => extract(parseSavedVariables(f.data), f.name));
  const realms = merge(extracts);
  addPartialRounds(realms);
  const unmapped = enrich(realms);
  return { extracts, realms, unmapped };
}

// ---------------------------------------------------------------------------
// 網站用的彙總（沒有角色名）
// ---------------------------------------------------------------------------

const classKey = p => p.class_token || "?" + p.class_raw;
const raceKey = p => p.race_token || "?" + p.race_raw;
const inc = (m, k, by = 1) => m.set(k, (m.get(k) || 0) + by);

function aggregate(players) {
  const classes = new Map(), races = new Map(), matrix = new Map(), guilds = new Map(), langs = new Map();
  const levels = [];
  for (const p of players) {
    const ck = classKey(p), rk = raceKey(p);
    inc(classes, ck);
    inc(races, rk);
    inc(matrix, ck + "|" + rk);
    const lv = Number.isInteger(p.level) ? Math.min(100, Math.max(0, p.level)) : 0;
    levels[lv] = (levels[lv] || 0) + 1;
    if (truthy(p.guild)) inc(guilds, p.guild);
    if (NAME_RULES) inc(langs, nameLang(p.name));   // 只留各類人數，角色名不上傳
  }
  for (let i = 0; i < levels.length; i++) levels[i] = levels[i] || 0;
  return {
    n: players.length,
    classes: Object.fromEntries(classes),
    races: Object.fromEntries(races),
    matrix: Object.fromEntries(matrix),
    ...(NAME_RULES ? { langs: Object.fromEntries(langs) } : {}),
    levels,
    guilds: {
      count: guilds.size,
      members: [...guilds.values()].reduce((a, b) => a + b, 0),
      top: mostCommon(guilds, 10).map(([g, c]) => [String(g), c]),
    },
  };
}

/** A complete census pass: every level, no custom filter. Custom /dz deep queries are not rounds. */
export function isFullRound(s) {
  if (truthy(get(s, "query"))) return false;
  const lv = get(s, "levels");
  if (lv === undefined || lv === null) return true;
  const m = /^\s*1\s*-\s*(\d+)\s*$/.exec(String(lv));
  return !!m && Number(m[1]) >= 60;
}

// 網站公布的角色只算「最後一次被看到的時間，落在某一輪完整普查之內」的人（老闆 10/19：刪掉 10/18 晚上的聯盟測試取樣）。
// 完整普查＝沒有取消、查全部等級的那一輪，時間取 started～at；測試期間、輪和輪之間零星看到的都不算。
// 上傳、彙整時篩（普查彙總 buildSlices、深度數據 upload-insights.mjs），不改存檔
export function inRounds(players, scans) {
  const wins = [];
  for (const s of scans) {
    if (truthy(get(s, "cancelled")) || !isFullRound(s)) continue;
    const at = get(s, "at"), secs = get(s, "secs"), started = get(s, "started");
    const start = isNum(started) ? started : isNum(at) && isNum(secs) ? at - secs : null;
    if (isNum(at) && start !== null) wins.push([start, at]);
  }
  return players.filter(p => truthy(p.last) && wins.some(([a, b]) => a <= p.last && p.last <= b));
}

const intOrNull = v => (isNum(v) && Number.isSafeInteger(Math.round(v)) ? Math.max(0, Math.round(v)) : null);

// 一輪普查「找到」幾人：插件記的 found 在普查途中用過誰的視窗時會被清掉重算、偏低（10/19 那輪記 1,307，實際 17,521）；
// 「最後一次被看到的時間落在這一輪內」的人數也是下限，兩者取大的（和 tools/parse_denizens.py 的 found_of 一樣）。
function roundFound(s, players) {
  const at = get(s, "at"), secs = get(s, "secs"), started = get(s, "started");
  const start = truthy(started) ? started : Number.isInteger(at) && Number.isInteger(secs) ? at - secs : null;
  let inside = 0;
  if (start && at) for (const p of players) if (truthy(p.last) && start <= p.last && p.last <= at) inside++;
  return Math.max(num0(get(s, "found")), inside);
}

function slice(r, phase, players, scans) {
  const snapshot = players.reduce((m, p) => Math.max(m, num0(p.last)), 0);
  const within = secs => players.filter(p => truthy(p.last) && snapshot - p.last <= secs);
  const active = within(ACTIVE_DAYS * 86400);
  const day = within(86400);
  const base = active.length ? active : players;

  const rounds = scans.filter(s => !truthy(s.get("cancelled")) && isFullRound(s));
  const last = rounds[rounds.length - 1];
  const passFrom = last ? (isNum(last.get("started")) ? last.get("started") : num0(last.get("at")) - num0(last.get("secs"))) : null;
  const pass = passFrom === null ? day : players.filter(p => truthy(p.last) && p.last >= passFrom);

  const lastAt = last ? num0(last.get("at")) : 0;
  let recent = rounds.filter(s => lastAt - num0(s.get("at")) <= ACTIVE_DAYS * 86400);
  if (recent.length < 20) recent = rounds.slice(-20);
  const sum = key => rounds.reduce((a, s) => a + num0(s.get(key)), 0);

  // 每個範圍實際涵蓋的期間：[範圍起點之後最早看到人的時間, 最後看到人的時間]（網頁顯示「起算」「更新」用）
  const span = (list, from, to) => {
    if (!list.length) return null;
    let lo = Infinity, hi = 0;
    for (const p of list) {
      lo = Math.min(lo, Math.max(from, num0(or(p.first, p.last))));
      hi = Math.max(hi, Math.min(to, num0(p.last)));
    }
    return [Math.round(Math.min(lo, hi)), Math.round(hi)];   // 存檔時間怪怪的（first 比 last 晚）也不要讓整份上傳被擋
  };
  // 封測最後三天：最後一次被看到在起點之後、第一次被看到在終點之前（也就是這段期間在線上出現過）
  const camp = players.filter(p => truthy(p.last) && p.last >= CAMPAIGN.start && num0(or(p.first, p.last)) < CAMPAIGN.end);

  return {
    v: 1, phase, realm: r.realm, faction: r.faction, snapshot,
    counts: { total: players.length, week: active.length, day: day.length, pass: pass.length, ...(camp.length ? { camp: camp.length } : {}) },
    windows: {
      week: { ...aggregate(base), span: span(base, snapshot - ACTIVE_DAYS * 86400, snapshot) },
      day: { ...aggregate(day), span: span(day, snapshot - 86400, snapshot) },
      pass: { ...aggregate(pass), span: span(pass, passFrom ?? snapshot - 86400, snapshot) },
      ...(camp.length ? { camp: { ...aggregate(camp), span: span(camp, CAMPAIGN.start, CAMPAIGN.end), range: [CAMPAIGN.start, CAMPAIGN.end] } } : {}),
    },
    rounds: { n: rounds.length, secs: Math.round(sum("secs")), sent: Math.round(sum("sent")), found: rounds.reduce((a, s) => a + roundFound(s, players), 0) },
    scans: recent.slice(-300).map(s => ({
      at: intOrNull(s.get("at")), started: intOrNull(s.get("started")), found: roundFound(s, players),
      new: intOrNull(s.get("new")), sent: intOrNull(s.get("sent")), secs: intOrNull(s.get("secs")),
      mode: typeof s.get("mode") === "string" ? s.get("mode").slice(0, 12) : "", capped: intOrNull(s.get("capped")),
    })),
  };
}

/**
 * One summary per phase × realm × faction. Players and rounds seen before launch are
 * "beta" (封測), from launch on "live" (亞服), so beta data never leaks into launch numbers.
 */
export function buildSlices(realms, { launchTs = LAUNCH_TS } = {}) {
  const out = [];
  for (const r of realms) {
    const groups = { beta: { players: [], scans: [] }, live: { players: [], scans: [] } };
    for (const p of inRounds(r.players, r.scans)) groups[num0(p.last) >= launchTs ? "live" : "beta"].players.push(p);
    for (const s of r.scans) groups[num0(s.get("at")) >= launchTs ? "live" : "beta"].scans.push(s);
    for (const phase of ["beta", "live"]) {
      const g = groups[phase];
      if (g.players.length) out.push(slice(r, phase, g.players, g.scans));
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// parse_denizens.py「報告.md」裡每個伺服器＋陣營的數字（給上傳頁預覽和對答案用）
// ---------------------------------------------------------------------------

export function realmReport(r) {
  const players = r.players;
  const snapshot = players.reduce((m, p) => Math.max(m, num0(p.last)), 0);
  const active = players.filter(p => truthy(p.last) && snapshot - p.last <= ACTIVE_DAYS * 86400);
  const day = players.filter(p => truthy(p.last) && snapshot - p.last <= 86400);
  const base = active.length ? active : players;
  const tally = keyOf => { const m = new Map(); for (const p of base) inc(m, keyOf(p)); return mostCommon(m); };
  const buckets = new Map();
  for (const p of base) {
    const lv = Number.isInteger(p.level) ? p.level : 0;
    inc(buckets, Math.max(0, Math.floor((lv - 1) / 5)));
  }
  const guilds = new Map();
  for (const p of base) if (truthy(p.guild)) inc(guilds, p.guild);
  const scans = r.scans.filter(s => !truthy(get(s, "cancelled")));
  const sent = scans.reduce((a, s) => a + num0(get(s, "sent")), 0);
  const secs = scans.reduce((a, s) => a + num0(get(s, "secs")), 0);
  return {
    realm: r.realm, faction: r.faction, snapshot,
    total: players.length, week: active.length, day: day.length, n: base.length,
    classes: tally(classKey), races: tally(raceKey),
    langs: NAME_RULES ? tally(p => nameLang(p.name)) : null,
    levels: [...buckets.entries()].sort((a, b) => a[0] - b[0]),
    guilds: { count: guilds.size, members: [...guilds.values()].reduce((a, b) => a + b, 0), top: mostCommon(guilds, 10) },
    scans: scans.map(s => ({ ...Object.fromEntries(s), found: roundFound(s, players) })),
    secsPerQuery: sent && secs ? secs / sent : null,
    foundPerRound: scans.length ? scans.reduce((a, s) => a + roundFound(s, players), 0) / scans.length : null,
  };
}

/** Python's format(x, ".Nf"): round half to even on the exact binary value. */
export function pyFixed(x, digits = 1) {
  if (!Number.isFinite(x)) return String(x);
  const neg = x < 0;
  const view = new DataView(new ArrayBuffer(8));
  view.setFloat64(0, Math.abs(x));
  const hi = view.getUint32(0), lo = view.getUint32(4);
  const e = (hi >>> 20) & 0x7ff;
  let mant = (BigInt(hi & 0xfffff) << 32n) | BigInt(lo);
  let exp;
  if (e === 0) exp = -1074;
  else { mant |= 1n << 52n; exp = e - 1075; }
  const scaled = mant * 10n ** BigInt(digits);
  let q;
  if (exp >= 0) q = scaled << BigInt(exp);
  else {
    const sh = BigInt(-exp);
    q = scaled >> sh;
    const rem = scaled - (q << sh), half = 1n << (sh - 1n);
    if (rem > half || (rem === half && (q & 1n) === 1n)) q += 1n;
  }
  let s = q.toString();
  if (digits > 0) {
    s = s.padStart(digits + 1, "0");
    s = s.slice(0, -digits) + "." + s.slice(-digits);
  }
  return (neg ? "-" : "") + s;
}
