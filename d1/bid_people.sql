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
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('阿莫 谷','阿莫 谷','WARRIOR',10,9,1888,14145900,1792927916,1793561505,0);
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
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('1 1','1 1','PALADIN',2,1,12,120000,1793534120,1794232612,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('11 阿莫','11 阿莫','MAGE',1,0,0,0,1793534253,1793534253,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('阿莫 阿','阿莫 阿','WARRIOR',1,0,0,0,1793551785,1793551785,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('大明 王','大明 王','WARRIOR',4,4,558,3297000,1793551785,1793559552,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('小 充','小 充','HUNTER',1,0,0,0,1793551785,1793551785,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('隊長 大','隊長 大','HUNTER',1,0,0,0,1793552128,1793552128,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('會計 阿','會計 阿','WARRIOR',1,0,0,0,1793552128,1793552128,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('戰士 王','戰士 王','ROGUE',1,2,68,2604000,1793552513,1793552513,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('戰士2 王','戰士2 王','ROGUE',1,0,0,2604000,1793552513,1793552513,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('阿莫 谷ˊ','阿莫 谷ˊ','ROGUE',1,0,0,0,1793554298,1793554298,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('威 利','威 利','WARRIOR',1,1,2553,3839700,1793561505,1793561505,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('novel santos','Novel Santos','WARRIOR',1,0,0,2117400,1793561505,1793561505,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('luca','Luca','PALADIN',1,0,0,2117400,1793561505,1793561505,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('牛肉 大神','牛肉 大神','PALADIN',1,0,0,3005400,1793561505,1793561505,2);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('宇 夜','宇 夜','PALADIN',1,0,0,2117400,1793561505,1793561505,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('歪踢 安達哥','歪踢 安達哥','ROGUE',1,0,0,2117400,1793561505,1793561505,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('a bcd','A Bcd','ROGUE',1,0,0,2117400,1793561505,1793561505,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('但 是','但 是','DRUID',1,0,0,2117400,1793561505,1793561505,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('香魚','香魚','PRIEST',1,0,0,2117400,1793561505,1793561505,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('kevin','Kevin','PRIEST',1,0,0,2117400,1793561505,1793561505,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('武君','武君','PRIEST',1,0,0,2117400,1793561505,1793561505,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('小可愛 檸檬','小可愛 檸檬','PRIEST',1,0,0,2117400,1793561505,1793561505,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('6 6','6 6','WARRIOR',1,0,0,0,1793585168,1793585168,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('qq qq','QQ QQ','DRUID',1,0,0,0,1793585168,1793585168,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('陳 勝','陳 勝','SHAMAN',1,0,0,0,1793588881,1793588881,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('洋洋薯片 周董','洋洋薯片 周董','SHAMAN',1,0,0,353300,1793601389,1793601389,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('義父 教父','義父 教父','MAGE',1,0,0,229700,1793601389,1793601389,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('23 23','23 23','PALADIN',1,1,40,198400,1793601389,1793601389,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('24 23','24 23','WARRIOR',1,1,35,229300,1793601389,1793601389,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('25 23','25 23','PRIEST',1,2,49,229300,1793601389,1793601389,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('123 456','123 456','WARRIOR',1,0,0,0,1793608647,1793608647,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('3211 4567','3211 4567','WARRIOR',1,0,0,0,1793622037,1793622037,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('歐洲人 大衛','歐洲人 大衛','SHAMAN',1,0,0,0,1793766024,1793766024,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('11 11','11 11','WARRIOR',1,0,0,0,1793777312,1793777312,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('胖子 靈活','胖子 靈活','WARRIOR',1,0,0,0,1794045635,1794045635,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('肥隆 不想上班','肥隆 不想上班','MAGE',1,0,0,0,1794049023,1794049023,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('suusu sha','Suusu Sha','SHAMAN',1,0,0,0,1794316943,1794316943,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('suusu suu','Suusu suu','MAGE',1,0,0,0,1794316943,1794316943,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('英京 塚亣','英京 塚亣','PALADIN',1,0,0,0,1794348589,1794348589,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('菲比啾比 菲比','菲比啾比 菲比','HUNTER',2,0,0,7500000,1794374444,1794374945,0);
INSERT INTO "bid_people" ("nkey","name","cls","runs","bought","spent","got","first_at","last_at","ugly") VALUES('姑姑嘎嘎 估嘎','姑姑嘎嘎 估嘎','DRUID',2,2,1500,7500000,1794374444,1794374945,0);
