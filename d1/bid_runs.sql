PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE bid_runs (
  code       TEXT    NOT NULL,
  closed_at  INTEGER NOT NULL,
  dungeon    TEXT,
  members    INTEGER,
  sales      INTEGER,
  total      INTEGER,
  PRIMARY KEY (code, closed_at)
);
INSERT INTO "bid_runs" ("code","closed_at","dungeon","members","sales","total") VALUES('2S42',1792918674,'黑翼之巢',2,1,12);
INSERT INTO "bid_runs" ("code","closed_at","dungeon","members","sales","total") VALUES('X76U',1792927916,'熔火之心',1,2,41);
INSERT INTO "bid_runs" ("code","closed_at","dungeon","members","sales","total") VALUES('3AU4',1792928991,'黑澗深淵',1,2,51);
INSERT INTO "bid_runs" ("code","closed_at","dungeon","members","sales","total") VALUES('734Q',1792932910,'熔火之心',2,2,903);
INSERT INTO "bid_runs" ("code","closed_at","dungeon","members","sales","total") VALUES('JXT5',1792936673,'黑翼之巢',3,1,10);
INSERT INTO "bid_runs" ("code","closed_at","dungeon","members","sales","total") VALUES('JKVX',1792939984,'熔火之心',3,0,0);
INSERT INTO "bid_runs" ("code","closed_at","dungeon","members","sales","total") VALUES('VU32',1792999798,'黑石深淵',9,9,1509);
