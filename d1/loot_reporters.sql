PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE loot_reporters (
  kill_id INTEGER NOT NULL,
  who     TEXT    NOT NULL,
  PRIMARY KEY (kill_id, who)
) WITHOUT ROWID;
