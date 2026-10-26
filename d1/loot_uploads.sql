PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE loot_uploads (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  who       TEXT    NOT NULL,
  t         INTEGER NOT NULL,
  kills     INTEGER NOT NULL,
  new_kills INTEGER NOT NULL,
  drops     INTEGER NOT NULL,
  build     TEXT
);
