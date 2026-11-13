-- 阿莫比小幫手：滑鼠跟隨閃亮亮（1.24.0；老闆 11/8 轉述玩家建議「滑鼠跟隨閃亮亮✨」）
-- 滑鼠移動時在後面撒幾顆星星（遊戲內建的 Interface\Cooldown\star4 材質，疊加發光），0.7 秒內淡出、變小、往下飄一點。
--   * 戰鬥中不撒（不擋視線）；按住右鍵轉鏡頭（IsMouselooking）時不撒。
--   * 一個全畫面的透明框（不接滑鼠，點擊照常穿過），最多同時 40 顆，用完就重複用，不會越積越多。
--   * 「畫面優化」分頁可以關（cursorSparkle，預設開；sparkle 是實用功能的拾取閃光，不一樣）。只畫圖，不會做任何事。

local _, ns = ...
local K = {}
ns.Sparkle = K

local TEX = "Interface\\Cooldown\\star4"
local MAX = 40
local LIFE = 0.7          -- 秒：一顆星星多久消失
local GAP = 12            -- 像素：滑鼠移動這麼遠才撒一顆
local COLORS = { { 1, 0.92, 0.55 }, { 1, 1, 1 }, { 0.72, 0.86, 1 }, { 1, 0.74, 0.9 } }

local frame
local free, live = {}, {}
local lastX, lastY

function K.On() return ns.db.settings.cursorSparkle ~= false end

local function take()
  local t = table.remove(free)
  if not t then
    if #live >= MAX then return nil end
    t = frame:CreateTexture(nil, "OVERLAY")
    t:SetTexture(TEX)
    t:SetBlendMode("ADD")
  end
  return t
end

local function clear()
  for i = #live, 1, -1 do
    local p = live[i]
    p.tex:Hide()
    free[#free + 1] = p.tex
    live[i] = nil
  end
  lastX, lastY = nil, nil
end

local function spawn(x, y)
  local t = take()
  if not t then return end
  local c = COLORS[math.random(#COLORS)]
  t:SetVertexColor(c[1], c[2], c[3])
  local size = math.random(12, 24)
  if t.SetRotation then t:SetRotation(math.random() * math.pi) end
  live[#live + 1] = { tex = t, x = x + math.random(-6, 6), y = y + math.random(-6, 6), age = 0, size = size,
                      drift = math.random(8, 20) }
  t:Show()
end

-- 每一格畫面：撒新的、舊的變淡
function K.Step(elapsed)
  if not K.On() or InCombatLockdown() then
    if #live > 0 then clear() end
    return
  end
  local x, y = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  if type(x) == "number" and type(y) == "number" and scale and scale > 0 then
    x, y = x / scale, y / scale
    local looking = IsMouselooking and IsMouselooking()
    if not looking and lastX and ((x - lastX) ^ 2 + (y - lastY) ^ 2) >= GAP * GAP then
      spawn(x, y)
      lastX, lastY = x, y
    elseif not lastX or looking then
      lastX, lastY = x, y
    end
  end
  for i = #live, 1, -1 do
    local p = live[i]
    p.age = p.age + elapsed
    if p.age >= LIFE then
      p.tex:Hide()
      free[#free + 1] = p.tex
      table.remove(live, i)
    else
      local k = 1 - p.age / LIFE
      local s = p.size * (0.4 + 0.6 * k)
      p.tex:SetSize(s, s)
      p.tex:SetAlpha(k)
      p.tex:ClearAllPoints()
      p.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y - p.drift * p.age)
    end
  end
end

function K.Count() return #live end

function K.Init()
  frame = CreateFrame("Frame", nil, UIParent)
  frame:SetFrameStrata("TOOLTIP")
  frame:SetAllPoints(UIParent)
  frame:EnableMouse(false)
  frame:SetScript("OnUpdate", function(_, elapsed) ns.Try("sparkle", K.Step, elapsed) end)
end

ns.Register(K)
