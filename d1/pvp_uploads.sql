PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE pvp_uploads (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  reporter TEXT    NOT NULL,
  t        INTEGER NOT NULL,
  kills    INTEGER NOT NULL,
  fresh    INTEGER NOT NULL,
  dup      INTEGER NOT NULL,
  limited  INTEGER NOT NULL,
  rejected INTEGER NOT NULL
);
