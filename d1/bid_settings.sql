PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE bid_settings (
  k  TEXT PRIMARY KEY,
  v  TEXT NOT NULL
);
INSERT INTO "bid_settings" ("k","v") VALUES('pass','123456');
INSERT INTO "bid_settings" ("k","v") VALUES('pass_at','1792886486');
INSERT INTO "bid_settings" ("k","v") VALUES('guild','阿莫比（測試名單）');
INSERT INTO "bid_settings" ("k","v") VALUES('roster_at','1792886693');
INSERT INTO "bid_settings" ("k","v") VALUES('roster_count','1');
