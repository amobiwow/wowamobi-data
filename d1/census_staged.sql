PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE census_staged (
  phase      TEXT    NOT NULL CHECK (phase IN ('beta', 'live')),
  realm      TEXT    NOT NULL,
  faction    TEXT    NOT NULL CHECK (faction IN ('Alliance', 'Horde')),
  rounds     INTEGER NOT NULL,   -- 完整普查輪數（data 的 rounds.n）
  snapshot   INTEGER NOT NULL,
  data       TEXT    NOT NULL,   -- 和 census_slices.data 一樣的彙總 JSON
  files      TEXT    NOT NULL DEFAULT '[]',
  staged_at  INTEGER NOT NULL,
  PRIMARY KEY (phase, realm, faction, rounds)
);
