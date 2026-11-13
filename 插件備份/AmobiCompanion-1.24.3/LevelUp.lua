-- 阿莫比小幫手：升級公告（1.15.0，老闆 11/6；1.15.1 加網址）
--   老闆在公會頻道看到別人的插件說「到 30 級了，公會裡並列第 1，聖騎士裡並列第 1！1 到 30 級遊戲時長 1 天 3 小時 50 分」，
--   問為什麼別人能輕易排出等級名次 → 那是公會裡的名次（遊戲本來就給插件公會名單上每個人的等級、職業），「要，加進小幫手」。
--
-- 升到 10、20、30……級（可以改成每 5 級、每一級）時，在公會頻道說一句：
--   [阿莫比小幫手 wowamobi.com] 升到 30 級了！公會裡並列第 1 名、戰士裡第 2 名。1 到 30 級遊戲時間 1 天 3 小時 50 分
--   開頭括號加網址（1.15.1，老闆 11/7：別人的插件「根本就是在打廣告」→「要，加網址」）；不能用半形「|」（聊天的跳脫字元）
-- 名次：公會名單上比你高級的人數＋1，有人跟你一樣等級就寫「並列」；職業的名次只比同職業的人。
--   名單用 C_Club（AmobiGuild 讀公會名單同一個作法，開服驗證過讀得到全部成員）；離線的人是他最後一次上線的等級。
-- 遊戲時間：遊戲的 /played（RequestTimePlayed → TIME_PLAYED_MSG），聊天框會照常出現遊戲時間那兩行。
-- 原則：
--   * 預設開（老闆要的，像別人的插件一樣）；可以關、可以改多久說一次；方案和全部開／全部關不動它（發話的事玩家自己決定）
--   * 只在公會頻道說，不在公會就不說；只有升級的那一刻說一次（不重複、不補說以前的等級）
--   * 戰鬥中、首領戰、聊天限制時不說，等解除再說（10 分鐘內還不行就算了）
--   * 這是小幫手唯一會替玩家發話的地方（C_ChatInfo.SendChatMessage，只有 GUILD）

local _, ns = ...
local L = {}
ns.LevelUp = L

L.PREFIX = "[阿莫比小幫手 wowamobi.com]"
local WAIT = 3          -- 秒：等公會名單、遊戲時間回來
local RETRY = 10        -- 秒：現在不能說（戰鬥中、首領戰……）多久再試
local GIVE_UP = 600     -- 秒：10 分鐘還不能說就算了
L.EVERY = { 10, 5, 1 }  -- 多久說一次（設定 levelEvery）

local pending, scheduled

local function S() return ns.db.settings end

function L.Every()
  local e = tonumber(S().levelEvery)
  for _, v in ipairs(L.EVERY) do
    if v == e then return e end
  end
  return 10
end

-- 這一級要不要說
function L.Due(level)
  if type(level) ~= "number" or level < 2 then return false end
  return level % L.Every() == 0
end

-- 聊天限制（首領戰、挑戰模式時遊戲不讓插件說話，公會名單也會變秘密值）
function L.Lockdown()
  local on = ns.Call(C_ChatInfo, "InChatMessagingLockdown")
  return on == true
end

-- 公會名單：自己以外每個人的 { level, class }；讀不到回傳 nil
function L.Roster()
  if not (IsInGuild and IsInGuild()) then return nil end
  local clubId = ns.Call(C_Club, "GetGuildClubId")
  if clubId == nil or ns.Secret(clubId) then return nil end
  local ids = ns.Call(C_Club, "GetClubMembers", clubId)
  if type(ids) ~= "table" or ns.Secret(ids) then return nil end
  local me = UnitGUID("player")
  local out = {}
  for _, mid in ipairs(ids) do
    local info = ns.Call(C_Club, "GetMemberInfo", clubId, mid)
    if type(info) == "table" and not ns.Secret(info) and info.isSelf ~= true
       and not (me and info.guid ~= nil and not ns.Secret(info.guid) and info.guid == me) then
      local lv, cls = info.level, info.classID
      if type(lv) == "number" and not ns.Secret(lv) then
        out[#out + 1] = { level = lv, class = (type(cls) == "number" and not ns.Secret(cls)) and cls or nil }
      end
    end
  end
  return out
end

-- 名次：比你高級的人數＋1；有人一樣等級就是並列
function L.Rank(members, level, classID)
  local above, tie, cAbove, cTie = 0, false, 0, false
  for _, m in ipairs(members) do
    if m.level > level then above = above + 1 elseif m.level == level then tie = true end
    if classID and m.class == classID then
      if m.level > level then cAbove = cAbove + 1 elseif m.level == level then cTie = true end
    end
  end
  return above + 1, tie, cAbove + 1, cTie
end

-- 秒數 → 「1 天 3 小時 50 分」
function L.Duration(sec)
  sec = math.floor(tonumber(sec) or 0)
  local d, h, m = math.floor(sec / 86400), math.floor(sec % 86400 / 3600), math.floor(sec % 3600 / 60)
  if d > 0 then return ("%d 天 %d 小時 %d 分"):format(d, h, m) end
  if h > 0 then return ("%d 小時 %d 分"):format(h, m) end
  return ("%d 分"):format(m)
end

-- 要說的那句；公會名單讀不到回傳 nil
function L.Message(level, played)
  local members = L.Roster()
  if not members then return nil end
  local className, _, classID = UnitClass("player")
  if ns.Secret(classID) or type(classID) ~= "number" then classID = nil end
  local rank, tie, cRank, cTie = L.Rank(members, level, classID)
  local text = ("%s 升到 %d 級了！公會裡%s第 %d 名"):format(L.PREFIX, level, tie and "並列" or "", rank)
  if classID and type(className) == "string" and not ns.Secret(className) and className ~= "" then
    text = text .. ("、%s裡%s第 %d 名"):format(className, cTie and "並列" or "", cRank)
  end
  text = text .. "。"
  if type(played) == "number" and played > 0 then
    text = text .. ("1 到 %d 級遊戲時間 %s"):format(level, L.Duration(played))
  end
  return text
end

local function send(text)
  local fn = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
  if type(fn) ~= "function" then return false end
  return pcall(fn, text, "GUILD")
end

local function later(sec)
  if scheduled then return end
  scheduled = true
  C_Timer.After(sec, function()
    scheduled = false
    ns.Try("levelup", L.Flush)
  end)
end

-- 公會名單、遊戲時間應該回來了：組好那句話說出去（試一下的只印給自己看）
function L.Flush()
  local p = pending
  if not p then return end
  if GetTime() - p.at > GIVE_UP then pending = nil; return end
  if ns.Restricted() or L.Lockdown() then return later(RETRY) end
  local text = L.Message(p.level, p.played)
  pending = nil
  if p.test then
    if text then
      ns.Print("試一下（只有你看得到）：" .. text)
    else
      ns.Print("這隻角色不在公會（或公會名單還沒讀到），升級時不會說。")
    end
    ns.UI.Refresh("levelup")
    return
  end
  if not text then return end
  if send(text) then
    S().levelLast = { level = p.level, at = time() }
  end
  ns.UI.Refresh("levelup")
end

local function start(level, test)
  pending = { level = level, at = GetTime(), test = test }
  ns.Call(C_GuildInfo, "GuildRoster")   -- 請伺服器更新公會名單（只讀名單；邀請插件送不了，見 Recruit.lua）
  if type(RequestTimePlayed) == "function" then pcall(RequestTimePlayed) end
  later(WAIT)
end

function L.OnLevel(level)
  if not S().levelAnnounce then return end
  if type(level) ~= "number" or ns.Secret(level) then level = UnitLevel("player") end
  if not L.Due(level) then return end
  if not (IsInGuild and IsInGuild()) then return end
  start(level, false)
end

-- 「試一下」：用現在的等級算一次，只印在自己的聊天框
function L.Test()
  start(UnitLevel("player"), true)
end

function L.OnPlayed(total)
  if pending and type(total) == "number" and not ns.Secret(total) then pending.played = total end
end

function L.Init()
  ns.On("PLAYER_LEVEL_UP", function(level) L.OnLevel(level) end)
  ns.On("TIME_PLAYED_MSG", function(total) L.OnPlayed(total) end)
end
ns.Register(L)

-- ---------------------------------------------------------------------------- 分頁
local EVERY_TEXT = { [10] = "每 10 級", [5] = "每 5 級", [1] = "每一級" }

local function buildTab(p)
  local tip = ns.UI.Text(p, "GameFontHighlightSmall",
    "升級的時候，自動在公會頻道說你升到幾級、在公會裡排第幾名、同職業排第幾名，還有花了多少遊戲時間。", 430)
  tip:SetPoint("TOPLEFT", 0, 0)
  local example = ns.UI.Text(p, "GameFontDisableSmall",
    "例如：" .. L.PREFIX .. " 升到 30 級了！公會裡並列第 1 名、戰士裡第 2 名。1 到 30 級遊戲時間 1 天 3 小時 50 分", 430)
  example:SetPoint("TOPLEFT", 0, -36)
  p.check = ns.UI.Check(p, "升級時在公會頻道報排名", function() return S().levelAnnounce end, function(v)
    S().levelAnnounce = v
    ns.UI.Refresh("levelup")
  end)
  p.check:SetPoint("TOPLEFT", 0, -76)
  local label = ns.UI.Text(p, "GameFontHighlightSmall", "多久說一次")
  label:SetPoint("TOPLEFT", 4, -114)
  p.every = {}
  local x = 80
  for _, e in ipairs(L.EVERY) do
    local b = ns.UI.Button(p, EVERY_TEXT[e], 80, 22, function()
      S().levelEvery = e
      ns.UI.Refresh("levelup")
    end)
    b:SetPoint("TOPLEFT", x, -108)
    b.every = e
    p.every[#p.every + 1] = b
    x = x + 86
  end
  p.status = ns.UI.Text(p, "GameFontHighlightSmall", "", 430)
  p.status:SetPoint("TOPLEFT", 0, -146)
  p.test = ns.UI.Button(p, "試一下（只有你看得到）", 170, 22, function() L.Test() end)
  p.test:SetPoint("TOPLEFT", 0, -190)
  local note = ns.UI.Text(p, "GameFontDisableSmall",
    "名次照公會名單上每個人的等級算，離線的人是他最後一次上線的等級。戰鬥中升級的話，打完才說。", 430)
  note:SetPoint("TOPLEFT", 0, -226)
  L.page = p
end

local function refreshTab(p)
  p.check:Refresh()
  local every = L.Every()
  for _, b in ipairs(p.every) do b:SetAlpha(b.every == every and 1 or 0.6) end
  local lines = {}
  if not S().levelAnnounce then
    lines[#lines + 1] = "|cff9d9d9d現在關著：打勾才會說。|r"
  elseif not (IsInGuild and IsInGuild()) then
    lines[#lines + 1] = "|cffff6060這隻角色不在公會，升級時不會說。|r"
  else
    local lv = tonumber(UnitLevel("player")) or 0
    local max = tonumber(ns.Call(_G, "GetMaxPlayerLevel")) or 60
    local nextLv = (math.floor(lv / every) + 1) * every
    if lv >= max then
      lines[#lines + 1] = "|cff60d060開著：你已經滿級了。|r"
    else
      lines[#lines + 1] = ("|cff60d060開著：下一次在 %d 級說。|r"):format(math.min(nextLv, max))
    end
  end
  local last = S().levelLast
  if type(last) == "table" and last.level then
    lines[#lines + 1] = ("|cff9d9d9d上一次說的是 %d 級（%s）。|r"):format(last.level, date("%m/%d %H:%M", last.at or 0))
  end
  p.status:SetText(table.concat(lines, "\n"))
end

ns.UI.AddTab("levelup", "升級公告", buildTab, refreshTab)
