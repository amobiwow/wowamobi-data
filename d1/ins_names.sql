PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE ins_names (
  phase    TEXT NOT NULL,
  nkey     TEXT NOT NULL,   -- 名字 NFKC＋小寫
  realm    TEXT NOT NULL,
  faction  TEXT NOT NULL,
  name     TEXT NOT NULL,
  cls      TEXT NOT NULL DEFAULT '',
  PRIMARY KEY (phase, nkey, realm, faction)
) WITHOUT ROWID;
