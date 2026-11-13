// 普查深度數據：上傳端（insights-sync.js）和 Worker（src/insights.js）共用的小規則。
// 角色、公會依名字雜湊分包存在 D1（ins_rows），兩邊一定要算出同一包，所以放在同一個檔。

export const NB_CHAR = 256;   // 角色分成幾包（一包約 80～200 個角色）
export const NB_GUILD = 32;   // 公會分成幾包
export const PHASE_RE = /^[a-z0-9]{1,12}$/;   // 階段代碼：beta（開服前）、live（開服後），之後可以加新的
// 目前有的階段（和 insights-sync.js 的 PHASES 一樣；check-insights.mjs 會檢查）。移除申請要一個一個階段找角色。
export const PHASE_IDS = ["beta", "live"];
export const FACTIONS = ["Alliance", "Horde"];

/** 名字比對用的鍵：NFKC＋小寫（搜尋不分大小寫，全形半形視為一樣）。 */
export const nameKey = s => String(s ?? "").normalize("NFKC").toLowerCase();

/** FNV-1a 32 位元，對 UTF-8 位元組算。 */
export function fnv1a(s) {
  let h = 0x811c9dc5;
  for (const b of new TextEncoder().encode(s)) {
    h ^= b;
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

/** 第幾包，補零成三位數字串（D1 依文字排序也會照順序）。 */
export const bucketOf = (key, n) => String(fnv1a(key) % n).padStart(3, "0");

/** 台灣日期 YYYY-MM-DD（台灣沒有夏令時間，一律 UTC+8）。 */
export const twDate = sec => new Date(sec * 1000 + 8 * 3600 * 1000).toISOString().slice(0, 10);
