-- 阿莫比小幫手：M 地圖增強（1.24.0；老闆 11/8 轉述玩家建議「M地圖增強：顯示未探索、可設定顯示旅店、訓練師等等、顯示建議等級、領地」）
-- 示意圖：D:\魔獸網站\小幫手地圖與飛行示意圖\
--   1. 去迷霧：區域地圖上沒探索過的那幾塊也畫出來（遊戲只畫探索過的：C_MapExplorationInfo.GetExploredMapTextures）。
--      每張圖有哪幾塊、圖檔編號在 Data\MapOverlays.lua（永恆客戶端的 WorldMapOverlay／WorldMapOverlayTile，
--      site/scripts/wowdata/extract_map_overlays.py）；位置大小的算法照暴雪的 MapExplorationDataProvider.lua。
--   2. 地圖上標旅店、專業訓練師、職業訓練師、郵箱、銀行、拍賣場、修理、獸欄、戰場軍官（「畫面優化」分頁勾要哪些；預設前三樣）。
--      位置是 Data\Map.lua 的（和「地圖導航」同一份，經典版參考），滑鼠指著有名字和「位置是經典版參考」。
--      敵對陣營的訓練師不標，職業訓練師只標自己職業的（和地圖導航一樣）。
--   3. 建議等級、領地：區域地圖左上角一小塊「艾爾文森林 5–10／聯盟領地・對你來說…」（等級顏色照你的等級，和地圖導航一樣）；
--      大陸地圖每個區域中間標建議等級，框的顏色是聯盟（藍）／部落（紅）／爭奪中（黃）。
-- 做法（不改暴雪的地圖視窗，和地圖導航的原則一樣）：自己的框架（父是 UIParent，不接滑鼠點擊）錨在世界地圖的捲動區上、
--   裁掉超出的部分；去迷霧那層的大小、縮放跟著地圖畫布（WorldMapFrame.ScrollContainer.Child）走，圖層高度用地圖自己的
--   「探索圖層」（PIN_FRAME_LEVEL_MAP_EXPLORATION），所以任務、飛行點這些圖示照樣在上面。只讀地圖的編號、大小、縮放，
--   不呼叫會改地圖的函式、不加資料提供者、不 hook 地圖。
-- 「畫面優化」分頁可以分別關（mapReveal、mapInfo、mapPins）。

local _, ns = ...
local M = {}
ns.MapPlus = M

M.KINDS = {
  { key = "inn", name = "旅店", icon = "Interface\\Minimap\\Tracking\\Innkeeper", on = true },
  { key = "prof", name = "專業訓練師", icon = "Interface\\Minimap\\Tracking\\Profession", on = true },
  { key = "class", name = "職業訓練師", icon = "Interface\\Minimap\\Tracking\\Class", on = true },
  { key = "mail", name = "郵箱", icon = "Interface\\Minimap\\Tracking\\Mailbox" },
  { key = "bank", name = "銀行", icon = "Interface\\Minimap\\Tracking\\Banker" },
  { key = "auction", name = "拍賣場", icon = "Interface\\Minimap\\Tracking\\Auctioneer" },
  { key = "repair", name = "修理", icon = "Interface\\Minimap\\Tracking\\Repair" },
  { key = "stable", name = "獸欄管理員", icon = "Interface\\Minimap\\Tracking\\StableMaster" },
  { key = "battle", name = "戰場軍官", icon = "Interface\\Minimap\\Tracking\\BattleMaster" },
}
local PIN = 18
local FAC = { ["聯盟"] = { 0.31, 0.53, 0.92 }, ["部落"] = { 0.85, 0.29, 0.32 }, ["爭奪中"] = { 0.91, 0.77, 0.35 } }

local clip, reveal, pins, info
local texFree, texLive = {}, {}
local pinFree, pinLive = {}, {}
local shownMap, dirty, lastScale, lastW, lastH

local function S() return ns.db.settings end
local function num(v) return type(v) == "number" and not ns.Secret(v) and v or nil end
local function yes(v) return not ns.Secret(v) and v and true or false end

function M.PinOn(key)
  local t = S().mapPins
  if type(t) == "table" and t[key] ~= nil then return t[key] and true or false end
  for _, k in ipairs(M.KINDS) do if k.key == key then return k.on == true end end
  return false
end

function M.SetPin(key, on)
  S().mapPins = type(S().mapPins) == "table" and S().mapPins or {}
  S().mapPins[key] = on and true or false
  dirty = true
end

function M.Dirty() dirty = true end

local function anyOn()
  if S().mapReveal ~= false or S().mapInfo ~= false then return true end
  for _, k in ipairs(M.KINDS) do if M.PinOn(k.key) then return true end end
  return false
end

-- 世界地圖（沒載入、沒有畫布就是 nil）
local function worldMap()
  local f = _G.WorldMapFrame
  local sc = f and f.ScrollContainer
  if sc and sc.Child then return f, sc, sc.Child end
end

local function pinLevel(f, kind, fallback)
  local ok, mgr = pcall(function() return f:GetPinFrameLevelsManager() end)
  if ok and mgr then
    local ok2, v = pcall(mgr.GetValidFrameLevel, mgr, kind)
    if ok2 and num(v) then return v end
  end
  return fallback
end

-- ------------------------------------------------------------------ 框架
local function ensure()
  if clip then return end
  clip = CreateFrame("Frame", nil, UIParent)
  clip:SetClipsChildren(true)
  clip:EnableMouse(false)
  clip:Hide()
  reveal = CreateFrame("Frame", nil, clip)
  reveal:EnableMouse(false)
  pins = CreateFrame("Frame", nil, clip)
  pins:SetAllPoints(clip)
  pins:EnableMouse(false)
  info = CreateFrame("Frame", nil, clip, "BackdropTemplate")
  info:EnableMouse(false)
  info:SetPoint("TOPLEFT", clip, "TOPLEFT", 10, -10)
  ns.Hud.GoldBox(info, 0.82)
  info.title = ns.Hud.Text(info, 17)
  info.title:SetPoint("TOPLEFT", 12, -10)
  info.title:SetTextColor(1, 0.9, 0.66)
  info.sub = ns.Hud.Text(info, 12)
  info.sub:SetPoint("TOPLEFT", info.title, "BOTTOMLEFT", 0, -4)
  info:Hide()
end

local function releaseAll()
  for i = #texLive, 1, -1 do texLive[i]:Hide(); texFree[#texFree + 1] = texLive[i]; texLive[i] = nil end
  for i = #pinLive, 1, -1 do pinLive[i]:Hide(); pinFree[#pinFree + 1] = pinLive[i]; pinLive[i] = nil end
  if info then info:Hide() end
end

-- ------------------------------------------------------------------ 1. 去迷霧
function M.Unexplored(mapID)
  local MO = ns.MapOverlays
  if not MO then return {} end
  local art = num(ns.Call(C_Map, "GetMapArtID", mapID)) or MO.maps[mapID]
  local list = art and MO.arts[art]
  if not list then return {} end
  local seen = {}
  local explored = ns.Call(C_MapExplorationInfo, "GetExploredMapTextures", mapID)
  if type(explored) == "table" and not ns.Secret(explored) then
    for _, e in ipairs(explored) do
      if type(e) == "table" and num(e.offsetX) and num(e.offsetY) then seen[e.offsetX .. "," .. e.offsetY] = true end
    end
  end
  local out = {}
  for _, o in ipairs(list) do
    if not seen[o[3] .. "," .. o[4]] then out[#out + 1] = o end
  end
  return out
end

local function buildReveal(mapID)
  local layers = ns.Call(C_Map, "GetMapArtLayers", mapID)
  local L = type(layers) == "table" and layers[1] or nil
  local TW, TH = L and num(L.tileWidth) or 256, L and num(L.tileHeight) or 256
  for _, o in ipairs(M.Unexplored(mapID)) do
    local w, h, ox, oy, files = o[1], o[2], o[3], o[4], o[5]
    local wide, tall = math.ceil(w / TW), math.ceil(h / TH)
    for j = 1, tall do
      local ph, fh = TH, TH
      if j == tall then
        ph = h % TH
        if ph == 0 then ph = TH end
        fh = 16
        while fh < ph do fh = fh * 2 end
      end
      for k = 1, wide do
        local pw, fw = TW, TW
        if k == wide then
          pw = w % TW
          if pw == 0 then pw = TW end
          fw = 16
          while fw < pw do fw = fw * 2 end
        end
        local fd = files[(j - 1) * wide + k]
        if fd then
          local t = table.remove(texFree) or reveal:CreateTexture(nil, "ARTWORK")
          t:ClearAllPoints()
          t:SetSize(pw, ph)
          t:SetTexCoord(0, pw / fw, 0, ph / fh)
          t:SetPoint("TOPLEFT", reveal, "TOPLEFT", ox + TW * (k - 1), -(oy + TH * (j - 1)))
          t:SetTexture(fd, nil, nil, "TRILINEAR")
          t:Show()
          texLive[#texLive + 1] = t
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ 2. 地圖上的 NPC、大陸地圖的等級
local function takePin()
  local b = table.remove(pinFree)
  if not b then
    b = CreateFrame("Frame", nil, pins, "BackdropTemplate")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.text = ns.Hud.Text(b, 13)
    b.text:SetPoint("CENTER")
    b.text:SetJustifyH("CENTER")
    if b.SetMouseClickEnabled and b.SetMouseMotionEnabled then
      b:SetMouseClickEnabled(false)                -- 點擊照常穿過去給地圖，只有指著時顯示說明
      b:SetMouseMotionEnabled(true)
    else
      b:EnableMouse(false)
    end
    b:SetScript("OnEnter", function(self)
      if not self.tip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.tip[1])
      for i = 2, #self.tip do GameTooltip:AddLine(self.tip[i], 1, 1, 1, true) end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  b.icon:Hide()
  b.text:SetText("")
  if b.SetBackdrop then b:SetBackdrop(nil) end
  b:Show()
  pinLive[#pinLive + 1] = b
  return b
end

local function levelWord(z)
  local lv = num(UnitLevel("player")) or 0
  if not (z and z.lo) then return "" end
  if lv < z.lo - 4 then return "對你來說太難" end
  if lv < z.lo then return "對你來說有點難" end
  if lv <= z.hi then return "剛好適合你" end
  if lv <= z.hi + 5 then return "對你來說有點簡單" end
  return "對你來說太簡單"
end

local function levelText(id)
  return ns.Navigate and ns.Navigate.LevelText(id) or ""
end

local function buildPins(mapID)
  local MD = ns.MapData
  if not (MD and MD.points) then return end
  local fac = UnitFactionGroup("player")
  local enemy = fac == "Alliance" and "H" or fac == "Horde" and "A" or nil
  local myClass = select(3, UnitClass("player"))
  for _, k in ipairs(M.KINDS) do
    if M.PinOn(k.key) then
      local trainer = k.key == "prof" or k.key == "class"
      for _, p in ipairs(MD.points[k.key] or {}) do
        if p[1] == mapID and not (trainer and enemy and p[10] == enemy) and not (k.key == "class" and p[9] ~= myClass) then
          local b = takePin()
          b:SetSize(PIN, PIN)
          b.icon:SetTexture(k.icon)
          b.icon:Show()
          b.x, b.y = p[2], p[3]
          b.tip = { k.name, p[7] .. ((trainer and p[8]) and ("（" .. p[8] .. "）") or ""), "|cff9d9d9d位置是經典版參考|r" }
        end
      end
    end
  end
end

-- 大陸地圖：每個區域中間標建議等級，框的顏色是領地
local function buildLevels(mapID)
  local MD = ns.MapData
  local kids = ns.Call(C_Map, "GetMapChildrenInfo", mapID, Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3, false)
  if type(kids) ~= "table" or ns.Secret(kids) then return end
  for _, c in ipairs(kids) do
    local id = type(c) == "table" and num(c.mapID)
    local z = id and MD and MD.zones[id]
    if z and z.lo then
      local minX, maxX, minY, maxY = ns.Call(C_Map, "GetMapRectOnMap", id, mapID)
      if num(minX) and num(maxX) and num(minY) and num(maxY) then
        local b = takePin()
        b.text:SetText(levelText(id))
        local w = (b.text:GetStringWidth() or 30) + 14
        b:SetSize(w, 20)
        ns.Hud.GoldBox(b, 0.78)
        local col = FAC[z.faction or ""] or { 0.8, 0.8, 0.8 }
        b:SetBackdropBorderColor(col[1], col[2], col[3], 1)
        b.x, b.y = (minX + maxX) / 2, (minY + maxY) / 2
        b.tip = { z.name .. " " .. levelText(id), (z.faction and (z.faction == "爭奪中" and "爭奪中的區域" or z.faction .. "領地") or ""), levelWord(z) }
      end
    end
  end
end

local function buildInfo(mapID)
  local z = ns.MapData and ns.MapData.zones[mapID]
  local mi = ns.Call(C_Map, "GetMapInfo", mapID)
  local mtype = type(mi) == "table" and not ns.Secret(mi) and num(mi.mapType)
  local T = Enum and Enum.UIMapType or {}
  if mtype and mtype == (T.Continent or 2) then
    info.title:SetText((type(mi.name) == "string" and mi.name) or "")
    info.sub:SetText("數字是建議等級；框：|cff4f87ea藍＝聯盟|r、|cffd94a52紅＝部落|r、|cffe8c55a黃＝爭奪中|r")
  elseif z and (z.lo or z.faction) then
    info.title:SetText(z.name .. (z.lo and ("  " .. levelText(mapID)) or ""))
    local col = FAC[z.faction or ""]
    local fac = z.faction and (z.faction == "爭奪中" and "爭奪中的區域" or z.faction .. "領地") or ""
    local c = col and ("|cff%02x%02x%02x"):format(col[1] * 255, col[2] * 255, col[3] * 255) or ""
    info.sub:SetText((fac ~= "" and (c .. fac .. "|r") or "") .. (z.lo and ((fac ~= "" and "・" or "") .. levelWord(z)) or ""))
  else
    return
  end
  local w = math.max(info.title:GetStringWidth() or 0, info.sub:GetStringWidth() or 0) + 26
  info:SetSize(math.max(140, w), 52)
  info:Show()
end

function M.Build(mapID)
  ensure()
  releaseAll()
  if not mapID then return end
  if S().mapReveal ~= false then buildReveal(mapID) end
  local mi = ns.Call(C_Map, "GetMapInfo", mapID)
  local mtype = type(mi) == "table" and not ns.Secret(mi) and num(mi.mapType)
  local T = Enum and Enum.UIMapType or {}
  if S().mapInfo ~= false then
    buildInfo(mapID)
    if mtype == (T.Continent or 2) then buildLevels(mapID) end
  end
  buildPins(mapID)
end

-- 縮放、拖動後：圖示放回地圖上的位置（圖示大小不跟著縮放）
local function placePins(s, W, H)
  for _, b in ipairs(pinLive) do
    b:ClearAllPoints()
    b:SetPoint("CENTER", reveal, "TOPLEFT", b.x * W * s, -b.y * H * s)
  end
end

-- 每一格畫面（地圖開著時）：跟著地圖的大小、縮放、層級
function M.Step()
  local f, sc, canvas = worldMap()
  if not f or not yes(f:IsShown()) or not anyOn() then
    if clip and clip:IsShown() then clip:Hide() end
    shownMap = nil
    return
  end
  ensure()
  if clip.on ~= sc then
    clip:ClearAllPoints()
    clip:SetAllPoints(sc)
    clip.on = sc
  end
  local strata = f:GetFrameStrata()
  if clip:GetFrameStrata() ~= strata then clip:SetFrameStrata(strata) end
  local base = canvas:GetFrameLevel() or 1
  local rl = pinLevel(f, "PIN_FRAME_LEVEL_MAP_EXPLORATION", base + 1)
  local pl = pinLevel(f, "PIN_FRAME_LEVEL_AREA_POI", rl + 20) + 1
  if clip.rl ~= rl or clip.pl ~= pl then
    clip.rl, clip.pl = rl, pl
    clip:SetFrameLevel(math.max(1, rl - 1))
    reveal:SetFrameLevel(rl)
    pins:SetFrameLevel(pl)
    info:SetFrameLevel(pl + 5)
  end
  clip:Show()
  local ok, mapID = pcall(f.GetMapID, f)
  mapID = ok and num(mapID) or nil
  if mapID ~= shownMap or dirty then
    shownMap, dirty, lastScale = mapID, false, nil
    M.Build(mapID)
  end
  local W, H = canvas:GetWidth(), canvas:GetHeight()
  local s = canvas:GetEffectiveScale() / clip:GetEffectiveScale()
  if s ~= lastScale or W ~= lastW or H ~= lastH then
    lastScale, lastW, lastH = s, W, H
    reveal:SetScale(s)
    reveal:SetSize(W, H)
    reveal:ClearAllPoints()
    reveal:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, 0)
    placePins(s, W, H)
  end
end

function M.Count() return #texLive, #pinLive, info and info:IsShown() end

function M.Init()
  local f = CreateFrame("Frame")
  f:SetScript("OnUpdate", function() ns.Try("map:step", M.Step) end)
  ns.On("MAP_EXPLORATION_UPDATED", function() dirty = true end)
  ns.On("PLAYER_LEVEL_UP", function() dirty = true end)
end

ns.Register(M)
