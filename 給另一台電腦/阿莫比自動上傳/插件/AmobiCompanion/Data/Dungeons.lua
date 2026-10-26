-- 由 tools/build_companion_data.py 產生，不要手改：副本小卡：進入／建議等級、首領出場順序、記到的掉落（用地圖編號查）
-- 來源：site/public/data/dungeons.json、site/public/data/loot.json（永恆 1.60.1.70532）
local _, ns = ...
ns.DungeonData = {
  version = "1.60.1.70532",
  lootUpdated = nil,
  instances = {
    [249] = {
      name = "奧妮克希亞的巢穴",
      kind = "raid",
      players = 40,
      bosses = {
        {
          id = 1084,
          name = "奧妮克希亞",
        },
      },
      lo = 60,
      hi = 60,
      reset = "每 5 天",
    },
    [409] = {
      name = "熔火之心",
      kind = "raid",
      players = 40,
      bosses = {
        {
          id = 663,
          name = "魯西弗隆",
        },
        {
          id = 664,
          name = "瑪格曼達",
        },
        {
          id = 665,
          name = "基赫納斯",
        },
        {
          id = 666,
          name = "加爾",
        },
        {
          id = 667,
          name = "沙斯拉爾",
        },
        {
          id = 668,
          name = "迦頓男爵",
        },
        {
          id = 669,
          name = "薩弗隆先驅者",
        },
        {
          id = 670,
          name = "焚化者古雷曼格",
        },
        {
          id = 671,
          name = "管理者埃克索圖斯",
        },
        {
          id = 672,
          name = "拉格納羅斯",
        },
      },
      entry = 50,
      lo = 60,
      hi = 60,
      reset = "每週",
    },
    [389] = {
      name = "怒焰裂谷",
      kind = "dungeon",
      players = 5,
      bosses = {
        {
          id = 2732,
          name = "奧格弗林特",
        },
        {
          id = 2733,
          name = "『飢餓者』塔拉加曼",
        },
        {
          id = 2734,
          name = "『塑能師』耶戈什",
        },
        {
          id = 2735,
          name = "巴札蘭",
        },
      },
      entry = 10,
      lo = 13,
      hi = 18,
    },
    [3065] = {
      name = "族長之廳",
      kind = "dungeon",
      players = 5,
      bosses = {
        {
          id = 3493,
          name = "法爾椎‧安威瑪",
        },
        {
          id = 3495,
          name = "英弗努斯",
        },
        {
          id = 3494,
          name = "掠奪者",
        },
        {
          id = 3496,
          name = "杜爾根‧戴格哈默",
        },
      },
      lo = 13,
      hi = 20,
      new = true,
    },
    [2999] = {
      name = "羅德隆廢墟",
      kind = "dungeon",
      players = 5,
      bosses = {
        {
          id = 3353,
          name = "枯萎之牙",
        },
        {
          id = 3357,
          name = "被棄者",
        },
        {
          id = 3355,
          name = "屠夫",
        },
        {
          id = 3354,
          name = "拉斯梅爾",
        },
        {
          id = 3408,
          name = "羅德隆隊長",
        },
        {
          id = 3411,
          name = "邪惡的維多",
        },
        {
          id = 3412,
          name = "布喬克",
        },
      },
      lo = 15,
      hi = 22,
      new = true,
    },
    [43] = {
      name = "哀嚎洞穴",
      kind = "dungeon",
      players = 5,
      bosses = {
        {
          id = 585,
          name = "安娜科德拉",
        },
        {
          id = 586,
          name = "考布萊恩",
        },
        {
          id = 587,
          name = "克雷什",
        },
        {
          id = 588,
          name = "皮薩斯",
        },
        {
          id = 589,
          name = "斯卡姆",
        },
        {
          id = 590,
          name = "瑟芬迪斯",
        },
        {
          id = 591,
          name = "永生的沃爾丹",
        },
        {
          id = 592,
          name = "吞噬者穆坦努斯",
        },
      },
      entry = 10,
      lo = 15,
      hi = 24,
    },
    [36] = {
      name = "死亡礦坑",
      kind = "dungeon",
      players = 5,
      bosses = {
        {
          id = 2741,
          name = "拉克佐",
        },
        {
          id = 2742,
          name = "斯尼德",
        },
        {
          id = 3676,
          name = "礦工強森",
        },
        {
          id = 2743,
          name = "基爾尼格",
        },
        {
          id = 2744,
          name = "綠皮隊長",
        },
        {
          id = 2745,
          name = "重拳先生",
        },
        {
          id = 2746,
          name = "餅乾",
        },
        {
          id = 2747,
          name = "艾德溫‧范克里夫",
        },
      },
      entry = 10,
      lo = 17,
      hi = 26,
    },
    [33] = {
      name = "影牙城堡",
      kind = "dungeon",
      players = 5,
      bosses = {
        {
          id = 2748,
          name = "雷希戈爾",
        },
        {
          id = 2749,
          name = "『屠夫』銳爪",
        },
        {
          id = 2750,
          name = "席瓦萊恩男爵",
        },
        {
          id = 2751,
          name = "指揮官斯普林瓦爾",
        },
        {
          id = 2752,
          name = "『盲眼守衛』奧杜",
        },
        {
          id = 2753,
          name = "『吞噬者』芬魯斯",
        },
        {
          id = 2754,
          name = "狼王南杜斯",
        },
        {
          id = 2755,
          name = "大法師阿魯高",
        },
      },
      entry = 11,
      lo = 20,
      hi = 30,
    },
    [34] = {
      name = "暴風城監獄",
      kind = "dungeon",
      players = 5,
      bosses = {
        {
          id = 2756,
          name = "可怕的塔高爾",
        },
        {
          id = 2757,
          name = "卡姆·深怒",
        },
        {
          id = 2758,
          name = "哈姆霍克",
        },
        {
          id = 2759,
          name = "迪克斯特·瓦德",
        },
        {
          id = 2760,
          name = "巴基爾·斯瑞德",
        },
      },
      entry = 15,
      lo = 24,
      hi = 32,
    },
    [48] = {
      name = "黑澗深淵",
      kind = "dungeon",
      players = 5,
      bosses = {
        {
          id = 2916,
          name = "加摩拉",
        },
        {
          id = 2915,
          name = "薩利維絲女士",
        },
        {
          id = 2914,
          name = "格里哈斯特",
        },
        {
          id = 2913,
          name = "洛古斯·傑特",
        },
        {
          id = 2912,
          name = "老瑟拉吉斯",
        },
        {
          id = 2911,
          name = "暮光領主克爾里斯",
        },
        {
          id = 2910,
          name = "阿庫麥爾",
        },
      },
      entry = 15,
      lo = 24,
      hi = 32,
    },
    [2998] = {
      name = "挖掘場：濕地",
      kind = "dungeon",
      players = 5,
      bosses = {
        {
          id = 3480,
          name = "鹽脊",
        },
        {
          id = 3481,
          name = "蔭牙",
        },
        {
          id = 3644,
          name = "高地之懼",
        },
        {
          id = 3482,
          name = "聖物守護者",
        },
      },
      lo = 26,
      hi = 33,
      new = true,
    },
    [2959] = {
      name = "達拉然城",
      kind = "dungeon",
      players = 5,
      bosses = {
        {
          id = 3298,
          name = "秘法異象",
        },
        {
          id = 3299,
          name = "魔化古樹",
        },
        {
          id = 3300,
          name = "法力吞噬者",
        },
        {
          id = 3301,
          name = "法力元素",
        },
        {
          id = 3302,
          name = "不穩定的哨兵",
        },
        {
          id = 3303,
          name = "大法師之影",
        },
        {
          id = 3310,
          name = "『忽視者』林恩",
        },
        {
          id = 3311,
          name = "『墓地騎士』亞崔希斯",
        },
        {
          id = 3312,
          name = "法力怨靈",
        },
      },
      lo = 28,
      hi = 35,
      new = true,
    },
    [47] = {
      name = "剃刀沼澤",
      kind = "dungeon",
      players = 5,
      bosses = {
        {
          id = 2773,
          name = "魯古格",
        },
        {
          id = 2774,
          name = "阿葛金‧棘咒",
        },
        {
          id = 2775,
          name = "亡語者賈格巴",
        },
        {
          id = 2776,
          name = "拉姆塔斯主宰",
        },
        {
          id = 2777,
          name = "暴怒的阿迦賽羅斯",
        },
        {
          id = 2778,
          name = "卡爾加‧刺肋",
        },
      },
      entry = 25,
      lo = 29,
      hi = 38,
    },
    [90] = {
      name = "諾姆瑞根",
      kind = "dungeon",
      players = 5,
      bosses = {
        {
          id = 2768,
          name = "格魯比斯",
        },
        {
          id = 2769,
          name = "粘性輻射塵",
        },
        {
          id = 2770,
          name = "電刑器6000型",
        },
        {
          id = 2771,
          name = "群體打擊者9-60",
        },
        {
          id = 2772,
          name = "機電師瑟瑪普拉格",
        },
      },
      entry = 19,
      lo = 29,
      hi = 38,
    },
    [189] = {
      name = "血色修道院",
      kind = "dungeon",
      players = 5,
      bosses = {
        {
          id = 444,
          name = "審訊員韋沙斯",
        },
        {
          id = 2779,
          name = "血法師薩爾諾斯",
        },
        {
          id = 446,
          name = "馴犬者洛克希",
        },
        {
          id = 447,
          name = "秘法師杜安",
        },
        {
          id = 448,
          name = "赫洛德",
        },
        {
          id = 449,
          name = "高等審判官法爾班克斯",
        },
        {
          id = 450,
          name = "高等審判官懷特邁恩",
        },
      },
      entry = 20,
      lo = 30,
      hi = 46,
      wings = {
        {
          name = "血色修道院 - 墓地",
          lo = 30,
          hi = 38,
        },
        {
          name = "血色修道院 - 圖書館",
          lo = 33,
          hi = 41,
        },
        {
          name = "血色修道院 - 軍械庫",
          lo = 36,
          hi = 44,
        },
        {
          name = "血色修道院 - 大教堂",
          lo = 38,
          hi = 46,
        },
      },
    },
    [129] = {
      name = "剃刀高地",
      kind = "dungeon",
      players = 5,
      bosses = {
        {
          id = 2780,
          name = "圖特卡什",
        },
        {
          id = 2781,
          name = "腐爛的普雷莫爾",
        },
        {
          id = 2782,
          name = "火眼莫德雷斯",
        },
        {
          id = 2783,
          name = "拉戈斯諾特",
        },
        {
          id = 2784,
          name = "暴食者",
        },
        {
          id = 2785,
          name = "『寒冰使者』亞門納爾",
        },
      },
      entry = 35,
      lo = 37,
      hi = 46,
    },
    [70] = {
      name = "奧達曼",
      kind = "dungeon",
      players = 5,
      bosses = {
        {
          id = 547,
          name = "魯維羅什",
        },
        {
          id = 548,
          name = "失蹤的矮人",
        },
        {
          id = 549,
          name = "艾隆納亞",
        },
        {
          id = 1887,
          name = "黑曜石哨兵",
        },
        {
          id = 551,
          name = "古代的石頭看守者",
        },
        {
          id = 552,
          name = "加加恩·火錘",
        },
        {
          id = 553,
          name = "格瑞姆洛克",
        },
        {
          id = 554,
          name = "阿札達斯",
        },
      },
      entry = 30,
      lo = 41,
      hi = 51,
    },
    [209] = {
      name = "祖爾法拉克",
      kind = "dungeon",
      players = 5,
      bosses = {
        {
          id = 593,
          name = "水占師維蕾薩",
        },
        {
          id = 594,
          name = "加茲瑞拉",
        },
        {
          id = 595,
          name = "安圖蘇爾",
        },
        {
          id = 596,
          name = "殉教者塞卡",
        },
        {
          id = 597,
          name = "巫醫祖穆拉恩",
        },
        {
          id = 598,
          name = "耐克魯姆",
        },
        {
          id = 599,
          name = "暗影祭司塞瑟斯",
        },
        {
          id = 600,
          name = "烏克茲·沙頂",
        },
      },
      entry = 39,
      lo = 44,
      hi = 54,
    },
    [349] = {
      name = "瑪拉頓",
      kind = "dungeon",
      players = 5,
      bosses = {
        {
          id = 422,
          name = "諾克賽恩",
        },
        {
          id = 423,
          name = "銳刺鞭笞者",
        },
        {
          id = 427,
          name = "技工吉茲洛克",
        },
        {
          id = 424,
          name = "維利塔恩領主",
        },
        {
          id = 425,
          name = "被詛咒的塞雷布拉斯",
        },
        {
          id = 426,
          name = "蘭斯利德",
        },
        {
          id = 428,
          name = "洛特格里普",
        },
        {
          id = 429,
          name = "瑟萊德絲公主",
        },
      },
      entry = 25,
      lo = 46,
      hi = 55,
    },
    [109] = {
      name = "沉沒的神廟",
      kind = "dungeon",
      players = 5,
      bosses = {
        {
          id = 3582,
          name = "阿塔拉利恩",
        },
        {
          id = 3583,
          name = "哈卡的化身",
        },
        {
          id = 3584,
          name = "伊蘭尼庫斯之影",
        },
        {
          id = 3585,
          name = "哈札斯",
        },
        {
          id = 3586,
          name = "摩弗拉斯",
        },
        {
          id = 3587,
          name = "編織者",
        },
        {
          id = 3588,
          name = "德姆塞卡爾",
        },
        {
          id = 3589,
          name = "『預言者』迦瑪蘭",
        },
      },
      entry = 45,
      lo = 50,
      hi = 60,
    },
    [230] = {
      name = "黑石深淵",
      kind = "dungeon",
      players = 5,
      bosses = {
        {
          id = 227,
          name = "審訊官格斯塔恩",
        },
        {
          id = 228,
          name = "洛考爾",
        },
        {
          id = 229,
          name = "馴犬者格雷布瑪爾",
        },
        {
          id = 230,
          name = "秩序競技場",
        },
        {
          id = 231,
          name = "控火師羅格雷恩",
        },
        {
          id = 232,
          name = "伊森迪奧斯",
        },
        {
          id = 233,
          name = "典獄官斯迪爾基斯",
        },
        {
          id = 234,
          name = "弗諾斯·達克維爾",
        },
        {
          id = 235,
          name = "貝爾加",
        },
        {
          id = 236,
          name = "安格弗將軍",
        },
        {
          id = 237,
          name = "傀儡統帥阿格曼奇",
        },
        {
          id = 238,
          name = "霍爾雷·黑鬚",
        },
        {
          id = 239,
          name = "法拉克斯",
        },
        {
          id = 240,
          name = "雷布里·斯庫比格特",
        },
        {
          id = 241,
          name = "普拉格",
        },
        {
          id = 2791,
          name = "銀行",
        },
        {
          id = 242,
          name = "弗萊拉斯大使",
        },
        {
          id = 243,
          name = "七賢",
        },
        {
          id = 244,
          name = "瑪格姆斯",
        },
        {
          id = 2789,
          name = "茉艾拉·銅鬚公主",
        },
        {
          id = 2790,
          name = "達格蘭‧索瑞森大帝",
        },
      },
      entry = 42,
      lo = 52,
      hi = 60,
    },
    [429] = {
      name = "厄運之槌",
      kind = "dungeon",
      players = 5,
      bosses = {
        {
          id = 343,
          name = "瑟雷姆·刺蹄",
        },
        {
          id = 344,
          name = "海多斯博恩",
        },
        {
          id = 345,
          name = "蕾瑟塔蒂絲",
        },
        {
          id = 2792,
          name = "普希林",
        },
        {
          id = 346,
          name = "奧茲恩",
        },
        {
          id = 350,
          name = "特迪斯·扭木",
        },
        {
          id = 347,
          name = "伊琳娜·鴉橡",
        },
        {
          id = 348,
          name = "博學者卡雷迪斯",
        },
        {
          id = 349,
          name = "伊莫塔爾",
        },
        {
          id = 361,
          name = "托塞德林王子",
        },
        {
          id = 362,
          name = "衛兵摩爾達",
        },
        {
          id = 363,
          name = "踐踏者克雷格",
        },
        {
          id = 364,
          name = "衛兵芬古斯",
        },
        {
          id = 365,
          name = "衛兵斯里基克",
        },
        {
          id = 366,
          name = "克羅卡斯",
        },
        {
          id = 367,
          name = "觀察者克魯什",
        },
        {
          id = 368,
          name = "戈多克大王",
        },
        {
          id = 2793,
          name = "赫爾努拉斯領主",
        },
        {
          id = 2794,
          name = "蘇斯",
        },
      },
      entry = 31,
      lo = 54,
      hi = 60,
      wings = {
        {
          name = "厄運之槌（東側）",
          lo = 54,
          hi = 60,
        },
        {
          name = "厄運之槌（西側）",
          lo = 56,
          hi = 60,
        },
        {
          name = "厄運之槌（北側）",
          lo = 56,
          hi = 60,
        },
      },
    },
    [229] = {
      name = "黑石塔",
      kind = "dungeon",
      players = 10,
      bosses = {
        {
          id = 267,
          name = "歐莫克大王",
        },
        {
          id = 268,
          name = "暗影獵手沃許加斯",
        },
        {
          id = 269,
          name = "指揮官沃恩",
        },
        {
          id = 270,
          name = "煙網蛛后",
        },
        {
          id = 271,
          name = "烏洛克",
        },
        {
          id = 272,
          name = "軍需官茲格雷斯",
        },
        {
          id = 274,
          name = "哈雷肯",
        },
        {
          id = 273,
          name = "奴役者基茲盧爾",
        },
        {
          id = 275,
          name = "維姆薩拉克主宰",
        },
        {
          id = 3062,
          name = "烈焰衛士艾博希爾",
        },
        {
          id = 3063,
          name = "大酋長雷德·黑手",
        },
        {
          id = 3068,
          name = "比斯巨獸",
        },
        {
          id = 3069,
          name = "達基薩斯將軍",
        },
        {
          id = 3070,
          name = "瓦薩拉克領主",
        },
      },
      entry = 48,
      lo = 55,
      hi = 60,
      wings = {
        {
          name = "黑石塔下層",
          lo = 55,
          hi = 60,
        },
        {
          name = "黑石塔上層",
          lo = 59,
          hi = 60,
        },
      },
    },
    [289] = {
      name = "通靈學院",
      kind = "dungeon",
      players = 5,
      bosses = {
        {
          id = 2805,
          name = "基爾圖諾斯",
        },
        {
          id = 2804,
          name = "詹迪斯·巴羅夫",
        },
        {
          id = 2811,
          name = "血骨傀儡",
        },
        {
          id = 2809,
          name = "馬杜克·布萊克波爾",
        },
        {
          id = 2813,
          name = "維克圖斯",
        },
        {
          id = 3055,
          name = "科爾莫克",
        },
        {
          id = 2810,
          name = "萊斯‧霜語",
        },
        {
          id = 2803,
          name = "講師瑪麗希亞",
        },
        {
          id = 2802,
          name = "瑟爾林·卡斯迪諾夫教授",
        },
        {
          id = 2808,
          name = "博學者普克爾特",
        },
        {
          id = 2812,
          name = "拉文尼亞",
        },
        {
          id = 2807,
          name = "阿萊克斯·巴羅夫領主",
        },
        {
          id = 2806,
          name = "伊露希亞·巴羅夫女士",
        },
        {
          id = 2801,
          name = "黑暗院長加丁",
        },
      },
      entry = 33,
      lo = 58,
      hi = 60,
    },
    [329] = {
      name = "斯坦索姆",
      kind = "dungeon",
      players = 5,
      bosses = {
        {
          id = 473,
          name = "弗雷斯特恩",
        },
        {
          id = 474,
          name = "悲慘的提米",
        },
        {
          id = 476,
          name = "狂熱的瑪洛爾",
        },
        {
          id = 475,
          name = "砲手威利",
        },
        {
          id = 477,
          name = "檔案管理員加爾福特",
        },
        {
          id = 478,
          name = "巴納札爾",
        },
        {
          id = 472,
          name = "不可寬恕者",
        },
        {
          id = 479,
          name = "安娜絲塔麗男爵夫人",
        },
        {
          id = 480,
          name = "奈幽布恩坎",
        },
        {
          id = 481,
          name = "蒼白的瑪勒基",
        },
        {
          id = 482,
          name = "巴瑟拉斯鎮長",
        },
        {
          id = 483,
          name = "吞嚥者拉姆斯登",
        },
        {
          id = 484,
          name = "瑞文戴爾男爵",
        },
        {
          id = 2795,
          name = "黑衣守衛劍類鍛造師",
        },
        {
          id = 2796,
          name = "紅衣鑄錘師",
        },
        {
          id = 2797,
          name = "艾茲拉‧格里姆",
        },
        {
          id = 2798,
          name = "郵政局長瑪羅恩",
        },
        {
          id = 2799,
          name = "斯庫爾",
        },
        {
          id = 2800,
          name = "石脊",
        },
      },
      entry = 37,
      lo = 58,
      hi = 60,
      wings = {
        {
          name = "斯坦索姆（主門）",
          lo = 58,
          hi = 60,
        },
        {
          name = "斯坦索姆（僕從入口）",
          lo = 58,
          hi = 60,
        },
      },
    },
  },
}
