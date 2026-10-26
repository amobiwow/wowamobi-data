PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE auction_realms (
  phase     TEXT    NOT NULL CHECK (phase IN ('beta', 'live')),
  realm     TEXT    NOT NULL,
  faction   TEXT    NOT NULL CHECK (faction IN ('Alliance', 'Horde', 'Neutral')),
  last_full INTEGER,            -- 最近一次讀完的全掃描（完成時間）
  last_any  INTEGER NOT NULL,   -- 最近一次任何記錄（完成時間）
  PRIMARY KEY (phase, realm, faction)
) WITHOUT ROWID;
