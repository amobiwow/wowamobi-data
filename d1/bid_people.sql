PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE bid_people (
  nkey      TEXT    PRIMARY KEY,
  name      TEXT    NOT NULL,
  cls       TEXT,
  runs      INTEGER NOT NULL DEFAULT 0,
  bought    INTEGER NOT NULL DEFAULT 0,
  spent     INTEGER NOT NULL DEFAULT 0,      -- 金
  got       INTEGER NOT NULL DEFAULT 0,      -- 銅（分潤，含零頭）
  first_at  INTEGER,
  last_at   INTEGER
, ugly INTEGER NOT NULL DEFAULT 0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('谷 阿莫','谷 阿莫','WARRIOR',1,0,0,60000,1792918674,1792918674,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('王 大明','王 大明','HUNTER',1,1,12,60000,1792918674,1792918674,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('阿莫 谷','阿莫 谷','PRIEST',2,4,92,920000,1792927916,1792928991,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('測試 宇夜','測試 宇夜','PALADIN',1,2,903,4515000,1792932910,1792932910,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('測試 暗號','測試 暗號','MAGE',1,0,0,4515000,1792932910,1792932910,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('ffe ee','ffe ee','WARRIOR',1,1,10,41800,1792936673,1792936673,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('ffe 323','ffe 323','HUNTER',1,0,0,31600,1792936673,1792936673,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('ffee 323','ffee 323','ROGUE',1,0,0,26600,1792936673,1792936673,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('阿 莫','阿 莫','PALADIN',1,0,0,0,1792939984,1792939984,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('大明 小','大明 小','ROGUE',1,0,0,0,1792939984,1792939984,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('補 血','補 血','SHAMAN',1,0,0,0,1792939984,1792939984,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('a','A','DRUID',1,4,602,2849800,1792999798,1792999798,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('b','B','PALADIN',1,0,0,1340800,1792999798,1792999798,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('c','C','SHAMAN',1,0,0,1340800,1792999798,1792999798,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('d','D','PRIEST',1,0,0,1843300,1792999798,1792999798,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('e','E','HUNTER',1,1,500,1340800,1792999798,1792999798,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('f','F','WARRIOR',1,0,0,1843300,1792999798,1792999798,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('g','G','MAGE',1,0,0,1340800,1792999798,1792999798,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('h','H','WARLOCK',1,0,0,1340800,1792999798,1792999798,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('aa','AA','HUNTER',1,4,407,1849600,1792999798,1792999798,1);
