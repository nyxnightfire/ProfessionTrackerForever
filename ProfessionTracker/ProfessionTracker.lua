local ADDON_NAME = ...
local PROFESSION_SKILL_IDS = {
    [171] = "Alchemy", [164] = "Blacksmithing", [333] = "Enchanting",
    [202] = "Engineering", [182] = "Herbalism", [186] = "Mining",
    [393] = "Skinning", [197] = "Tailoring", [165] = "Leatherworking",
    [185] = "Cooking", [356] = "Fishing", [129] = "First Aid",
}
local PROFESSION_NAMES = {
    ["Alchemy"] = true, ["Blacksmithing"] = true, ["Enchanting"] = true,
    ["Engineering"] = true, ["Herbalism"] = true, ["Mining"] = true,
    ["Skinning"] = true, ["Tailoring"] = true, ["Leatherworking"] = true,
    ["Cooking"] = true, ["Fishing"] = true, ["First Aid"] = true,
    ["Poisons"] = true, ["Lockpicking"] = true,
}
local RANK_NAMES = { [75] = "Apprentice", [150] = "Journeyman", [225] = "Expert", [300] = "Artisan" }
local GOLD = { 1, 0.82, 0.12, 1 }
local BAR_COLORS = {
    silver = { 0.78, 0.82, 0.9 },
    blue = { 0.18, 0.48, 0.95 },
    green = { 0.2, 0.78, 0.24 },
    gold = { 0.95, 0.66, 0.08 },
    purple = { 0.67, 0.3, 0.9 },
}
local rows = {}
local frame
local collapsed = false
local expanded = {}
local lastSkill = {}
local expandedPoint
local expandedBounds
local bookAnchorActive = false
local activeProfessionBook
local professionBookMonitorRunning = false
local bookPreviousPoint
local bookPreviousCollapsed
local bookPreviousStrata
local bookPreviousLevel
local hookedProfessionBooks = {}
local lastRowsReverse = nil
local fishingCastUntil = 0
local lastFishingCatchAt = 0
local MakeBackdrop
local NewFont
local euiSkin
local euiLookHooked = false
local ApplyCollapsePresentation
local RememberExpandedPoint
local MonitorProfessionBook
local TryAttachToProfessionBook
local HookProfessionBookFrames
local eventRegistrationErrors = {}

local function GetOptions()
    ProfessionTrackerDB.options = ProfessionTrackerDB.options or {}
    local options = ProfessionTrackerDB.options
    if options.enabled == nil then options.enabled = true end
    if options.barColor == nil then options.barColor = "silver" end
    if options.showTier == nil then options.showTier = true end
    if options.showSkillNumbers == nil then options.showSkillNumbers = true end
    if options.rankUpGlow == nil then options.rankUpGlow = true end
    if options.uiStyle == nil or (options.uiStyle == "classic" and not options.uiStyleModeSet) then
        options.uiStyle = "auto"
    end
    if options.titleBarPosition == nil then options.titleBarPosition = "top" end
    if options.collapseDirection == nil then options.collapseDirection = "top" end
    if options.collapseDirection == "left" or options.collapseDirection == "right" then
        options.collapseDirection = "top"
    end
    if options.lockPosition == nil then options.lockPosition = false end
    return options
end

function ProfessionTracker_GetOptions()
    return GetOptions()
end

function ProfessionTracker_GetProfessionSettings(name)
    ProfessionTrackerDB.professionSettings = ProfessionTrackerDB.professionSettings or {}
    local settings = ProfessionTrackerDB.professionSettings[name]
    if not settings then
        settings = {}
        ProfessionTrackerDB.professionSettings[name] = settings
    end
    if settings.estimateDetail == nil then settings.estimateDetail = "full" end
    if settings.recipePriority == nil then settings.recipePriority = "lowest_cost" end
    if settings.fishingRateMode == nil then settings.fishingRateMode = "learn" end
    if settings.customFishingRate == nil then settings.customFishingRate = 2.5 end
    if settings.gatherRateMode == nil then
        settings.gatherRateMode = name == "Fishing" and settings.fishingRateMode or "learn"
    end
    if settings.customGatherRate == nil then settings.customGatherRate = settings.customFishingRate end
    return settings
end

function ProfessionTracker_SetProfessionSetting(name, key, value)
    ProfessionTracker_GetProfessionSettings(name)[key] = value
    ProfessionTracker_ApplyOptions()
end

local function GetResolvedUIStyle()
    local style = GetOptions().uiStyle or "auto"
    if style == "ellesmere" then return euiSkin and "eui" or "modern" end
    if style ~= "auto" then return style end
    if euiSkin then return "eui" end

    local knownUIAddons = {
        "EllesmereUI", "ElvUI", "Tukui", "GW2_UI", "NDui", "AzeriteUI", "DiabolicUI",
    }
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if isLoaded then
        for _, addonName in ipairs(knownUIAddons) do
            local ok, loaded = pcall(isLoaded, addonName)
            if ok and loaded then return "modern" end
        end
    end
    return "classic"
end

local function ResolveBarColor(color)
    if type(color) == "table" then
        local r, g, b = color.r or color[1], color.g or color[2], color.b or color[3]
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return { r = r, g = g, b = b }
        end
    elseif type(color) == "string" and BAR_COLORS[color] then
        local preset = BAR_COLORS[color]
        return { r = preset[1], g = preset[2], b = preset[3] }
    end
end

function ProfessionTracker_GetBarColor(name)
    local custom = name and ProfessionTrackerDB.professionBarColors and ProfessionTrackerDB.professionBarColors[name]
    local options = GetOptions()
    local resolved = ResolveBarColor(custom) or ResolveBarColor(options.barColorRGB) or ResolveBarColor(options.barColor)
    if not resolved then
        local preset = BAR_COLORS.silver
        resolved = { r = preset[1], g = preset[2], b = preset[3] }
    end
    return resolved.r, resolved.g, resolved.b
end

local function IsProfession(name)
    if PROFESSION_NAMES[name] then return true end
    -- Include localized/added professions while excluding weapon and class skills.
    return name and name:match("Profession$") ~= nil
end

local function GetSkillName(info)
    return PROFESSION_SKILL_IDS[info.skillID] or info.name
end

local function GetProfessionSkills()
    local byName = {}
    if not C_SkillInfo or not C_SkillInfo.GetNumSkillLines then return {} end
    for i = 1, C_SkillInfo.GetNumSkillLines() do
        local info = C_SkillInfo.GetSkillLineInfo(i)
        local name = info and GetSkillName(info)
        local cap = info and (info.maxRank or info.maxSkillLevel or 0)
        if info and not info.isHeader and name and (PROFESSION_SKILL_IDS[info.skillID] or IsProfession(info.name)) and cap > 0 then
            local candidate = {
                id = info.skillID,
                name = name,
                rank = info.rank or 0,
                cap = cap,
                tier = RANK_NAMES[cap] or ("Skill tier (" .. cap .. ")"),
            }
            local previous = byName[name]
            if not previous or candidate.cap > previous.cap or
                (candidate.cap == previous.cap and candidate.rank > previous.rank) then
                byName[name] = candidate
            end
        end
    end
    local found = {}
    for _, skill in pairs(byName) do found[#found + 1] = skill end
    table.sort(found, function(a, b) return a.name < b.name end)
    return found
end

ProfessionTracker_GetProfessionSkills = GetProfessionSkills

local function GetFishingStats()
    ProfessionTrackerDB.fishingStats = ProfessionTrackerDB.fishingStats or { samples = {}, catchesSinceSkill = 0 }
    local stats = ProfessionTrackerDB.fishingStats
    stats.samples = stats.samples or {}
    stats.catchesSinceSkill = stats.catchesSinceSkill or 0
    stats.totalCatches = stats.totalCatches or 0
    return stats
end

local function GetFishingCatchesPerPoint(stats)
    local settings = ProfessionTracker_GetProfessionSettings("Fishing")
    if settings.fishingRateMode == "custom" then
        return math.max(1, math.min(100, tonumber(settings.customFishingRate) or 2.5))
    end
    -- Start from the player's reported 2-3 catch range, then adapt to this character's history.
    local total, weight = 5, 2 -- prior average: 2.5 catches per skill point
    for _, sample in ipairs(stats.samples) do
        if sample > 0 and sample < 100 then
            total = total + sample
            weight = weight + 1
        end
    end
    return total / weight
end

function ProfessionTracker_ResetFishingEstimateData()
    local stats = GetFishingStats()
    stats.samples = {}
    stats.catchesSinceSkill = 0
    stats.totalCatches = 0
    stats.lastSkill = nil
    for _, skill in ipairs(GetProfessionSkills()) do
        if skill.name == "Fishing" then stats.lastSkill = skill.rank; break end
    end
    ProfessionTracker_Refresh()
end

local function CaptureFishingSkill()
    if not ProfessionTrackerDB then return end
    local fishing
    for _, skill in ipairs(GetProfessionSkills()) do
        if skill.name == "Fishing" then fishing = skill; break end
    end
    if not fishing then return end

    local stats = GetFishingStats()
    if stats.lastSkill == nil then
        stats.lastSkill = fishing.rank
        return
    end

    local gained = fishing.rank - stats.lastSkill
    if gained > 0 then
        if stats.catchesSinceSkill > 0 then
            local sample = stats.catchesSinceSkill / gained
            if sample > 0 and sample < 100 then
                table.insert(stats.samples, sample)
                while #stats.samples > 10 do table.remove(stats.samples, 1) end
            end
        end
        stats.catchesSinceSkill = 0
    end
    stats.lastSkill = fishing.rank
end

local function CountFishingCatch()
    local now = GetTime()
    if now - lastFishingCatchAt < 1.5 then return end
    lastFishingCatchAt = now
    fishingCastUntil = 0
    local stats = GetFishingStats()
    stats.catchesSinceSkill = stats.catchesSinceSkill + 1
    stats.totalCatches = stats.totalCatches + 1
    ProfessionTracker_Refresh()

    -- Allow the skill line and chat events from this catch to settle before learning its rate.
    C_Timer.After(0.35, function()
        CaptureFishingSkill()
        ProfessionTracker_Refresh()
    end)
end

local function RecordFishingLoot()
    if IsFishingLoot then
        local ok, isFishing = pcall(IsFishingLoot)
        if ok and isFishing then CountFishingCatch(); return end
    end
    -- Some clients do not identify fishing loot through IsFishingLoot(). A recent
    -- player Fishing cast plus the self-loot chat message is a safe fallback.
    if GetTime() <= fishingCastUntil then CountFishingCatch() end
end

local function OnFishingSpellcast(unit, ...)
    if unit ~= "player" then return end
    local args = { ... }
    local spellID = type(args[1]) == "string" and type(args[2]) == "number" and args[2] or nil
    if not spellID then for _, value in ipairs(args) do if type(value) == "number" then spellID = value end end end
    if spellID == 7620 then fishingCastUntil = GetTime() + 60 end
    if ProfessionTracker_RecordGatherSpell and ProfessionTracker_RecordGatherSpell(spellID) then ProfessionTracker_Refresh() end
end

local function OnLootMessage(message)
    if not message or GetTime() > fishingCastUntil then return end
    local selfLoot = _G.LOOT_ITEM_SELF
    local isSelfLoot = type(selfLoot) == "string" and message:find(selfLoot:gsub("%%s", ".+")) ~= nil
    if not isSelfLoot then isSelfLoot = message:find("You receive loot", 1, true) ~= nil end
    if isSelfLoot then CountFishingCatch() end
end

local function DumpSkillLines()
    local lines = {}
    if frame then
        lines[#lines + 1] = ("Tracker: %s, %s, position %s."):format(
            frame:IsShown() and "visible" or "hidden",
            collapsed and "collapsed" or "expanded",
            GetOptions().lockPosition and "locked" or "unlocked")
    else
        lines[#lines + 1] = "Tracker frame has not initialized."
    end
    for _, eventError in ipairs(eventRegistrationErrors) do
        lines[#lines + 1] = "Event registration warning: " .. eventError
    end
    if not C_SkillInfo or not C_SkillInfo.GetNumSkillLines then
        lines[#lines + 1] = "C_SkillInfo is unavailable."
    else
        local count = C_SkillInfo.GetNumSkillLines()
        lines[#lines + 1] = "Found " .. tostring(count) .. " skill lines; recognized " .. #GetProfessionSkills() .. " professions."
        for i = 1, count do
            local info = C_SkillInfo.GetSkillLineInfo(i)
            if info then
                local name = info.name or "?"
                local recognized = PROFESSION_SKILL_IDS[info.skillID] and (" => " .. PROFESSION_SKILL_IDS[info.skillID]) or ""
                lines[#lines + 1] = ("%s [id %s] %s/%s%s%s"):format(name, tostring(info.skillID), tostring(info.rank), tostring(info.maxRank), info.isHeader and " (header)" or "", recognized)
            end
        end
    end
    if ProfessionTrackerDB then
        local stats = GetFishingStats()
        lines[#lines + 1] = ("Fishing tracker: %d total catches; %d since last skill-up; learned rate %.2f catches/skill from %d skill-ups."):format(
            stats.totalCatches, stats.catchesSinceSkill, GetFishingCatchesPerPoint(stats), #stats.samples)
    end
    if ProfessionTracker_GetCraftingDebugLines then
        for _, line in ipairs(ProfessionTracker_GetCraftingDebugLines()) do lines[#lines + 1] = line end
    end
    return lines
end

local debugFrame
local function ShowDebugReport(report)
    if not debugFrame then
        debugFrame = CreateFrame("Frame", "ProfessionTrackerDebugFrame", UIParent, "BackdropTemplate")
        debugFrame:SetSize(560, 390)
        debugFrame:SetPoint("CENTER")
        debugFrame:SetFrameStrata("DIALOG")
        debugFrame:SetMovable(true)
        debugFrame:EnableMouse(true)
        debugFrame:RegisterForDrag("LeftButton")
        debugFrame:SetScript("OnDragStart", debugFrame.StartMoving)
        debugFrame:SetScript("OnDragStop", debugFrame.StopMovingOrSizing)
        MakeBackdrop(debugFrame)

        local title = NewFont(debugFrame, 12, true)
        title:SetPoint("TOPLEFT", 14, -12)
        title:SetText("Profession Tracker Debug Report")

        local hint = debugFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
        hint:SetText("Click the text, press Ctrl+A then Ctrl+C, and paste the report here.")

        local close = CreateFrame("Button", nil, debugFrame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)

        local scroll = CreateFrame("ScrollFrame", nil, debugFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", debugFrame, "TOPLEFT", 12, -56)
        scroll:SetPoint("BOTTOMRIGHT", debugFrame, "BOTTOMRIGHT", -30, 12)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(500)
        edit:SetTextInsets(4, 4, 4, 4)
        edit:SetScript("OnEscapePressed", function() debugFrame:Hide() end)
        scroll:SetScrollChild(edit)
        debugFrame.edit = edit
        debugFrame.scroll = scroll
    end

    local edit = debugFrame.edit
    edit:SetText("Profession Tracker debug report\n" .. table.concat(report, "\n"))
    edit:SetCursorPosition(0)
    edit:SetFocus()
    edit:HighlightText()
    debugFrame:Show()
    C_Timer.After(0, function()
        if not debugFrame:IsShown() then return end
        edit:SetWidth(math.max(1, debugFrame.scroll:GetWidth() - 8))
        edit:SetHeight(math.max(debugFrame.scroll:GetHeight(), (#report + 1) * 16 + 12))
    end)
end

MakeBackdrop = function(target, bg, edge)
    local style = GetResolvedUIStyle()
    if style == "eui" and euiSkin then
        target:SetBackdrop(nil)
        if bg then euiSkin.Panel(target) else euiSkin.Shell(target) end
    elseif style == "modern" then
        local modernBackground = bg and { 0.055, 0.068, 0.088, 0.98 } or { 0.025, 0.035, 0.05, 0.98 }
        local modernBorder = bg and { 0.18, 0.32, 0.48, 1 } or { 0.23, 0.38, 0.54, 1 }
        target:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        target:SetBackdropColor(unpack(modernBackground))
        target:SetBackdropBorderColor(unpack(modernBorder))
    else
        target:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        target:SetBackdropColor(unpack(bg or { 0.025, 0.02, 0.015, 0.94 }))
        target:SetBackdropBorderColor(unpack(edge or { 0.62, 0.38, 0.11, 1 }))
    end
end

local function ApplyEllesmereControls()
    if not frame then return end
    local usingEllesmereSkin = euiSkin and GetResolvedUIStyle() == "eui"
    if frame.headerBackground then
        if usingEllesmereSkin then frame.headerBackground:Show() else frame.headerBackground:Hide() end
    end
    if frame.headerDivider then
        if usingEllesmereSkin then frame.headerDivider:Show() else frame.headerDivider:Hide() end
    end
    if not usingEllesmereSkin then return end
    local ar, ag, ab = euiSkin.GetAccentColor()
    if frame then
        euiSkin.Font(frame.title, ar, ag, ab)
        if frame.collapse then euiSkin.Button(frame.collapse) end
    end
    for _, row in ipairs(rows) do
        MakeBackdrop(row, true)
        if row.title then euiSkin.Font(row.title, ar, ag, ab) end
        if row.value then euiSkin.Font(row.value, 1, 1, 1) end
        if row.detail then euiSkin.Font(row.detail) end
        if row.toggle then euiSkin.Button(row.toggle) end
    end
end

local function RegisterEllesmereSkin()
    if not (EllesmereUI and EllesmereUI.RegisterSkin) then return end
    EllesmereUI.RegisterSkin("ProfessionTracker", function(S)
        euiSkin = S
        if S.OnLooksChanged and not euiLookHooked then
            euiLookHooked = true
            S.OnLooksChanged(function()
                if GetResolvedUIStyle() == "eui" then
                    ProfessionTracker_ApplyOptions()
                    ApplyEllesmereControls()
                end
            end)
        end
        if GetResolvedUIStyle() == "eui" then
            ProfessionTracker_ApplyOptions()
            ApplyEllesmereControls()
        end
    end)
end

NewFont = function(parent, size, outline)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetFont("Fonts\\FRIZQT__.TTF", size, outline and "OUTLINE" or "")
    fs:SetTextColor(unpack(GOLD))
    return fs
end

local function SetRowData(row, data)
    row.data = data
    local options = GetOptions()
    row.title:SetText(options.showTier and (data.name .. "  |  " .. data.tier) or data.name)
    local style = GetResolvedUIStyle()
    if style == "eui" and euiSkin then
        local r, g, b = euiSkin.GetAccentColor()
        row.title:SetTextColor(r, g, b, 1)
    elseif style == "modern" then
        row.title:SetTextColor(0.9, 0.94, 1, 1)
    else
        row.title:SetTextColor(unpack(GOLD))
    end
    local red, green, blue = ProfessionTracker_GetBarColor(data.name)
    row.bar:SetStatusBarColor(red, green, blue, 1)
    row.bar:SetMinMaxValues(0, math.max(1, data.cap))
    row.bar:SetValue(math.min(data.rank, data.cap))
    row.value:SetText(data.rank .. " / " .. data.cap)
    row.value:SetShown(options.showSkillNumbers)
    local remaining = math.max(0, data.cap - data.rank)
    local detailText
    if remaining == 0 then
        detailText = "Current trained cap reached"
    elseif data.name == "Fishing" then
        local stats = GetFishingStats()
        local rate = GetFishingCatchesPerPoint(stats)
        local catchesLeft = math.max(0, math.floor(remaining * rate - stats.catchesSinceSkill + 0.5))
        local settings = ProfessionTracker_GetProfessionSettings(data.name)
        local mode = settings.estimateDetail
        detailText = ("~%d catches to %d"):format(catchesLeft, data.cap)
        if mode == "recommended" then
            detailText = detailText .. (" (%.1f catches/skill)"):format(rate)
        elseif mode == "full" then
            local rateSource = settings.fishingRateMode == "custom" and "custom rate" or "learned rate"
            detailText = detailText .. ("\n%s: %.1f catches/skill; %d since skill-up"):format(rateSource, rate, stats.catchesSinceSkill)
        end
    elseif (data.name == "Herbalism" or data.name == "Mining" or data.name == "Skinning") and ProfessionTracker_GetGatherDetail then
        detailText = ProfessionTracker_GetGatherDetail(data)
    else
        detailText = ProfessionTracker_GetCraftDetail and ProfessionTracker_GetCraftDetail(data) or "Open profession to scan recipes"
    end
    row.detail:SetText(detailText)
    row.detail:SetTextColor(0.84, 0.84, 0.84, 1)
    if expanded[data.name] then row.detail:Show() else row.detail:Hide() end

    local previous = lastSkill[data.name]
    if options.rankUpGlow and previous and (data.rank > previous.rank or data.cap > previous.cap) then
        row.glow:Show()
        row.glow.animation:Stop()
        row.glow.animation:Play()
    end
    lastSkill[data.name] = { rank = data.rank, cap = data.cap }
end

local function LayoutRows(skills)
    for _, row in ipairs(rows) do row:Hide() end
    local reverse = GetOptions().collapseDirection == "bottom"
    local titleAtBottom = GetOptions().titleBarPosition == "bottom"
    local y = -38
    local bottomY = 4
    for i = 1, #skills do
        local data = reverse and not titleAtBottom and skills[#skills - i + 1] or skills[i]
        local row = rows[i]
        if not row then
            row = CreateFrame("Frame", nil, frame.rowsFrame, "BackdropTemplate")
            row:SetPoint("TOPLEFT", frame.rowsFrame, "TOPLEFT", 10, y)
            row:SetPoint("TOPRIGHT", frame.rowsFrame, "TOPRIGHT", -10, y)
            row:SetHeight(48)
            MakeBackdrop(row, { 0.045, 0.038, 0.03, 0.88 }, { 0.25, 0.17, 0.09, 0.9 })

            row.title = NewFont(row, 11, true)
            row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -5)
            row.title:SetJustifyH("LEFT")

            row.bar = CreateFrame("StatusBar", nil, row)
            row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -22)
            row.bar:SetPoint("TOPRIGHT", row, "TOPRIGHT", -36, -22)
            row.bar:SetHeight(13)
            row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
            row.bar:SetMinMaxValues(0, 100)
            row.bar:SetValue(0)
            local barBg = row.bar:CreateTexture(nil, "BACKGROUND")
            barBg:SetAllPoints()
            barBg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
            barBg:SetVertexColor(0.08, 0.07, 0.06, 1)

            row.value = row.bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.value:SetFont("Fonts\\FRIZQT__.TTF", 11, "THICKOUTLINE")
            row.value:SetTextColor(1, 1, 1, 1)
            row.value:SetShadowColor(0, 0, 0, 1)
            row.value:SetShadowOffset(1, -1)
            row.value:SetPoint("CENTER", row.bar, "CENTER", 0, 0)

            row.toggle = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.toggle:SetSize(23, 20)
            row.toggle:SetText("+")
            row.toggle:SetScript("OnClick", function()
                local name = row.data and row.data.name
                if not name then return end
                expanded[name] = not expanded[name] or nil
                ProfessionTrackerDB.expanded = expanded
                ProfessionTracker_Refresh()
            end)

            row.glow = CreateFrame("Frame", nil, row)
            row.glow:SetPoint("TOPLEFT", row, "TOPLEFT", 5, -2)
            row.glow:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -5, 2)
            row.glow:SetFrameLevel(row:GetFrameLevel() + 4)
            row.glow.texture = row.glow:CreateTexture(nil, "OVERLAY")
            row.glow.texture:SetAllPoints()
            row.glow.texture:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
            row.glow.texture:SetBlendMode("ADD")
            row.glow:SetAlpha(0)
            row.glow.animation = row.glow:CreateAnimationGroup()
            local fade = row.glow.animation:CreateAnimation("Alpha")
            fade:SetFromAlpha(0.85)
            fade:SetToAlpha(0)
            fade:SetDuration(1.1)
            row.glow.animation:SetScript("OnFinished", function() row.glow:Hide() end)
            row.glow:Hide()

            row.detail = NewFont(row, 10, false)
            row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -42)
            row.detail:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.detail:SetJustifyH("LEFT")
            row.detail:SetJustifyV("TOP")
            rows[i] = row
            ApplyEllesmereControls()
        end
        row:ClearAllPoints()
        if reverse then
            row:SetPoint("BOTTOMLEFT", frame.rowsFrame, "BOTTOMLEFT", 10, bottomY)
            row:SetPoint("BOTTOMRIGHT", frame.rowsFrame, "BOTTOMRIGHT", -10, bottomY)
        else
            row:SetPoint("TOPLEFT", frame.rowsFrame, "TOPLEFT", 10, y)
            row:SetPoint("TOPRIGHT", frame.rowsFrame, "TOPRIGHT", -10, y)
        end
        local rowHeight = expanded[data.name] and 88 or 48
        row:SetHeight(rowHeight)
        row.title:ClearAllPoints()
        row.bar:ClearAllPoints()
        row.detail:ClearAllPoints()
        if reverse then
            row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -5)
            row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -22)
            row.bar:SetPoint("TOPRIGHT", row, "TOPRIGHT", -36, -22)
            row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -42)
            row.detail:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            bottomY = bottomY + rowHeight + 4
        else
            row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -5)
            row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -22)
            row.bar:SetPoint("TOPRIGHT", row, "TOPRIGHT", -36, -22)
            row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -42)
            row.detail:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            y = y - rowHeight - 4
        end
        row.toggle:ClearAllPoints()
        row.toggle:SetPoint("CENTER", row.bar, "RIGHT", 17, 0)
        row.toggle:SetText(expanded[data.name] and "-" or "+")
        SetRowData(row, data)
        row:SetShown(not collapsed)
    end
    local empty = #skills == 0
    frame.empty:SetShown(empty and not collapsed)
    if collapsed then
        frame:SetHeight(38)
    else
        local contentHeight = empty and 64 or math.max(1, reverse and bottomY + 4 or -y + 4)
        frame.rowsFrame:SetSize(frame:GetWidth(), contentHeight)
        local desiredHeight = empty and 92 or math.max(82, contentHeight + 30)
        local oldHeight = frame:GetHeight()
        local left, top, _, bottom = frame:GetLeft(), frame:GetTop(), frame:GetRight(), frame:GetBottom()
        local screenHeight = UIParent:GetHeight()
        local maxHeight = math.max(120, screenHeight - 96)
        if reverse and bottom then
            maxHeight = math.min(maxHeight, math.max(120, screenHeight - bottom - 16))
        elseif top then
            -- Keep a clear margin above chat when the panel expands downward.
            maxHeight = math.min(maxHeight, math.max(120, top - 96))
        end
        local newHeight = math.min(desiredHeight, maxHeight)
        frame:SetHeight(newHeight)
        if left and math.abs(newHeight - oldHeight) > 0.5 and not bookAnchorActive then
            frame:ClearAllPoints()
            if reverse and bottom then
                frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
            elseif top then
                frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            end
            RememberExpandedPoint()
        end
        local maxScroll = math.max(0, contentHeight - frame.body:GetHeight())
        local scroll = frame.body:GetVerticalScroll() or 0
        if lastRowsReverse ~= reverse then scroll = reverse and maxScroll or 0 end
        frame.body:SetVerticalScroll(math.max(0, math.min(scroll, maxScroll)))
        lastRowsReverse = reverse
    end
end

function ProfessionTracker_Refresh()
    if not frame then return end
    LayoutRows(GetProfessionSkills())
end

function ProfessionTracker_ApplyOptions()
    if frame then
        frame:SetShown(GetOptions().enabled ~= false)
        MakeBackdrop(frame)
        local style = GetResolvedUIStyle()
        if style == "eui" and euiSkin then
            local r, g, b = euiSkin.GetAccentColor()
            frame.title:SetTextColor(r, g, b, 1)
        else
            local modern = style == "modern"
            frame.title:SetTextColor(modern and 0.9 or GOLD[1], modern and 0.94 or GOLD[2], modern and 1 or GOLD[3], 1)
        end
        for _, row in ipairs(rows) do
            MakeBackdrop(row, { 0.045, 0.038, 0.03, 0.88 }, { 0.25, 0.17, 0.09, 0.9 })
        end
        if ApplyCollapsePresentation then ApplyCollapsePresentation() end
        ProfessionTracker_Refresh()
        ApplyEllesmereControls()
    end
end

function ProfessionTracker_IsProfessionExpanded(name)
    return expanded[name] and true or false
end

function ProfessionTracker_SetProfessionExpanded(name, value)
    expanded[name] = value and true or nil
    ProfessionTrackerDB.expanded = expanded
    ProfessionTracker_Refresh()
end

function ProfessionTracker_GetProfessionBarColorOverride(name)
    local colors = ProfessionTrackerDB and ProfessionTrackerDB.professionBarColors
    return colors and colors[name]
end

function ProfessionTracker_SetProfessionBarColor(name, colorKey)
    ProfessionTrackerDB.professionBarColors = ProfessionTrackerDB.professionBarColors or {}
    local color = ResolveBarColor(colorKey)
    if color then
        ProfessionTrackerDB.professionBarColors[name] = color
    else
        ProfessionTrackerDB.professionBarColors[name] = nil
    end
    ProfessionTracker_ApplyOptions()
end

function ProfessionTracker_GetPositionLocked()
    return GetOptions().lockPosition and true or false
end

function ProfessionTracker_SetPositionLocked(value)
    GetOptions().lockPosition = value and true or false
end

local function FindProfessionBook()
    local characterFrame = _G.CharacterFrame
    local characterVisible = characterFrame and characterFrame.IsVisible and characterFrame:IsVisible()
    local skillsTabSelected = false
    if characterVisible then
        local selectedTab = characterFrame.selectedTab
        if PanelTemplates_GetSelectedTab then
            selectedTab = PanelTemplates_GetSelectedTab(characterFrame) or selectedTab
        end
        local skillsTab = _G.CharacterFrameTab4
        skillsTabSelected = selectedTab == 4
            or (skillsTab and skillsTab.GetChecked and skillsTab:GetChecked())
    end

    -- In the Classic character book, Skills is tab 4. The tab click can happen
    -- before SkillFrame reports visible, so use the selected tab as the signal.
    for _, paneName in ipairs({ "SkillFrame", "SkillListFrame" }) do
        local skillPane = _G[paneName]
        if skillPane and skillPane.IsVisible and skillPane:IsVisible() then
            if characterVisible then return characterFrame end
            return skillPane
        end
    end
    if characterVisible and skillsTabSelected then
        return characterFrame
    end

    local candidates = {
        "ProfessionsBookFrame", "ProfessionBookFrame", "SkillBookFrame",
        "ProfessionsFrame", "TradeSkillFrame", "CraftFrame",
    }
    for _, name in ipairs(candidates) do
        local candidate = _G[name]
        if candidate and candidate.IsVisible and candidate:IsVisible() then return candidate end
    end
end

local function AttachToProfessionBook(book)
    if not frame or not frame:IsShown() or not book then return end
    local wasAnchoredToBook = bookAnchorActive and activeProfessionBook == book
    local bookLeft, bookRight = book:GetLeft(), book:GetRight()
    local bookWidth = book:GetWidth() or 0
    if not bookLeft and bookRight then bookLeft = bookRight - bookWidth end
    if not bookRight and bookLeft then bookRight = bookLeft + bookWidth end
    if not bookLeft or not bookRight or bookWidth <= 0 then
        C_Timer.After(0.12, function()
            if book.IsVisible and book:IsVisible() then AttachToProfessionBook(book) end
        end)
        return
    end

    if not bookAnchorActive then
        if not collapsed then RememberExpandedPoint() end
        bookPreviousPoint = expandedPoint or ProfessionTrackerDB.point
        bookPreviousCollapsed = collapsed
        bookPreviousStrata = frame:GetFrameStrata()
        bookPreviousLevel = frame:GetFrameLevel()
        bookAnchorActive = true

        -- Expand while the player is working, then restore the prior state on close.
        collapsed = false
        frame.body:Show()
        ApplyCollapsePresentation()
    end
    activeProfessionBook = book
    if not wasAnchoredToBook then ProfessionTracker_Refresh() end

    -- Leave room for profession-book decorations/icons that can extend beyond
    -- the book frame's reported right edge, especially with UI skin addons.
    local gap = 56
    local screenWidth = UIParent:GetWidth()
    local rightSpace = screenWidth - bookRight
    local leftSpace = bookLeft
    local frameWidth = frame:GetWidth()
    local canFitRight = rightSpace >= frameWidth + gap
    local canFitLeft = leftSpace >= frameWidth + gap
    local dockRight = canFitRight or (not canFitLeft and rightSpace >= leftSpace)

    frame:ClearAllPoints()
    frame:SetFrameStrata(book:GetFrameStrata() or bookPreviousStrata or "MEDIUM")
    frame:SetFrameLevel(math.max(book:GetFrameLevel() + 10, bookPreviousLevel or 0))
    if dockRight then
        frame:SetPoint("LEFT", book, "RIGHT", gap, 0)
    else
        frame:SetPoint("RIGHT", book, "LEFT", -gap, 0)
    end
end

TryAttachToProfessionBook = function(retries)
    local book = FindProfessionBook()
    if book then
        AttachToProfessionBook(book)
    elseif retries > 0 then
        C_Timer.After(0.15, function() TryAttachToProfessionBook(retries - 1) end)
    end
end

local function RestoreAfterProfessionBook()
    if not frame or not bookAnchorActive then return end
    bookAnchorActive = false
    activeProfessionBook = nil
    collapsed = bookPreviousCollapsed and true or false
    ProfessionTrackerDB.collapsed = collapsed
    frame:ClearAllPoints()
    local p = bookPreviousPoint or expandedPoint or { "RIGHT", "RIGHT", -32, 0 }
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    if bookPreviousStrata then frame:SetFrameStrata(bookPreviousStrata) end
    if bookPreviousLevel then frame:SetFrameLevel(bookPreviousLevel) end
    if collapsed then
        for _, row in ipairs(rows) do row:Hide() end
        ApplyCollapsePresentation()
    else
        frame.body:Show()
        ApplyCollapsePresentation()
        ProfessionTracker_Refresh()
    end
    bookPreviousPoint = nil
    bookPreviousCollapsed = nil
    bookPreviousStrata = nil
    bookPreviousLevel = nil
end

MonitorProfessionBook = function()
    if professionBookMonitorRunning then return end
    professionBookMonitorRunning = true
    local function checkBook()
        if not frame or not frame:IsShown() then
            professionBookMonitorRunning = false
            return
        end
        HookProfessionBookFrames()
        local book = FindProfessionBook()
        if book then
            AttachToProfessionBook(book)
        elseif bookAnchorActive then
            RestoreAfterProfessionBook()
        end
        C_Timer.After(0.25, checkBook)
    end
    C_Timer.After(0.1, checkBook)
end

HookProfessionBookFrames = function()
    local names = {
        "ProfessionsBookFrame", "ProfessionBookFrame", "SkillBookFrame",
        "SkillFrame", "SkillListFrame", "CharacterFrame", "CharacterFrameTab4", "ProfessionsFrame",
        "TradeSkillFrame", "CraftFrame",
    }
    for _, name in ipairs(names) do
        local book = _G[name]
        if book and not hookedProfessionBooks[book] and book.HookScript then
            hookedProfessionBooks[book] = true
            book:HookScript("OnShow", function(shownBook)
                if not frame then return end
                C_Timer.After(0, function()
                    HookProfessionBookFrames()
                    TryAttachToProfessionBook(6)
                end)
            end)
            if name == "CharacterFrameTab4" then
                book:HookScript("OnClick", function()
                    C_Timer.After(0, function()
                        HookProfessionBookFrames()
                        TryAttachToProfessionBook(6)
                    end)
                end)
            end
            book:HookScript("OnHide", function()
                C_Timer.After(0.15, function()
                    HookProfessionBookFrames()
                    local visibleBook = FindProfessionBook()
                    if visibleBook then
                        AttachToProfessionBook(visibleBook)
                    elseif bookAnchorActive then
                        RestoreAfterProfessionBook()
                    end
                end)
            end)
        end
    end
end

RememberExpandedPoint = function()
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if point then
        expandedPoint = { point, relativePoint, x, y }
        ProfessionTrackerDB.point = expandedPoint
    end
    local left, top, right, bottom = frame:GetLeft(), frame:GetTop(), frame:GetRight(), frame:GetBottom()
    if left and top and right and bottom then
        expandedBounds = { left = left, top = top, right = right, bottom = bottom }
    end
end

local function AnchorCollapsedAtSelectedEdge(direction)
    if bookAnchorActive then return end
    local bounds = expandedBounds
    if not bounds then
        local left, top, right, bottom = frame:GetLeft(), frame:GetTop(), frame:GetRight(), frame:GetBottom()
        bounds = { left = left or 0, top = top or UIParent:GetHeight(), right = right or 300, bottom = bottom or 0 }
    end
    frame:ClearAllPoints()
    if direction == "bottom" then
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", bounds.left, bounds.bottom)
    else
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", bounds.left, bounds.top)
    end
end

ApplyCollapsePresentation = function()
    if not frame then return end
    local direction = GetOptions().collapseDirection or "top"
    local titleAtBottom = GetOptions().titleBarPosition == "bottom"
    frame.header:ClearAllPoints()
    frame.collapse:ClearAllPoints()
    frame.title:ClearAllPoints()
    if not collapsed then
        frame:SetWidth(300)
        frame.header:SetHeight(28)
        frame.body:ClearAllPoints()
        if titleAtBottom then
            frame.header:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
            frame.header:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
            frame.body:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            frame.body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, -28)
        else
            frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            frame.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
            frame.body:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -28)
            frame.body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        end
        frame.title:SetPoint("LEFT", frame.header, "LEFT", 6, 0)
        frame.title:SetText("Profession Tracker")
        frame.title:Show()
        frame.collapse:SetSize(34, 26)
        frame.collapse:SetPoint("RIGHT", frame.header, "RIGHT", -1, 0)
        frame.collapse:SetText("-")
        frame.collapse.tooltipText = "Hide bars toward the " .. direction .. " edge"
    else
        frame.body:Hide()
        frame:SetHeight(38)
        -- Fill the entire collapsed tab so EUI's outer accent edge cannot show
        -- around the header's sides.
        frame.header:SetHeight(38)
        frame.collapse.tooltipText = "Show profession bars"
        frame:SetSize(300, 38)
        if direction == "top" then
            frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            frame.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        else
            frame.header:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
            frame.header:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        end
        frame.title:SetPoint("LEFT", frame.header, "LEFT", 6, 0)
        frame.title:SetText("Profession Tracker")
        frame.title:Show()
        frame.collapse:SetSize(34, 26)
        frame.collapse:SetPoint("RIGHT", frame.header, "RIGHT", -1, 0)
        frame.collapse:SetText("+")
        AnchorCollapsedAtSelectedEdge(direction)
    end
end

local function ToggleCollapsed()
    collapsed = not collapsed
    ProfessionTrackerDB.collapsed = collapsed
    if collapsed then
        if not bookAnchorActive then RememberExpandedPoint() end
        for _, row in ipairs(rows) do row:Hide() end
        ApplyCollapsePresentation()
    else
        frame.body:Show()
        if not bookAnchorActive then
            frame:ClearAllPoints()
            local p = expandedPoint or ProfessionTrackerDB.point or { "RIGHT", "RIGHT", -32, 0 }
            frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        end
        ApplyCollapsePresentation()
        ProfessionTracker_Refresh()
    end
end

local function CreateTracker()
    frame = CreateFrame("Frame", "ProfessionTrackerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(300, 110)
    frame:SetPoint("RIGHT", UIParent, "RIGHT", -32, 0)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    MakeBackdrop(frame)

    frame.header = CreateFrame("Frame", nil, frame)
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -5)
    frame.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -5)
    frame.header:SetHeight(25)
    frame.header:SetFrameLevel(frame:GetFrameLevel() + 2)
    frame.header:EnableMouse(true)
    frame.headerBackground = frame.header:CreateTexture(nil, "BACKGROUND")
    frame.headerBackground:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.headerBackground:SetAllPoints(frame.header)
    frame.headerBackground:SetVertexColor(0.018, 0.018, 0.022, 1)
    frame.headerBackground:Hide()
    frame.headerDivider = frame.header:CreateTexture(nil, "BORDER")
    frame.headerDivider:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.headerDivider:SetPoint("BOTTOMLEFT", frame.header, "BOTTOMLEFT", 0, 0)
    frame.headerDivider:SetPoint("BOTTOMRIGHT", frame.header, "BOTTOMRIGHT", 0, 0)
    frame.headerDivider:SetHeight(1)
    frame.headerDivider:SetVertexColor(0.18, 0.18, 0.2, 1)
    frame.headerDivider:Hide()
    frame.header:RegisterForDrag("LeftButton")
    frame.header:SetScript("OnDragStart", function()
        if bookAnchorActive and not FindProfessionBook() then RestoreAfterProfessionBook() end
        if GetOptions().lockPosition then
            print("|cffffd200Profession Tracker:|r Position is locked. Use /pt unlock to move it.")
        elseif bookAnchorActive then
            print("|cffffd200Profession Tracker:|r Tracker is docked beside the open profession book.")
        else
            frame:StartMoving()
        end
    end)
    frame.header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if not collapsed and not bookAnchorActive then RememberExpandedPoint() end
    end)
    frame.header:SetScript("OnEnter", function()
        GameTooltip:SetOwner(frame.header, "ANCHOR_TOP")
        GameTooltip:SetText(GetOptions().lockPosition and "Position locked" or "Drag this title bar to move the tracker")
        GameTooltip:Show()
    end)
    frame.header:SetScript("OnLeave", GameTooltip_Hide)

    frame.title = NewFont(frame.header, 12, true)
    frame.title:SetPoint("LEFT", frame.header, "LEFT", 6, 0)
    frame.title:SetText("Profession Tracker")

    frame.collapse = CreateFrame("Button", nil, frame.header, "UIPanelButtonTemplate")
    frame.collapse:SetSize(24, 20)
    frame.collapse:SetPoint("RIGHT", frame.header, "RIGHT", -1, 0)
    frame.collapse:SetText("-")
    frame.collapse:SetScript("OnClick", ToggleCollapsed)
    frame.collapse:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.tooltipText or "Collapse profession bars")
        GameTooltip:Show()
    end)
    frame.collapse:SetScript("OnLeave", GameTooltip_Hide)

    frame.body = CreateFrame("ScrollFrame", nil, frame)
    frame.body:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -28)
    frame.body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.body:EnableMouseWheel(true)
    frame.body:SetScript("OnMouseWheel", function(self, delta)
        local child = self:GetScrollChild()
        local maxScroll = child and math.max(0, child:GetHeight() - self:GetHeight()) or 0
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 36)))
    end)
    frame.rowsFrame = CreateFrame("Frame", nil, frame.body)
    frame.rowsFrame:SetSize(280, 1)
    frame.body:SetScrollChild(frame.rowsFrame)
    frame.empty = NewFont(frame.body, 11, false)
    frame.empty:SetPoint("TOPLEFT", frame.body, "TOPLEFT", 14, -10)
    frame.empty:SetPoint("RIGHT", frame.body, "RIGHT", -14, 0)
    frame.empty:SetJustifyH("LEFT")
    frame.empty:SetText("No learned professions found.")
    frame:SetScript("OnShow", function()
        HookProfessionBookFrames()
        TryAttachToProfessionBook(6)
        MonitorProfessionBook()
    end)

    if ProfessionTrackerDB.point then
        local p = ProfessionTrackerDB.point
        frame:ClearAllPoints()
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        expandedPoint = p
    else
        expandedPoint = { "RIGHT", "RIGHT", -32, 0 }
    end
    local style = GetResolvedUIStyle()
    if style == "eui" and euiSkin then
        local r, g, b = euiSkin.GetAccentColor()
        frame.title:SetTextColor(r, g, b, 1)
    else
        local modern = style == "modern"
        frame.title:SetTextColor(modern and 0.9 or GOLD[1], modern and 0.94 or GOLD[2], modern and 1 or GOLD[3], 1)
    end
    ApplyCollapsePresentation()
    ProfessionTracker_Refresh()
    ApplyEllesmereControls()
    RememberExpandedPoint()
    if GetOptions().enabled == false then frame:Hide() end
end

local eventFrame = CreateFrame("Frame")
RegisterEllesmereSkin()
local function SafeRegisterEvent(event)
    local ok, err = pcall(eventFrame.RegisterEvent, eventFrame, event)
    if not ok then eventRegistrationErrors[#eventRegistrationErrors + 1] = event .. ": " .. tostring(err) end
end
SafeRegisterEvent("PLAYER_LOGIN")
SafeRegisterEvent("ADDON_LOADED")
SafeRegisterEvent("PLAYER_ENTERING_WORLD")
SafeRegisterEvent("SKILL_LINES_CHANGED")
SafeRegisterEvent("CHAT_MSG_SKILL")
SafeRegisterEvent("LOOT_OPENED")
SafeRegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
SafeRegisterEvent("CHAT_MSG_LOOT")
SafeRegisterEvent("TRADE_SKILL_SHOW")
SafeRegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
SafeRegisterEvent("TRADE_SKILL_CLOSE")
SafeRegisterEvent("CRAFT_SHOW")
SafeRegisterEvent("CRAFT_CLOSE")
SafeRegisterEvent("TRADE_SKILL_CRAFT_BEGIN")
SafeRegisterEvent("NEW_RECIPE_LEARNED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        HookProfessionBookFrames()
    elseif event == "PLAYER_LOGIN" then
        ProfessionTrackerDB = ProfessionTrackerDB or {}
        expanded = ProfessionTrackerDB.expanded or {}
        local startCollapsed = ProfessionTrackerDB.collapsed or false
        collapsed = false
        GetFishingStats()
        if ProfessionTracker_CraftingInit then ProfessionTracker_CraftingInit() end
        CreateTracker()
        HookProfessionBookFrames()
        TryAttachToProfessionBook(6)
        MonitorProfessionBook()
        CaptureFishingSkill()
        if ProfessionTracker_CaptureGatherSkillups then ProfessionTracker_CaptureGatherSkillups() end
        if startCollapsed then ToggleCollapsed() end
    elseif event == "LOOT_OPENED" then
        RecordFishingLoot()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnFishingSpellcast(...)
    elseif event == "CHAT_MSG_LOOT" then
        OnLootMessage(...)
    elseif event == "TRADE_SKILL_CRAFT_BEGIN" then
        local recipeID = ...
        if ProfessionTracker_RecordCraft then ProfessionTracker_RecordCraft(recipeID) end
        ProfessionTracker_Refresh()
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" or event == "CRAFT_SHOW" then
        HookProfessionBookFrames()
        if event == "TRADE_SKILL_SHOW" or event == "CRAFT_SHOW" then TryAttachToProfessionBook(6) end
        MonitorProfessionBook()
        if ProfessionTracker_CraftingSetOpen then ProfessionTracker_CraftingSetOpen(true) end
        C_Timer.After(0.6, function()
            if ProfessionTracker_ScanCraftRecipes then ProfessionTracker_ScanCraftRecipes() end
            ProfessionTracker_Refresh()
        end)
    elseif event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE" then
        local book = FindProfessionBook()
        if book then AttachToProfessionBook(book) else RestoreAfterProfessionBook() end
        if ProfessionTracker_CraftingSetOpen then ProfessionTracker_CraftingSetOpen(false) end
    elseif event == "NEW_RECIPE_LEARNED" then
        C_Timer.After(0.5, function()
            if ProfessionTracker_ScanCraftRecipes then ProfessionTracker_ScanCraftRecipes() end
            ProfessionTracker_Refresh()
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        HookProfessionBookFrames()
        TryAttachToProfessionBook(2)
        C_Timer.After(0.5, function()
            CaptureFishingSkill()
            if ProfessionTracker_CaptureGatherSkillups then ProfessionTracker_CaptureGatherSkillups() end
            if ProfessionTracker_CaptureCraftSkillups then ProfessionTracker_CaptureCraftSkillups() end
            ProfessionTracker_Refresh()
        end)
    elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
        C_Timer.After(0.75, function()
            CaptureFishingSkill()
            if ProfessionTracker_CaptureGatherSkillups then ProfessionTracker_CaptureGatherSkillups() end
            if ProfessionTracker_CaptureCraftSkillups then ProfessionTracker_CaptureCraftSkillups() end
            if ProfessionTracker_CraftingIsOpen and ProfessionTracker_CraftingIsOpen() and ProfessionTracker_ScanCraftRecipes then
                ProfessionTracker_ScanCraftRecipes()
            end
            ProfessionTracker_Refresh()
        end)
    elseif frame then
        ProfessionTracker_Refresh()
    end
end)
SLASH_PROFESSIONTRACKER1 = "/pt"
SLASH_PROFESSIONTRACKER2 = "/professiontracker"
SlashCmdList.PROFESSIONTRACKER = function(message)
    message = (message or ""):lower()
    if message == "" or message == "options" then
        if ProfessionTracker_OpenOptions then ProfessionTracker_OpenOptions() end
    elseif message == "hide" then frame:Hide()
    elseif message == "show" or message == "expand" then
        GetOptions().enabled = true
        if collapsed then ToggleCollapsed() end
        frame:Show()
    elseif message == "toggle" then frame:SetShown(not frame:IsShown())
    elseif message == "collapse" then if not collapsed then ToggleCollapsed() end
    elseif message == "lock" then
        ProfessionTracker_SetPositionLocked(true)
        print("|cffffd200Profession Tracker:|r Position locked.")
    elseif message == "unlock" then
        ProfessionTracker_SetPositionLocked(false)
        print("|cffffd200Profession Tracker:|r Position unlocked.")
    elseif message == "debug" then ShowDebugReport(DumpSkillLines())
    else print("|cffffd200Profession Tracker:|r /pt show, /pt hide, /pt toggle, /pt collapse, /pt expand, /pt lock, /pt unlock, /pt options, /pt debug") end
end











