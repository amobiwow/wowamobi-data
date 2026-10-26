PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE loot_kills (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  ukey      TEXT    NOT NULL UNIQUE,
  realm     TEXT    NOT NULL,
  enc       INTEGER NOT NULL,   -- 首領（遊戲 DungeonEncounter 編號，和網站副本資料庫一樣）
  map       INTEGER NOT NULL,   -- 副本地圖編號
  diff      INTEGER,
  size      INTEGER,
  copy      TEXT,               -- 副本分身編號（屍體 GUID 裡的那一段；有人打開過屍體才有）
  t         INTEGER NOT NULL,   -- 伺服器時間（unix 秒）
  phase     TEXT    NOT NULL CHECK (phase IN ('beta', 'live')),   -- 開服（2026-11-05 07:00）以前的算 beta
  full      INTEGER NOT NULL DEFAULT 0,   -- 1＝有人打開過屍體或寶箱（掉落清單是完整的）；0＝只記到隊伍擲骰的物品
  reporters INTEGER NOT NULL DEFAULT 0,   -- 幾個人回報過這場
  created   INTEGER NOT NULL
);
