PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE IF NOT EXISTS "d1_migrations"(
		id         INTEGER PRIMARY KEY AUTOINCREMENT,
		name       TEXT UNIQUE,
		applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
);
INSERT INTO "d1_migrations" ("id","name","applied_at") VALUES(1,'0001_init.sql','2026-10-18 11:05:51');
INSERT INTO "d1_migrations" ("id","name","applied_at") VALUES(2,'0003_auction.sql','2026-10-19 00:03:55');
INSERT INTO "d1_migrations" ("id","name","applied_at") VALUES(3,'0002_insights.sql','2026-10-19 00:09:10');
INSERT INTO "d1_migrations" ("id","name","applied_at") VALUES(4,'0004_news.sql','2026-10-19 10:10:32');
INSERT INTO "d1_migrations" ("id","name","applied_at") VALUES(5,'0005_loot.sql','2026-10-22 14:45:13');
INSERT INTO "d1_migrations" ("id","name","applied_at") VALUES(6,'0006_auction_spread.sql','2026-10-24 03:54:25');
INSERT INTO "d1_migrations" ("id","name","applied_at") VALUES(7,'0007_census_staged.sql','2026-10-24 06:14:46');
INSERT INTO "d1_migrations" ("id","name","applied_at") VALUES(8,'0008_bid.sql','2026-10-24 23:15:21');
INSERT INTO "d1_migrations" ("id","name","applied_at") VALUES(9,'0009_bid_people.sql','2026-10-25 03:55:18');
INSERT INTO "d1_migrations" ("id","name","applied_at") VALUES(10,'0010_bid_ugly.sql','2026-10-25 04:09:35');
INSERT INTO "d1_migrations" ("id","name","applied_at") VALUES(11,'0011_pvp.sql','2026-10-26 12:01:22');
INSERT INTO "d1_migrations" ("id","name","applied_at") VALUES(12,'0012_pvp_reports.sql','2026-10-26 12:12:06');
INSERT INTO "d1_migrations" ("id","name","applied_at") VALUES(13,'0013_pvp_faction.sql','2026-10-26 12:43:55');
