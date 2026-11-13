PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE meta (
  k TEXT PRIMARY KEY,
  v TEXT NOT NULL
);
INSERT INTO "meta" ("k","v") VALUES('news_fetched_at','1794572156');
INSERT INTO "meta" ("k","v") VALUES('news_found','18');
INSERT INTO "meta" ("k","v") VALUES('news_error','');
INSERT INTO "meta" ("k","v") VALUES('blue_fetched_at','1794572156');
INSERT INTO "meta" ("k","v") VALUES('blue_found','4');
INSERT INTO "meta" ("k","v") VALUES('blue_error','');
INSERT INTO "meta" ("k","v") VALUES('site_stats','{"visitors":6193,"pages":25916,"at":1794572456,"since":1794499200,"rows":9000,"sample":1.01}');
INSERT INTO "meta" ("k","v") VALUES('news_error_at','1793833256');
INSERT INTO "meta" ("k","v") VALUES('blue_error_at','1794266156');
