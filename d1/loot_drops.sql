PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE loot_drops (
  kill_id INTEGER NOT NULL,
  item_id INTEGER NOT NULL,
  n       INTEGER NOT NULL,
  PRIMARY KEY (kill_id, item_id)
) WITHOUT ROWID;
