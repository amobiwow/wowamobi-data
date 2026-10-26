PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE pvp_kills (
  id             TEXT    PRIMARY KEY,   -- sha-256(伺服器|回報的人|對方名字|時間) 的前 32 碼：同一個人、同一個對方、同一秒的重傳擋掉
  at             INTEGER NOT NULL,      -- 伺服器時間（unix 秒，回報的人收到榮譽訊息的時候）
  realm          TEXT    NOT NULL,      -- 伺服器名稱（遊戲的寫法）
  map            INTEGER,               -- 地圖（C_Map 的 uiMapID）
  inst           INTEGER,               -- 在戰場、副本裡：副本地圖編號；野外是 0
  zone           TEXT,                  -- 區域中文名（GetRealZoneText；小幫手 1.7.0 傳的沒有）
  victim         TEXT    NOT NULL,      -- 被殺的部落玩家名字（遊戲訊息裡的寫法）
  victim_rank    TEXT,                  -- 對方的軍銜（遊戲文字；沒有軍銜的是空的）
  honor          INTEGER,               -- 估計榮譽
  reporter       TEXT    NOT NULL,      -- 回報的聯盟角色名字（密語的寄件人，站長的插件收到時記的）
  reporter_class TEXT,                  -- 回報的人的職業（UnitClass 的英文代號，例如 MAGE）
  reporter_level INTEGER,
  reporter_guild TEXT,                  -- 回報的人的公會名（沒有公會是空的）
  group_size     INTEGER,               -- 隊伍人數（0＝自己一個人）
  uploaded_at    INTEGER NOT NULL
, reporter_faction TEXT NOT NULL DEFAULT 'Alliance' CHECK (reporter_faction IN ('Alliance', 'Horde')));
