-- 阿莫比小幫手：鳥點計時器（1.24.0；老闆 11/8 轉述玩家建議「鳥點計時器」）
-- 坐飛行點時，畫面上方一條：飛往哪裡、還有多久到（進度條）；這條航線第一次飛就顯示已經飛了多久，落地時記下時間，下次就知道。
--   * 目的地：玩家在飛行地圖上點了哪一站（TakeTaxiNode）。用 hooksecurefunc("TakeTaxiNode", …) 在遊戲的函式後面記下站名
--     （TaxiNodeName）、出發的站（TaxiNodeGetType 是 "CURRENT" 的那一站）；只記，不改遊戲的函式、不碰飛行地圖的視窗。
--     這是小幫手唯一用 hooksecurefunc 的地方（維護說明第 2 節、原始碼掃描的例外）。
--   * 起飛、落地：UnitOnTaxi("player") 變成 true／false（每 0.2 秒看一次）。落地時飛了 8 秒以上才記。
--   * 時間存在自己的存檔（db.flight.times["起點>終點"] = { t = 秒, n = 飛過幾次 }），取最近 3 次的平均；
--     沒有點站名（例如從別的方式上飛行）就用飛行點的位置（Data\Map.lua）找最近的站當起點、終點。
--   * 「畫面優化」分頁可以關（flightTimer，預設開）。

local _, ns = ...
local F = {}
ns.Flight = F

local POLL = 0.2
local MIN_FLIGHT = 8       -- 秒：飛不到這麼久不記（點錯馬上下來）
local PENDING = 15         -- 秒：點了站之後這麼久內起飛才算這一趟
local NEAR = 120           -- 碼：用位置找飛行點時，這麼近以內才算

local db
local bar
local pending, flying
local acc = 0

local function S() return ns.db.settings end
function F.On() return S().flightTimer ~= false end

local function str(v) return type(v) == "string" and not ns.Secret(v) and v ~= "" and v or nil end

local function clock(sec)
  sec = math.max(0, math.floor(sec + 0.5))
  return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end

-- 最近的飛行點（Data\Map.lua 的 flight，世界座標）；回傳站名
function F.NearestNode()
  local N, MD = ns.Navigate, ns.MapData
  if not (N and MD and MD.points and MD.points.flight) then return nil end
  local map, x, y = N.Where()
  if not x then return nil end
  local c, X, Y = N.ToWorld(map, x, y)
  if not c then return nil end
  local best, bd
  for _, p in ipairs(MD.points.flight) do
    if p[4] == c then
      local d = math.sqrt((p[5] - X) ^ 2 + (p[6] - Y) ^ 2)
      if d < NEAR and (not bd or d < bd) then best, bd = p[7], d end
    end
  end
  return best
end

local function key(from, to) return (from or "?") .. ">" .. (to or "?") end

-- 這條航線記到的時間（秒），沒有回傳 nil
function F.Time(from, to)
  local e = from and to and db.times[key(from, to)]
  return type(e) == "table" and type(e.t) == "number" and e.t or nil
end

function F.Record(from, to, secs)
  if not (from and to) or from == to or secs < MIN_FLIGHT then return end
  local k = key(from, to)
  local e = db.times[k]
  if type(e) ~= "table" then e = { n = 0, last = {} }; db.times[k] = e end
  e.last = type(e.last) == "table" and e.last or {}
  table.insert(e.last, math.floor(secs + 0.5))
  while #e.last > 3 do table.remove(e.last, 1) end
  local sum = 0
  for _, v in ipairs(e.last) do sum = sum + v end
  e.t = math.floor(sum / #e.last + 0.5)
  e.n = (e.n or 0) + 1
end

-- TakeTaxiNode(第幾站) 的後面：記下要去哪、從哪出發
function F.Took(slot)
  local to = str(ns.Call(_G, "TaxiNodeName", slot))
  local from
  local n = ns.Call(_G, "NumTaxiNodes")
  if type(n) == "number" then
    for i = 1, n do
      if ns.Call(_G, "TaxiNodeGetType", i) == "CURRENT" then from = str(ns.Call(_G, "TaxiNodeName", i)) end
    end
  end
  pending = { from = from or F.NearestNode(), to = to, at = GetTime() }
end

-- ------------------------------------------------------------------ 畫面上方那一條
local function build()
  bar = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  bar:SetSize(380, 50)
  bar:SetFrameStrata("MEDIUM")
  ns.Hud.GoldBox(bar)
  bar.title = ns.Hud.Text(bar, 15)
  bar.title:SetPoint("TOPLEFT", 12, -9)
  bar.title:SetPoint("RIGHT", -96, 0)
  bar.title:SetWordWrap(false)
  bar.title:SetTextColor(1, 0.9, 0.66)
  bar.time = ns.Hud.Text(bar, 15)
  bar.time:SetPoint("TOPRIGHT", -12, -9)
  bar.time:SetJustifyH("RIGHT")
  bar.box = CreateFrame("Frame", nil, bar, "BackdropTemplate")
  bar.box:SetHeight(10)
  bar.box:SetPoint("BOTTOMLEFT", 12, 10)
  bar.box:SetPoint("BOTTOMRIGHT", -12, 10)
  if bar.box.SetBackdrop then
    bar.box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    bar.box:SetBackdropColor(0.13, 0.1, 0.16, 0.95)
    bar.box:SetBackdropBorderColor(0.91, 0.78, 0.45, 0.6)
  end
  bar.fill = CreateFrame("StatusBar", nil, bar.box)
  bar.fill:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar.fill:SetStatusBarColor(0.47, 0.75, 1)
  bar.fill:SetMinMaxValues(0, 1)
  bar.fill:SetPoint("TOPLEFT", 1, -1)
  bar.fill:SetPoint("BOTTOMRIGHT", -1, 1)
  bar.note = ns.Hud.Text(bar.box, 11)
  bar.note:SetPoint("CENTER")
  bar.note:SetJustifyH("CENTER")
  bar:SetPoint("TOP", UIParent, "TOP", 0, -128)
  bar:Hide()
end

function F.Update()
  if not bar then return end
  if not (flying and F.On()) then bar:Hide(); return end
  local spent = GetTime() - flying.start
  bar.title:SetText(flying.to and ("飛往 " .. flying.to) or "飛行中")
  if flying.eta then
    local left = flying.eta - spent
    bar.time:SetText(left > 0 and ("還有 " .. clock(left)) or "快到了")
    bar.fill:SetValue(math.min(1, spent / flying.eta))
    bar.note:SetText("")
  else
    bar.time:SetText("已飛 " .. clock(spent))
    bar.fill:SetValue(0)
    bar.note:SetText("第一次飛這條，落地後就記住時間")
  end
  bar:Show()
end

-- 每 0.2 秒：看起飛、落地
function F.Poll()
  local v = UnitOnTaxi("player")
  local onTaxi = not ns.Secret(v) and v == true
  if onTaxi and not flying then
    local p = pending and GetTime() - pending.at < PENDING and pending or nil
    local from = p and p.from or F.NearestNode()
    local to = p and p.to
    flying = { from = from, to = to, start = GetTime(), eta = F.Time(from, to) }
    pending = nil
  elseif not onTaxi and flying then
    local secs = GetTime() - flying.start
    local to = flying.to or F.NearestNode()
    F.Record(flying.from, to, secs)
    flying = nil
  end
  F.Update()
end

function F.Flying() return flying end
function F.BarText()
  if not (bar and bar:IsShown()) then return nil end
  return (bar.title:GetText() or "") .. "｜" .. (bar.time:GetText() or "") .. "｜" .. (bar.note:GetText() or "")
end

function F.Init()
  ns.db.flight = type(ns.db.flight) == "table" and ns.db.flight or {}
  db = ns.db.flight
  db.times = type(db.times) == "table" and db.times or {}
  build()
  if type(TakeTaxiNode) == "function" and hooksecurefunc then
    hooksecurefunc("TakeTaxiNode", function(slot) ns.Try("flight:take", F.Took, slot) end)
  end
  local f = CreateFrame("Frame")
  f:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < POLL then return end
    acc = 0
    ns.Try("flight:poll", F.Poll)
  end)
end

ns.Register(F)
