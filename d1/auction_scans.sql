PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE auction_scans (
  realm     TEXT    NOT NULL,
  faction   TEXT    NOT NULL CHECK (faction IN ('Alliance', 'Horde', 'Neutral')),
  t         INTEGER NOT NULL,   -- 開始的時間（unix 秒，拿來認同一次掃描）
  kind      TEXT    NOT NULL CHECK (kind IN ('full', 'browse')),   -- full 全掃描、browse 瀏覽時看到的
  end_t     INTEGER NOT NULL,   -- 完成的時間（網站寫這個）
  phase     TEXT    NOT NULL CHECK (phase IN ('beta', 'live')),
  auctions  INTEGER,            -- 拍賣筆數（瀏覽的不知道）
  items     INTEGER NOT NULL,   -- 物品種數
  partial   INTEGER NOT NULL DEFAULT 0,   -- 1＝沒讀完（數字不用）
  upload_id INTEGER NOT NULL,
  PRIMARY KEY (realm, faction, t, kind)
) WITHOUT ROWID;
