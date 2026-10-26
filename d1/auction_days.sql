PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE auction_days (
  item_id    INTEGER NOT NULL,
  phase      TEXT    NOT NULL CHECK (phase IN ('beta', 'live')),
  realm      TEXT    NOT NULL,
  faction    TEXT    NOT NULL CHECK (faction IN ('Alliance', 'Horde', 'Neutral')),
  day        TEXT    NOT NULL,  -- YYYY-MM-DD（台灣時間）
  t          INTEGER NOT NULL,  -- 這筆數字那次掃描的完成時間
  kind       TEXT    NOT NULL CHECK (kind IN ('full', 'browse')),
  qty        INTEGER NOT NULL,  -- 上架數量（一疊 20 個算 20）
  auctions   INTEGER,           -- 拍賣筆數（只看分類清單時不知道）
  min_buyout INTEGER,           -- 最低一口價（單價）；只有競標時是 NULL
  median     INTEGER,           -- 中位數（照數量算）
  low        INTEGER, p10 INTEGER, p25 INTEGER, p75 INTEGER,           -- 那天最低的一口價
  PRIMARY KEY (item_id, phase, realm, faction, day)
) WITHOUT ROWID;
