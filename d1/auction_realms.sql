PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE auction_realms (
  phase     TEXT    NOT NULL CHECK (phase IN ('beta', 'live')),
  realm     TEXT    NOT NULL,
  faction   TEXT    NOT NULL CHECK (faction IN ('Alliance', 'Horde', 'Neutral')),
  last_full INTEGER,            -- 最近一次讀完的全掃描（完成時間）
  last_any  INTEGER NOT NULL,   -- 最近一次任何記錄（完成時間）
  PRIMARY KEY (phase, realm, faction)
) WITHOUT ROWID;
INSERT INTO "auction_realms" ("phase","realm","faction","last_full","last_any") VALUES('live','CAMWOW TW4 Realm 2 PvP','Alliance',1794558350,1794558350);
INSERT INTO "auction_realms" ("phase","realm","faction","last_full","last_any") VALUES('live','CAMWOW TW4 Realm 2 PvP','Horde',1794558095,1794558095);
INSERT INTO "auction_realms" ("phase","realm","faction","last_full","last_any") VALUES('live','CAMWOW TW4 Realm 2 PvP','Neutral',1794550569,1794550569);
