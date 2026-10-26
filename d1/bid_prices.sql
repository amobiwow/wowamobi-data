PRAGMA defer_foreign_keys=TRUE;
CREATE TABLE bid_prices (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id  INTEGER NOT NULL,
  price    INTEGER NOT NULL,                -- 金
  capped   INTEGER NOT NULL DEFAULT 0,      -- 1＝標到上限（擲骰決定）
  at       INTEGER NOT NULL
);
INSERT INTO "bid_prices" ("id","item_id","price","capped","at") VALUES(1,17073,23,0,1792886970);
INSERT INTO "bid_prices" ("id","item_id","price","capped","at") VALUES(2,17691,1,1,1792889078);
INSERT INTO "bid_prices" ("id","item_id","price","capped","at") VALUES(3,17073,23,0,1792896606);
INSERT INTO "bid_prices" ("id","item_id","price","capped","at") VALUES(4,10360,12,1,1792897033);
INSERT INTO "bid_prices" ("id","item_id","price","capped","at") VALUES(5,19017,1,1,1792927348);
INSERT INTO "bid_prices" ("id","item_id","price","capped","at") VALUES(6,9488,1,0,1792928141);
INSERT INTO "bid_prices" ("id","item_id","price","capped","at") VALUES(7,288915,23,0,1792932429);
INSERT INTO "bid_prices" ("id","item_id","price","capped","at") VALUES(8,18814,880,0,1792932794);
INSERT INTO "bid_prices" ("id","item_id","price","capped","at") VALUES(9,12584,10,0,1792936556);
INSERT INTO "bid_prices" ("id","item_id","price","capped","at") VALUES(10,21176,1,1,1792998380);
INSERT INTO "bid_prices" ("id","item_id","price","capped","at") VALUES(11,279321,305,0,1792998602);
INSERT INTO "bid_prices" ("id","item_id","price","capped","at") VALUES(12,13090,100,0,1792999284);
INSERT INTO "bid_prices" ("id","item_id","price","capped","at") VALUES(13,6728,2,0,1792999348);
INSERT INTO "bid_prices" ("id","item_id","price","capped","at") VALUES(14,254049,500,0,1792999423);
INSERT INTO "bid_prices" ("id","item_id","price","capped","at") VALUES(15,6473,50,1,1792999656);
