PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE ins_hidden (
  realm    TEXT    NOT NULL,
  faction  TEXT    NOT NULL,
  nkey     TEXT    NOT NULL,
  name     TEXT    NOT NULL,
  at       INTEGER NOT NULL,
  via      TEXT    NOT NULL DEFAULT 'web',   -- web＝角色頁的申請，owner＝站長手動
  PRIMARY KEY (realm, faction, nkey)
) WITHOUT ROWID;
