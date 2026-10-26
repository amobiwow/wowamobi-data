// 競拍場（/bid）的規則和分錢算法：網頁（bid.js）和競拍主機（src/bid-hub.js）共用同一份，算出來一定一樣。
// 老闆的「有限 2 標緣份團」（2026-10-25 定案，競拍場-UI企劃.md）：
//   起標＝商店價 2 倍（往上進位到整數金、至少 1 金）；上限＝商店價 100 倍（往下捨去、不低於起標）。
//   出價只能整數金、一定要比目前最高價高；15 秒沒人再出就結標（老闆 10/25：5 秒太快，自己都來不及按）；出到上限的人可以「也出上限」，結標時網站擲骰（1–100，老闆 10/26 從回遊戲 /roll 改的）。
//   紫裝以上一人一場限得標 2 件（擲骰贏的、補記的都算；大禮包、自訂物品不算）。
//   分錢：團長 lead%、坦補會計按人頭 roles%、剩下全團（含他們）均分。每一件只分給成交當下在團裡的人；
//   每一件、每個人先捨去到銀，除不盡的零頭留給會計。
//   只能標自己職業能用的裝（老闆 10/25）：進來時自己選職業；物品的職業限制在 bid-items.json 的 cls（public/data/class-gear.json）。
//   明標、暗標（老闆 10/25）：會計上架時選。明標＝上面這樣大家一直加價；暗標＝上架後 10 分鐘內，想標的人自己出一次價（出了不能改、
//   別人看不到），時間到網站掀牌：公開誰出了多少，出最高的人用他出的價得標；最高價平手的由網站擲骰（1–100）決定。
//   掀牌時已經不能標的人（離開了、紫裝已經標滿 2 件、被設成禁拍者）跳過，給下一個出最高的。暗標可以好幾件同時進行，不擋明標。
//   棄標（老闆 10/25）：得標的人不要了，會計在「已成交」標棄標。那一筆留著（後面的件數順序不變），但不算錢、不算限 2 件，
//   得標的人記「醜」一次；會計自己再上架一次。
// 金額單位：銅（1 金＝10,000 銅、1 銀＝100 銅）。出價、成交價存「金」（整數）。

export const G = 10000, S = 100;
export const SECS = 15;           // 15 秒沒人再出就結標（第一口價也是 15 秒；老闆 10/25 從 5 秒改）
export const START_SECS = 10;     // 會計按「倒數 10 秒開始」後倒數幾秒（老闆 10/26：不管幾個人參與都要倒數，從 5 秒改 10 秒；倒數中還能按參與）
export const SEALED_SECS = 300;   // 暗標：上架後 5 分鐘掀牌（老闆 10/25 定 10 分鐘，10/26 改 5 分鐘）
export const MAX_SEALED = 20;     // 暗標同時最多幾件
export const MAX_WINS = 2;        // 紫裝以上一人限幾件的預設值（老闆 10/26：會計開單時可以改，room.maxWins；0＝不限）
export const PURPLE = 4;          // 品質 4＝史詩（紫），5＝傳說

export const startOf = sell => Math.max(1, Math.ceil((Number(sell) || 0) * 2 / G));
export const capOf = sell => Math.max(startOf(sell), Math.floor((Number(sell) || 0) * 100 / G));
export const floorSilver = c => Math.floor(c / S) * S;
export const counts = item => !!item && !item.custom && (item.q || 0) >= PURPLE;   // 算在紫裝件數裡

// 永恆可以玩的 9 個職業（ChrClasses；位元＝1 << (職業編號 − 1)，和 class-gear.json 一樣）、職業顏色
export const CLASSES = [
  { token: "WARRIOR", name: "戰士", bit: 1, color: "#c79c6e" }, { token: "PALADIN", name: "聖騎士", bit: 2, color: "#f58cba" },
  { token: "HUNTER", name: "獵人", bit: 4, color: "#abd473" }, { token: "ROGUE", name: "盜賊", bit: 8, color: "#fff569" },
  { token: "PRIEST", name: "牧師", bit: 16, color: "#ffffff" }, { token: "SHAMAN", name: "薩滿", bit: 64, color: "#0070de" },
  { token: "MAGE", name: "法師", bit: 128, color: "#69ccf0" }, { token: "WARLOCK", name: "術士", bit: 256, color: "#9482c9" },
  { token: "DRUID", name: "德魯伊", bit: 1024, color: "#ff7d0a" },
];
export const classOf = token => CLASSES.find(c => c.token === token) || null;
// 每個職業的三個天賦（永恆的天賦樹名稱，照網站 public/data/talents.json）：「天賦審查限定」時進來要選
export const SPECS = {
  WARRIOR: ["武器", "狂怒", "防護"], PALADIN: ["神聖", "防護", "懲戒"], HUNTER: ["野獸控制", "射擊", "生存技能"],
  ROGUE: ["刺殺", "戰鬥", "敏銳"], PRIEST: ["戒律", "神聖", "暗影魔法"], SHAMAN: ["元素戰鬥", "增強", "恢復"],
  MAGE: ["秘法", "火焰", "冰霜"], WARLOCK: ["痛苦", "惡魔學識", "毀滅"], DRUID: ["平衡", "野性戰鬥", "恢復"],
};
export const specOk = (cls, spec) => !!(SPECS[cls] && SPECS[cls].includes(spec));
// 本團規則（老闆 10/25：「新增一個團長功能，他可以選此團附加條件」）：
//   cls   職業能用才能標（網站直接判斷；預設開）
//   armor 穿什麼甲進來就只能標那種甲（只寫出來，網站不判斷）
//   spec  天賦審查：只能標自己天賦專用的裝（只寫出來，團長看大家選的天賦審查）
export const RULES = [
  { key: "cls", name: "職業能用才能標", note: "網站直接判斷：職業穿不了、拿不了的不能參與", def: true },
  { key: "armor", name: "穿什麼甲進來就只能標那種甲", note: "只寫出來給大家看，網站不判斷", def: false },
  { key: "spec", name: "天賦審查：只能標自己天賦專用的裝", note: "進來要選天賦，團長看名單審查；網站不判斷", def: false },
];
export const ruleOn = (room, key) => (room?.rules && key in room.rules ? !!room.rules[key] : RULES.find(r => r.key === key).def);
// 這件哪些職業能用（item.cls 是位元，0／沒有＝不限）
export const classNames = mask => CLASSES.filter(c => mask & c.bit).map(c => c.name);
export const usable = (item, token) => !item?.cls || !!(classOf(token) && item.cls & classOf(token).bit);

export const comma = n => Math.round(n).toLocaleString("en-US");
export function gold(c) {
  const g = Math.floor(c / G), s = Math.floor((c % G) / S);
  return g ? `${comma(g)} 金${s ? ` ${s} 銀` : ""}` : `${s} 銀`;
}
export const goldOnly = g => `${comma(g)} 金`;
export function sellText(c) {
  const g = Math.floor(c / G), s = Math.floor((c % G) / S), b = c % S;
  return [g && `${g} 金`, s && `${s} 銀`, b && `${b} 銅`].filter(Boolean).join(" ") || "0 銅";
}

// 第 k 件成交時這個人在不在團裡（joinAt＝進來時已經成交幾件；leftAt＝離開／被換掉時已經成交幾件）
// 名字重複、還沒綁定的（dupOf，老闆 10/26：忘了密碼用新密碼進來的「谷阿莫（重複1）」）不算：綁定之後都算在原本那個人
export const present = (m, k) => !m.dupOf && m.joinAt <= k && (m.leftAt == null || m.leftAt > k);

// 第 k 件成交時的會計（會計可以中途換手：accHist＝[{id, from: 從第幾件起}]）
export function accAt(room, k) {
  let id = room.accHist?.[0]?.id ?? room.acc;
  for (const h of room.accHist || []) if (h.from <= k) id = h.id;
  return id;
}

// 第 k 件成交時的團長（老闆 10/26：轉讓團長之後，「這一刻開始，後面產生的收益，團長 10% 的部份就會變成新團長的」）：
// leadHist＝[{id, from: 從第幾件起}]，跟會計交接一樣；舊的房間沒有 leadHist，照現在的團長算
export function leadAt(room, k) {
  if (!room.leadHist?.length) return room.members.find(m => (m.roles || []).includes("lead"))?.id ?? null;
  let id = null;
  for (const h of room.leadHist) if (h.from <= k) id = h.id;
  return id;
}

// 第 k 件成交時這個人的坦、補：有人領收離開之後再改身分，從下一件起才算（roleHist＝[{roles, from}]，老闆 10/26：坦補可以很多位，要能隨時改）
export function rolesAt(m, k) {
  if (!m.roleHist?.length) return (m.roles || []).filter(x => x !== "lead");
  let r = m.roleHist[0].roles;
  for (const h of m.roleHist) if (h.from <= k) r = h.roles;
  return r;
}

const roleOf = (room, m, k) => {
  const r = new Set(rolesAt(m, k));
  if (accAt(room, k) === m.id) r.add("acc");
  if (leadAt(room, k) === m.id) r.add("lead");
  return r;
};

/** 第 k 件怎麼分：每個人都先捨去到銀，零頭（odd）留給會計。 */
export function split(room, k) {
  const s = room.sales[k];
  const c = s.void ? 0 : s.price * G;   // 棄標的這件沒有錢可以分
  const here = room.members.filter(m => present(m, k));
  const roles = new Map(here.map(m => [m.id, roleOf(room, m, k)]));
  const lead = here.find(m => roles.get(m.id).has("lead"));
  const holders = here.filter(m => { const r = roles.get(m.id); return r.has("tank") || r.has("heal") || r.has("acc"); });
  const hasTankHeal = here.some(m => { const r = roles.get(m.id); return r.has("tank") || r.has("heal"); });   // 每一件看當時的身分
  // 坦補會計那 10%（老闆 10/26：「有幾人就分幾人」）：新開的團（split 2）只要有坦、補或會計就發，沒有坦補時就是會計一個人拿；
  // 10/26 以前開的團照舊（有坦或補才發，不然併進全團均分），已經成交的帳才不會變
  const leadPct = lead ? room.pct.lead : 0, rolePct = holders.length && (room.split >= 2 || hasTankHeal) ? room.pct.roles : 0;
  const leadCut = floorSilver(c * leadPct / 100);
  const rolePer = rolePct ? floorSilver(c * rolePct / 100 / holders.length) : 0;
  const restPer = here.length ? floorSilver(c * (100 - leadPct - rolePct) / 100 / here.length) : 0;
  const paidOut = leadCut + rolePer * (rolePct ? holders.length : 0) + restPer * here.length;
  return { c, here, lead, holders: rolePct ? holders : [], leadCut, rolePer, restPer, odd: c - paidOut };
}

/** 每個人到第 upto 件（不含）為止分到多少銅；odd＝零頭總和，算給「目前的會計」。 */
export function shares(room, upto = room.sales.length) {
  const by = new Map(room.members.map(m => [m.id, 0]));
  let total = 0, odd = 0;
  for (let k = 0; k < upto; k++) {
    const x = split(room, k);
    total += x.c;
    odd += x.odd;
    if (x.lead) by.set(x.lead.id, by.get(x.lead.id) + x.leadCut);
    for (const m of x.holders) by.set(m.id, by.get(m.id) + x.rolePer);
    for (const m of x.here) by.set(m.id, by.get(m.id) + x.restPer);
  }
  return { by, total, odd };
}

/** 每個人分到的拆成三份：全團均分、坦補會計、團長各多少銅（老闆 10/26：「不然你就把明細也放上去給大家檢查」）。
 *  sum：三份各自加起來、零頭、總收入；團長那一份加起來＝總收入的 10%，坦補會計那一份也是（除不盡的幾銀算零頭）。 */
export function shareParts(room, upto = room.sales.length) {
  const by = new Map(room.members.map(m => [m.id, { rest: 0, role: 0, lead: 0 }]));
  const get = id => { if (!by.has(id)) by.set(id, { rest: 0, role: 0, lead: 0 }); return by.get(id); };
  const sum = { rest: 0, role: 0, lead: 0, odd: 0, total: 0 };
  for (let k = 0; k < upto; k++) {
    const x = split(room, k);
    sum.total += x.c;
    sum.odd += x.odd;
    if (x.lead) { get(x.lead.id).lead += x.leadCut; sum.lead += x.leadCut; }
    for (const m of x.holders) { get(m.id).role += x.rolePer; sum.role += x.rolePer; }
    for (const m of x.here) { get(m.id).rest += x.restPer; sum.rest += x.restPer; }
  }
  return { by, sum };
}

// 功能開關（老闆 10/26：「先把標幾件、分潤比、拍賣金額不限制隱藏，我還沒有要開放，未來我要開放時你才顯示出來」）
// 關著的時候：網頁不顯示，網站也不收（照預設：紫裝限 2 件、團長 10%／坦補會計 10%／全團 80%、起標 2 倍上限 100 倍）。
// 本機測試可以用 .dev.vars 的 BID_FEATURES=all 讓網站先收（網頁還是不顯示）。
export const FEATURES = { maxWins: false, pctEdit: false, freePrice: false };

// 團長＝開單的人（老闆 10/26：「開單的人就叫做團長，所以他不會是會計，他會設定一個人當會計」）：設本團條件、成員身分、
// 指定會計、換人、移出、關單。會計＝團長指定的另一個人：上架競標、補記、收錢、分錢；還沒指定就沒有會計，不能上架。
// 團長不在了（領收離開），團長的事由會計代。
export const leaderOf = room => room?.members?.find(m => m.leftAt == null && (m.roles || []).includes("lead")) || null;
export const canLead = (room, id) => { const l = leaderOf(room); return l ? l.id === id : room?.acc === id; };
// 關單前要做完的（老闆 10/26：「如果錢沒有全部收完跟領完，團長無法按關單」）：每一筆都收到錢、
// 還在場的人都領收了（團長、會計、沒上網頁的人不算：團長留著關單，會計拿著錢，沒上網頁的按不了）
export function closeBlockers(room) {
  const lead = leaderOf(room);
  const unpaid = (room?.sales || []).filter(s => !s.void && !s.paid);
  const waiting = (room?.members || []).filter(m => m.leftAt == null && !m.offline && !m.dupOf && m.id !== room.acc && m.id !== lead?.id);
  const payout = payoutDue(room);   // 會計還沒付清的人（老闆 10/26：關單前這邊通通都要顯示已支付）
  return { unpaid, waiting, payout, ok: !unpaid.length && !waiting.length && !payout.length };
}

// 已支付（老闆 10/26：「做一個勾給會計，叫做已支付…如果此人領錢後又繼續分到錢，就針對新的未領錢的部份跳一條資料出來」）：
// payouts＝{團員: [{c: 這次付了幾銅, at}]}；會計每勾一次記一筆（付當下還沒付的那一段）
export const paidOutOf = (room, id) => (room?.payouts?.[id] || []).reduce((a, p) => a + p.c, 0);
// 每個人應分、已經付了多少、還差多少（會計自己那份和零頭不用付；名字重複還沒綁定的沒有份）
export function payoutDue(room, all = false) {
  const sh = shares(room);
  return (room?.members || []).filter(m => !m.dupOf && m.id !== room?.acc)
    .map(m => { const owed = sh.by.get(m.id) || 0, paid = paidOutOf(room, m.id); return { m, owed, paid, due: owed - paid }; })
    .filter(x => all || x.due > 0);
}

// 這一團紫裝以上一人限幾件（0＝不限）、這個人是不是標滿了、畫面上怎麼寫
export const maxWinsOf = room => (Number.isInteger(room?.maxWins) ? room.maxWins : MAX_WINS);
export const fullOf = (room, id) => { const mw = maxWinsOf(room); return mw > 0 && winsOf(room, id) >= mw; };
export const winsLabel = (room, id) => { const mw = maxWinsOf(room), w = winsOf(room, id); return mw ? `${w}/${mw}` : `${w}`; };
export const limitLabel = room => (maxWinsOf(room) ? `限 ${maxWinsOf(room)} 件` : "不限件數");
export const countNote = (room, item) => (counts(item) ? `紫裝 · ${maxWinsOf(room) ? `算在限 ${maxWinsOf(room)} 件` : "不限件數"}` : "不算件數");

/** 這個人這一場紫裝以上得標幾件。 */
export const winsOf = (room, id, upto = room.sales.length) =>
  room.sales.slice(0, upto).filter(s => s.buyer === id && !s.void && counts(s.item)).length;

/** 這個人這一場棄標幾次（「醜」幾次）。 */
export const uglyOf = (room, id) => room.sales.filter(s => s.void && s.buyer === id).length;
/** 真的成交、要付錢的（不含棄標的）。 */
export const kept = room => room.sales.filter(s => !s.void);

/** 這個人現在能不能出這一件（回傳 null＝可以，不然是原因）。 */
export function canBidItem(room, m, item) {
  if (!m || m.leftAt != null) return "你已經不在這一團了";
  if (m.offline) return "沒上網頁的成員由會計補記";
  if (m.dupOf) return "你的名字跟團裡的人重複了：等團長「重複綁定」之後才能參與";
  if (item?.banned?.includes(m.id)) return "會計把你設成這件的禁拍者，這件不能標";   // 老闆 10/25：上架時會計可以設禁拍者
  if (counts(item) && fullOf(room, m.id)) return `你這場紫裝已經得標 ${maxWinsOf(room)} 件，紫裝以上不能再出價`;
  if (ruleOn(room, "cls")) {
    if (item?.cls && !classOf(m.cls)) return "這件限職業：先選你的職業（按「修改名字」）";
    if (!usable(item, m.cls)) return `你的職業（${classOf(m.cls).name}）不能用這件，只有${classNames(item.cls).join("、")}能標`;
  }
  return null;
}

/** 成交參考：最近幾次（新的在前）[{price, capped, at}] → 上次、中位數、最低、最高、幾成標到上限 */
export function refStats(rows) {
  if (!rows?.length) return null;
  const p = rows.map(r => r.price).sort((a, b) => a - b);
  const mid = p.length % 2 ? p[(p.length - 1) / 2] : Math.round((p[p.length / 2 - 1] + p[p.length / 2]) / 2);
  return { last: rows[0].price, lastAt: rows[0].at, n: rows.length, med: mid, min: p[0], max: p[p.length - 1],
           capRatio: Math.round(rows.filter(r => r.capped).length / rows.length * 10) };
}

// 4 碼暗碼：拿掉容易看錯的 0 O 1 I L，不分大小寫
export const CODE_CHARS = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
export const normCode = s => String(s || "").toUpperCase().replace(/[^0-9A-Z]/g, "").slice(0, 4);
export const validCode = s => /^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{4}$/.test(s);
export const fullName = (first, last) => `${String(first || "").trim()} ${String(last || "").trim()}`.trim();
export const nameKey = s => String(s ?? "").normalize("NFKC").toLowerCase().replace(/\s+/g, " ").trim();
// 比對公會名單用：連空白都拿掉（遊戲公會畫面的兩段名字中間有沒有空白、網頁兩格怎麼填，都比得到；開服後再確認格式）
export const rosterKey = s => nameKey(s).replace(/ /g, "");
