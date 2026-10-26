PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE meta (
  k TEXT PRIMARY KEY,
  v TEXT NOT NULL
);
INSERT INTO "meta" ("k","v") VALUES('news_fetched_at','1793030455');
INSERT INTO "meta" ("k","v") VALUES('news_found','12');
INSERT INTO "meta" ("k","v") VALUES('news_error','');
INSERT INTO "meta" ("k","v") VALUES('blue_fetched_at','1793030455');
INSERT INTO "meta" ("k","v") VALUES('blue_found','8');
INSERT INTO "meta" ("k","v") VALUES('blue_error','');
INSERT INTO "meta" ("k","v") VALUES('site_stats','{"visitors":2,"pages":2,"at":1793030457,"since":1793030400,"rows":3}');
