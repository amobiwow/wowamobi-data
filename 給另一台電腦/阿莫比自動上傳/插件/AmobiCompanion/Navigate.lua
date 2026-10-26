-- 阿莫比小幫手：地圖導航（「地圖導航」分頁）
--   座標：小地圖下面一小塊「西部荒野 10–20  52.3, 47.1」（區域等級照自己的等級上色，和網站世界地圖一樣），
--         和距離、DPS、仇恨一起在「戰鬥畫面」分頁解鎖拖動
--   導航：遊戲內建的導航點（C_Map.SetUserWaypoint ＋ C_SuperTrack.SetSuperTrackedUserWaypoint），畫面上有箭頭和距離，像 TomTom。
--         /amobi 去 52.3 47.1（這一區）、/amobi 去 西部荒野 52 47；走到 8 碼內自動清掉；/amobi 清除導航
--   最近的地點：飛行點、副本入口、旅店、銀行、拍賣場、郵箱、修理、獸欄、戰場軍官、靈魂醫者（Data\Map.lua，網站世界地圖的資料；
--         旅店那些 NPC 是經典版參考，畫面上寫明），照直線距離排，按一下就導航
-- 位置：C_Map.GetBestMapForUnit ＋ GetPlayerMapPosition（地圖上的 0～1）；世界座標用 Data\Map.lua 每張地圖的範圍（UiMapAssignment）
-- 換回去，和地點的座標同一套，算出來的距離就是碼。副本裡遊戲不給位置：座標不顯示、最近的地點算不出來。
-- 原則：只用 C_Map、C_SuperTrack 的函式，不改暴雪的地圖視窗和小地圖（不加圖示、不去迷霧）。

local _, ns = ...
local N = {}
ns.Navigate = N
local MD = ns.MapData

local ARRIVE = 8          -- 碼：走到這麼近就清掉導航點
local LIST_N = 8          -- 最近的地點列幾個
local COORDS_TICK = 0.2

local function S() return ns.db.settings end

local function xy(v)
  if v == nil or ns.Secret(v) then return nil end
  if v.GetXY then return v:GetXY() end
  return v.x, v.y
end

-- 自己在哪：地圖編號, x, y（0～1）；副本裡、讀不到時回傳 nil
function N.Where()
  local map = ns.Call(C_Map, "GetBestMapForUnit", "player")
  if type(map) ~= "number" or ns.Secret(map) then return nil end
  local x, y = xy(ns.Call(C_Map, "GetPlayerMapPosition", map, "player"))
  if type(x) ~= "number" or type(y) ~= "number" or ns.Secret(x) or ns.Secret(y) or (x == 0 and y == 0) then return map end
  return map, x, y
end

-- 地圖上的位置 → 世界座標（大陸, X, Y）
function N.ToWorld(map, x, y)
  local z = MD.zones[map]
  if not (z and x and y) then return nil end
  for _, a in ipairs(z.asg) do
    local c, x0, y0, x1, y1, u0, v0, u1, v1 = unpack(a)
    if x >= math.min(u0, u1) and x <= math.max(u0, u1) and y >= math.min(v0, v1) and y <= math.max(v0, v1) then
      return c, x1 - (y - v0) / (v1 - v0) * (x1 - x0), y1 - (x - u0) / (u1 - u0) * (y1 - y0)
    end
  end
  return nil
end

function N.ZoneName(map)
  local z = MD.zones[map]
  if z then return z.name end
  local info = ns.Call(C_Map, "GetMapInfo", map)
  return (type(info) == "table" and not ns.Secret(info) and info.name) or "?"
end

-- 區域等級和顏色（和網站世界地圖一樣：太高紅、偏高橘、剛好黃、偏低綠、太低灰）
function N.LevelText(map)
  local z = MD.zones[map]
  if not (z and z.lo) then return "" end
  local lv = UnitLevel("player") or 0
  local c = lv < z.lo - 4 and "ff4040" or lv < z.lo and "ff9a40" or lv <= z.hi and "ffe040" or lv <= z.hi + 5 and "60d060" or "9d9d9d"
  return ("|cff%s%s|r"):format(c, z.lo == z.hi and tostring(z.lo) or (z.lo .. "–" .. z.hi))
end

-- ---------------------------------------------------------------------------- 導航點
-- 回傳 true, 訊息 或 false, 原因
function N.Go(map, x, y, label)
  if not (C_Map and C_Map.SetUserWaypoint) then return false, "這個遊戲版本沒有導航點。" end
  if C_Map.CanSetUserWaypointOnMap and ns.Call(C_Map, "CanSetUserWaypointOnMap", map) == false then
    return false, "這張地圖不能放導航點。"
  end
  local point
  if UiMapPoint and UiMapPoint.CreateFromCoordinates then
    point = UiMapPoint.CreateFromCoordinates(map, x, y)
  else
    point = { uiMapID = map, position = CreateVector2D(x, y) }
  end
  local ok = pcall(C_Map.SetUserWaypoint, point)
  if not ok then return false, "遊戲沒有接受這個導航點。" end
  ns.Call(C_SuperTrack, "SetSuperTrackedUserWaypoint", true)
  S().nav = { map, x, y, label }
  local text = ("導航到%s（%s %.1f, %.1f），畫面上會出現箭頭和距離。"):format(label and ("「" .. label .. "」") or "",
    N.ZoneName(map), x * 100, y * 100)
  return true, text
end

function N.Clear(quiet)
  ns.Call(C_Map, "ClearUserWaypoint")
  ns.Call(C_SuperTrack, "SetSuperTrackedUserWaypoint", false)
  S().nav = nil
  return true, quiet and "" or "已清除導航點。"
end

-- 走到了就清掉
function N.CheckArrive()
  local nav = S().nav
  if not nav then return end
  local map, x, y = N.Where()
  if not x then return end
  local c1, X1, Y1 = N.ToWorld(map, x, y)
  local c2, X2, Y2 = N.ToWorld(nav[1], nav[2], nav[3])
  if not (c1 and c2) or c1 ~= c2 then return end
  if math.sqrt((X1 - X2) ^ 2 + (Y1 - Y2) ^ 2) <= ARRIVE then
    N.Clear(true)
    ns.Print("到了" .. (nav[4] and ("「" .. nav[4] .. "」") or "") .. "，導航點已清掉。")
  end
end

-- 最近的地點：{ 地點, 距離（碼） }，同一塊大陸、照距離排
function N.Nearest(kind, n)
  local map, x, y = N.Where()
  if not x then return nil, "讀不到你現在的位置（副本裡遊戲不給位置）。" end
  local c, X, Y = N.ToWorld(map, x, y)
  if not c then return nil, "這張地圖小幫手沒有資料。" end
  local out = {}
  for _, p in ipairs(MD.points[kind] or {}) do
    if p[4] == c then out[#out + 1] = { p = p, d = math.sqrt((p[5] - X) ^ 2 + (p[6] - Y) ^ 2) } end
  end
  table.sort(out, function(a, b) return a.d < b.d end)
  while #out > (n or LIST_N) do table.remove(out) end
  return out
end

-- /amobi 去 52.3 47.1｜/amobi 去 西部荒野 52 47｜/amobi 去 （沒有數字：說明）
function N.Slash(rest)
  rest = strtrim(rest or "")
  local zone, a, b = rest:match("^(.-)%s*([%d%.]+)[%s,，]+([%d%.]+)$")
  local x, y = tonumber(a), tonumber(b)
  if not (x and y) then
    return ns.Print("用法：/amobi 去 52.3 47.1（這一區的座標），或 /amobi 去 西部荒野 52 47；清除：/amobi 清除導航")
  end
  local map
  zone = strtrim(zone or "")
  if zone == "" then
    map = N.Where()
    if not map then return ns.Print("|cffff6060讀不到你現在在哪一區，請寫區域名稱，例如：/amobi 去 西部荒野 52 47|r") end
  else
    for id, z in pairs(MD.zones) do
      if z.name == zone then map = id end
    end
    if not map then
      for id, z in pairs(MD.zones) do
        if z.name:find(zone, 1, true) then map = id end
      end
    end
    if not map then return ns.Print("|cffff6060找不到區域「" .. zone .. "」。|r") end
  end
  if x > 1 or y > 1 then x, y = x / 100, y / 100 end
  local ok, msg = N.Go(map, math.max(0, math.min(1, x)), math.max(0, math.min(1, y)))
  ns.Print((ok and "" or "|cffff6060") .. msg .. (ok and "" or "|r"))
end

-- ---------------------------------------------------------------------------- 座標小塊
local coords

local function defaultCoordsPos()
  local w, h = UIParent:GetWidth(), UIParent:GetHeight()
  if type(w) ~= "number" or type(h) ~= "number" or ns.Secret(w) or ns.Secret(h) then return { 400, 200 } end
  return { math.floor(w / 2 - 110), math.floor(h / 2 - 232) }   -- 右上角、小地圖下面
end

function N.UpdateCoords()
  if not coords then return end
  local map, x, y = N.Where()
  if not map then
    coords.text:SetText(S().rangeLocked and "" or "座標（拖曳移動）")
    return
  end
  local lv = N.LevelText(map)
  local place = N.ZoneName(map) .. (lv ~= "" and (" " .. lv) or "")
  if x then
    coords.text:SetFormattedText("%s  |cffffffff%.1f, %.1f|r", place, x * 100, y * 100)
  else
    coords.text:SetText(place)
  end
end

function N.ShowCoords()
  if not S().coords then
    if coords then coords:Hide() end
    return
  end
  if not coords then
    coords = ns.Assist.MakeBlock("coords", "coordsPos", defaultCoordsPos, 240, COORDS_TICK, function()
      N.UpdateCoords()
      N.CheckArrive()
    end)
    N.coords = coords
  end
  coords:Show()
  N.UpdateCoords()
end

function N.Init()
  ns.On("PLAYER_ENTERING_WORLD", function()
    ns.Try("nav-coords", N.ShowCoords)
  end)
  ns.On("ZONE_CHANGED_NEW_AREA", function() ns.Try("nav-coords", N.UpdateCoords) end)
end
ns.Register(N)

-- ---------------------------------------------------------------------------- 分頁
local page = {}

local function say(msg, ok)
  if page.status then page.status:SetText((ok == false and "|cffff6060" or "") .. (msg or "") .. (ok == false and "|r" or "")) end
end

local function kindInfo(key)
  for _, k in ipairs(MD.kinds) do
    if k.key == key then return k end
  end
end

local function showList(kind)
  page.kind = kind
  for _, b in ipairs(page.kindButtons) do b:SetAlpha(b.kind == kind and 1 or 0.55) end
  local k = kindInfo(kind)
  local list, why = N.Nearest(kind, LIST_N)
  page.listHead:SetText(ns.GOLD .. "最近的" .. k.name .. "|r" .. (k.classic and "　|cff9d9d9d經典版的位置，永恆可能不同|r" or ""))
  for i, row in ipairs(page.rows) do
    local e = list and list[i]
    if e then
      local p = e.p
      row.text:SetText(("%s  |cff9d9d9d%s %.0f, %.0f|r%s"):format(p[7], N.ZoneName(p[1]), p[2] * 100, p[3] * 100, p[8] and ("  |cffb7a98c" .. p[8] .. "|r") or ""))
      row.dist:SetText(("%d 碼"):format(math.floor(e.d + 0.5)))
      row.go.point = p
      row:Show()
    else
      row:Hide()
    end
  end
  if not list then say(why, false) elseif #list == 0 then say("這塊大陸沒有記到" .. k.name .. "。") else say("") end
end

local function build(p)
  page.p = p
  local intro = ns.UI.Text(p, "GameFontHighlightSmall",
    "用遊戲內建的導航點帶路：按「導航」後畫面上會出現箭頭和距離，走到附近自動清掉。地點來自阿莫比網站的世界地圖。", 430)
  intro:SetPoint("TOPLEFT", 0, 0)
  local cc = ns.UI.Check(p, "顯示座標和區域等級（小地圖下面）", function() return S().coords end, function(v)
    S().coords = v
    N.ShowCoords()
  end)
  cc:SetPoint("TOPLEFT", 0, -34)
  page.where = ns.UI.Text(p, "GameFontHighlight", "", 430)
  page.where:SetPoint("TOPLEFT", 0, -64)

  local h1 = ns.UI.Text(p, "GameFontNormal", "輸入座標導航")
  h1:SetPoint("TOPLEFT", 0, -92)
  page.box = ns.UI.Edit(p, 200)
  page.box:SetPoint("TOPLEFT", 6, -112)
  page.box:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    N.Slash(self:GetText())
  end)
  local go = ns.UI.Button(p, "導航", 70, 22, function() N.Slash(page.box:GetText()) end)
  go:SetPoint("LEFT", page.box, "RIGHT", 8, 0)
  local clear = ns.UI.Button(p, "清除導航", 84, 22, function() say(select(2, N.Clear())) end)
  clear:SetPoint("LEFT", go, "RIGHT", 6, 0)
  local hint = ns.UI.Text(p, "GameFontDisableSmall", "例如「52.3 47.1」（這一區）或「西部荒野 52 47」。聊天框也可以打 /amobi 去 52.3 47.1。", 430)
  hint:SetPoint("TOPLEFT", 0, -140)

  local h2 = ns.UI.Text(p, "GameFontNormal", "找最近的")
  h2:SetPoint("TOPLEFT", 0, -170)
  page.kindButtons = {}
  local x, y = 0, -190
  for _, k in ipairs(MD.kinds) do
    if k.key ~= "town" then
      local b = ns.UI.Button(p, k.name, 84, 22, function() showList(k.key) end)
      b.kind = k.key
      b:SetPoint("TOPLEFT", x, y)
      x = x + 88
      if x > 400 then x, y = 0, y - 26 end
      page.kindButtons[#page.kindButtons + 1] = b
    end
  end
  page.listHead = ns.UI.Text(p, "GameFontHighlightSmall", "", 430)
  page.listHead:SetPoint("TOPLEFT", 0, y - 34)
  page.rows = {}
  for i = 1, LIST_N do
    local row = CreateFrame("Frame", nil, p)
    row:SetSize(430, 24)
    row:SetPoint("TOPLEFT", 0, y - 52 - (i - 1) * 26)
    row.text = ns.UI.Text(row, "GameFontHighlightSmall", "", 290)
    row.text:SetPoint("LEFT", 0, 0)
    row.dist = ns.UI.Text(row, "GameFontDisableSmall", "")
    row.dist:SetPoint("RIGHT", -62, 0)
    row.go = ns.UI.Button(row, "導航", 56, 20, function(self)
      local pt = self.point
      if pt then say(select(2, N.Go(pt[1], pt[2], pt[3], pt[7]))) end
    end)
    row.go:SetPoint("RIGHT", 0, 0)
    row:Hide()
    page.rows[i] = row
  end
  page.status = ns.UI.Text(p, "GameFontHighlightSmall", "", 430)
  page.status:SetPoint("TOPLEFT", 0, y - 52 - LIST_N * 26 - 6)
  N.page = page
end

local function refresh()
  local map, x, y = N.Where()
  if map then
    local lv = N.LevelText(map)
    page.where:SetText(("你在：%s%s%s"):format(N.ZoneName(map), lv ~= "" and ("（" .. lv .. " 級）") or "",
      x and ("  %.1f, %.1f"):format(x * 100, y * 100) or "  （這裡遊戲不給座標）"))
  else
    page.where:SetText("你在：讀不到位置")
  end
  showList(page.kind or "flight")
end

ns.UI.AddTab("nav", "地圖導航", build, refresh)
