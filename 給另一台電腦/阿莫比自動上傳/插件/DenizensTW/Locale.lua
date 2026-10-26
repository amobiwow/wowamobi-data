--[[ Denizens TW - locale --------------------------------------------------

Only the lines this fork adds or rewords are translated. Every key is the
English text itself, so a missing translation falls back to readable English
instead of nil.
--]]

local ADDON, ns = ...

local zhTW = {
    -- startup / status
    ["v%s loaded. |cffffd100/dz scan|r starts a census, |cffffd100/dz help|r lists commands."] =
        "v%s 已載入。|cffffd100/dz scan|r 開始普查，|cffffd100/dz help|r 查看所有指令。",
    ["v%s loaded - %s"] = "v%s 已載入 - %s",
    ["%d problem(s) - /dz debug"] = "%d 個問題 - 輸入 /dz debug 查看",
    ["out of date - built for %d, client is %d"] = "版本較舊 - 以 %d 製作，目前客戶端是 %d",
    ["click mode (this client needs a click for every /who)"] = "點擊模式 (這個客戶端每次 /who 都需要真人點擊)",

    -- conflict with the original addon
    ["The original Denizens is also enabled. Two addons sending /who at once throttle each other, so Denizens TW will not scan. Untick one of them in the AddOns list at character select."] =
        "偵測到原版 Denizens 也啟用中。兩個插件同時送 /who 會互相拖慢，所以 Denizens TW 暫停掃描。請在角色選擇畫面的「插件」清單取消勾選其中一個。",

    -- hardware gate
    ["This client only sends /who on a real click or key press. Switched to click mode: click in the game world, move, jump or use an ability (or press your Denizens TW key binding) - each one sends the next query. If Blizzard showed an \"AddOn blocked\" box, choose Ignore."] =
        "這個客戶端只允許「真人操作」送出 /who，已切換成點擊模式：在遊戲世界點一下滑鼠、走路、跳或放技能（或按你設定的 Denizens TW 快捷鍵），每一下就送出下一筆查詢。如果剛才跳出「插件被禁止執行」的視窗，請按「忽略」。",
    ["Click mode is on (remembered from an earlier session on this client build). /dz mode auto tests automatic sending again."] =
        "已啟用點擊模式 (上次在這個客戶端版本偵測到需要點擊)。輸入 /dz mode auto 可以重新測試自動送出。",
    ["Click mode: %d queries left. Click the game world, move or use an ability to send the next one."] =
        "點擊模式：還有 %d 筆查詢。點一下遊戲畫面、走路或放技能，就會送出下一筆。",
    ["Moving, jumping and abilities send queries in click mode: %s"] = "點擊模式下，走路、跳和放技能也會送出查詢：%s",
    ["Mode set to automatic - the next query tells whether this client allows it."] =
        "已切換為自動模式 - 下一筆查詢就會知道這個客戶端是否允許。",
    ["Mode set to click - every query waits for a click or key press."] = "已切換為點擊模式 - 每筆查詢都會等你點擊、走路或放技能。",
    ["Tip: drag the Find Group window by its title bar to move it out of the way (not in combat). Its spot is remembered; /dz whopos reset puts it back."] =
        "小提示：「尋求組隊」視窗可以拖標題列，移到不擋畫面的地方（戰鬥中不能拖），位置會記住。輸入 /dz whopos reset 可以恢復原位。",
    ["The Find Group window goes back to its usual spot next time it opens."] = "「尋求組隊」視窗下次打開時，會回到原本的位置。",
    ["Find Group window: drag its title bar to move it (not in combat). Spot: %s."] = "「尋求組隊」視窗：拖標題列就能移動（戰鬥中不能拖）。位置：%s。",
    ["remembered"] = "已記住",
    ["not moved yet"] = "還沒移動過",
    ["The Find Group window has not loaded yet; it can be dragged as soon as it first appears."] = "「尋求組隊」視窗還沒載入；它一出現就能拖。",
    ["In combat - the Find Group window can be dragged once combat ends."] = "戰鬥中，離開戰鬥後就能拖「尋求組隊」視窗。",
    ["Dragging the Find Group window failed to set up: %s - please send a screenshot."] = "「尋求組隊」視窗的拖曳功能沒裝好：%s。請截圖給我。",

    -- scans
    ["A scan is already running (%d queued). /dz stop cancels it."] = "已經有掃描在進行中 (排隊 %d 筆)。輸入 /dz stop 可以中止。",
    ["Census scan started (levels %d-%d%s)."] = "開始普查 (等級 %d-%d%s)。",
    [", filter: %s"] = "，條件：%s",
    ["Census complete: %d found (%d new), %d queries, %s."] = "普查完成：找到 %d 人 (新 %d 人)，送出 %d 次查詢，耗時 %s。",
    ["Still capped after every split: %s - more players exist there than one query can show."] =
        "切到最細仍然超過 50 人：%s - 這些組合實際人數比一次查詢能顯示的多。",
    ["%d queries got no reply and were given up."] = "%d 筆查詢一直沒有回應，已放棄。",
    ["Scan cancelled - %d queries dropped, %d players kept."] = "已中止掃描 - 丟棄 %d 筆查詢，保留 %d 人。",
    ["No scan running."] = "目前沒有掃描在進行。",
    ["%dm %02ds"] = "%d 分 %02d 秒",

    -- auto passes
    ["Auto census ON: a full pass every %d minutes while you are playing (paused when AFK or in combat)."] =
        "自動普查已開啟：你在遊戲中時每 %d 分鐘完整掃一輪 (暫離或戰鬥中自動暫停)。",
    ["Auto census OFF."] = "自動普查已關閉。",
    ["Auto census ON: a pass every %d minutes while you are playing. In click mode its queries go out with your clicks, movement and abilities."] =
        "自動普查已開啟：你在遊戲中時每 %d 分鐘排一輪。點擊模式下，查詢會跟著你的點擊、走路和技能送出。",
    ["Next auto pass in %d min."] = "下一輪自動普查：%d 分鐘後。",
    ["Continuous census ON: the next pass starts 10 s after one finishes. In click mode each query still goes out with your own clicks, movement and abilities. Paused when AFK or in combat; /dz auto off stops it."] =
        "連續普查已開啟：一輪做完 10 秒後自動開始下一輪，不用再打指令。點擊模式下每一筆查詢還是要你自己點一下、走路或放技能才會送出。暫離或戰鬥中暫停；輸入 /dz auto off 關閉。",
    ["Continuous census ON: the next pass starts 10 s after one finishes, while you are playing (paused when AFK or in combat). /dz auto off stops it."] =
        "連續普查已開啟：你在遊戲中時，一輪做完 10 秒後自動開始下一輪 (暫離或戰鬥中暫停)。輸入 /dz auto off 關閉。",
    ["auto census: on (back to back)"] = "自動普查：開啟 (連續，一輪做完馬上下一輪)",

    -- census report
    ["active (seen in 7 days): |cff66ff66%d|r"] = "7 天內看到 (活躍)：|cff66ff66%d|r",
    ["known ever (upper bound, includes deleted): %d"] = "累計看過 (上限值，含已刪除角色)：%d",
    ["guilds seen: %d   in a guild: %d%%"] = "看過的公會：%d   有公會的比例：%d%%",
    ["highest level seen: %d"] = "看過最高等級：%d",
    ["levels"] = "等級",
    ["top guilds:"] = "人數最多的公會：",
    ["last scan: %s ago, %d found, %d new, %d queries"] = "上一輪普查：%s 前，找到 %d 人，新 %d 人，%d 次查詢",
    ["Census cleared for this realm and faction."] = "已清空這個伺服器與陣營的普查資料。",
    ["This deletes every saved character for this realm and faction. Type |cffffd100/dz wipe confirm|r to do it."] =
        "這會刪除這個伺服器與陣營已存的所有角色。確定的話請輸入 |cffffd100/dz wipe confirm|r。",

    -- status
    ["mode: %s   queue: %d   gap: %.1fs   sent this session: %d   no reply: %d"] =
        "模式：%s   排隊：%d   間隔：%.1f 秒   本次登入已送出：%d   沒有回應：%d",
    ["automatic"] = "自動",
    ["click"] = "點擊",
    ["server said too fast: %d   replies that were not ours: %d"] = "伺服器嫌太快：%d 次   對不上的回覆：%d 筆",
    ["Moving and abilities cannot carry a /who on this client (the game refused it), so only clicks in the game world send queries now."] =
        "走路和技能帶出的 /who 一直被遊戲擋下，這次登入改成只用點擊遊戲畫面送出查詢。",
    ["This client refuses /who during combat, so queries wait until combat is over."] =
        "戰鬥中送出的 /who 一直被遊戲擋下，這次登入改成戰鬥結束再送。",
    ["Even a click in the game world could not send this /who. Please type /dz debug and send a screenshot."] =
        "連點擊遊戲畫面都送不出這筆 /who。請輸入 /dz debug 截圖給我。",
    ["turned off after the game refused them: %s"] = "被遊戲擋下、暫時不用：%s",
    ["moving and abilities"] = "走路和技能",
    ["combat"] = "戰鬥中",
    ["clicks"] = "點擊遊戲畫面",
    ["scan in progress: %d sent, %d waiting, %d found so far"] = "掃描進行中：已送出 %d，等待中 %d，目前找到 %d 人",
    ["auto census: on (every %d min)"] = "自動普查：開啟 (每 %d 分鐘)",
    ["auto census: off"] = "自動普查：關閉",
    ["client: %s %s (interface %s), locale %s"] = "客戶端：%s %s (介面版本 %s)，語言 %s",

    -- UI
    ["Name"] = "名字", ["Lvl"] = "等級", ["Class"] = "職業", ["Race"] = "種族",
    ["Zone"] = "區域", ["Guild"] = "公會", ["Level"] = "等級", ["Any"] = "不限",
    ["Query sent"] = "送出的查詢", ["Search"] = "查詢", ["Deep scan"] = "深度掃描",
    ["Filter results"] = "篩選結果", ["Census report"] = "普查報告", ["Full census"] = "完整普查",
    ["Cancel (%d)"] = "中止 (%d)", ["Continue (%d)"] = "繼續 (%d)",
    ["%d shown"] = "顯示 %d 人", [" of %d"] = " / 共 %d 人",
    ["(capped - try Deep scan)"] = "(已達 50 人上限 - 請用深度掃描)",
    ["[%d queued]"] = "[排隊 %d 筆]",
    ["roster: |cff66ff66%d|r active (7d)   %d known ever   %d guilds"] =
        "名冊：7 天內 |cff66ff66%d|r 人   累計 %d 人   %d 個公會",
    ["Send next /who (click mode)"] = "送出下一筆 /who (點擊模式)",
    ["in-pane takeover %s - /reload to apply."] = "嵌入暴雪 /who 視窗：%s - 輸入 /reload 生效。",
    ["ENABLED"] = "開啟", ["DISABLED"] = "關閉",
    ["the standalone window (/dz) touches none of Blizzard's frames."] = "獨立視窗 (/dz) 不會動到任何暴雪介面。",
    ["live debug output %s"] = "即時除錯訊息：%s",
    ["ON"] = "開", ["OFF"] = "關",
}

local L = setmetatable({}, { __index = function(_, key) return key end })
local locale = GetLocale and GetLocale() or "enUS"
if locale == "zhTW" or locale == "zhCN" then
    for key, text in pairs(zhTW) do L[key] = text end
end
ns.L = L
ns.locale = locale

-- Key binding labels (Bindings.xml). Globals by WoW's own convention.
BINDING_HEADER_DENIZENSTW = "Denizens TW"
BINDING_NAME_DENIZENSTW_STEP = L["Send next /who (click mode)"]
