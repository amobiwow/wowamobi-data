// 開服那段只算前 N 輪完整普查（upload-census.mjs、upload-insights.mjs 的 --rounds=N 共用）。
// 老闆 11/5：部落那台一口氣跑了 2 輪、聯盟 1 輪，「先上第一輪」；11/6：「我明明才說上到第七輪」。
// 存檔只留每個人最後一次被看到的樣子，沒有每一輪的紀錄，所以：第 N 輪結束後才第一次看到的人不算；
// 第 N 輪結束前就看過、後來又被看到的人，最後看到的時間改成第 N 輪結束（等級、區域是後來看到的）；第 N 輪之後的普查紀錄拿掉。
// 存檔剛好 N 輪、後面還有一輪跑到一半（老闆 11/5 聯盟第 6 輪跑到 14:12 停了，「我只有叫你算第五輪阿」）：一樣切在第 N 輪結束。
import { FACTION_ZH, isFullRound, LAUNCH_TS } from "../public/assets/denizens.js";

export function roundsArg(args) {
  const v = (args.find(a => a.startsWith("--rounds=")) || "").slice(9);
  if (!v) return null;
  const n = Number(v);
  if (!Number.isInteger(n) || n < 1) { console.error("--rounds 要是 1 以上的整數"); process.exit(2); }
  return n;
}

/** readSaves 的 realms 就地切到第 n 輪結束；存檔不到 n 輪的伺服器不動。 */
export function cutRounds(realms, n, log = console.log) {
  for (const r of realms) {
    const at = s => Number(s.get("at")) || 0;
    const full = r.scans.filter(s => !s.get("cancelled") && isFullRound(s) && at(s) >= LAUNCH_TS).sort((a, b) => at(a) - at(b));
    if (full.length < n) continue;
    const cut = at(full[n - 1]);
    const before = r.players.length;
    r.scans = r.scans.filter(s => at(s) <= cut);
    r.players = r.players.filter(p => (Number(p.first ?? p.last) || 0) <= cut).map(p => (Number(p.last) > cut ? { ...p, last: cut } : p));
    log(`${r.realm} | ${FACTION_ZH[r.faction]} | 開服只算前 ${n} 輪（存檔有 ${full.length} 輪，到 ${new Date(cut * 1000).toLocaleString("zh-TW", { timeZone: "Asia/Taipei" })}）：`
      + `第 ${n} 輪之後才看到的 ${before - r.players.length} 人不算`);
  }
  return realms;
}
