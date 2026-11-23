local ADDON_NAME = ...
local ALL_PROFESSIONS = {
    "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering",
    "First Aid", "Fishing", "Herbalism", "Leatherworking", "Lockpicking",
    "Mining", "Poisons", "Skinning", "Tailoring",
}

local rootCategory
local uiCategory
local professionCategories = {}
local registeredProfessionNames = {}
local rootPanel

local function Options()
    if ProfessionTracker_GetOptions then return ProfessionTracker_GetOptions() end
    ProfessionTrackerDB.options = ProfessionTrackerDB.options or {}
    return ProfessionTrackerDB.options
end

local function Changed()
    if ProfessionTracker_ApplyOptions then ProfessionTracker_ApplyOptions() end
end

local function GetCurrentColor(name)
    if ProfessionTracker_GetBarColor then
        local r, g, b = ProfessionTracker_GetBarColor(name)
        return r, g, b
    end
    return 0.78, 0.82, 0.9
end

local function CopyColor(r, g, b)
    return { r = r, g = g, b = b }
end

local function OpenColorPicker(initialColor, callback)
    local startColor = CopyColor(initialColor.r, initialColor.g, initialColor.b)
    local function ApplyColor()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        callback(CopyColor(r, g, b))
    end
    local function CancelColor()
        callback(startColor)
    end

    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = startColor.r,
            g = startColor.g,
            b = startColor.b,
            hasOpacity = false,
            swatchFunc = ApplyColor,
            cancelFunc = CancelColor,
        })
    else
        -- Compatibility with older ColorPickerFrame implementations.
        ColorPickerFrame.func = ApplyColor
        ColorPickerFrame.cancelFunc = CancelColor
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame:SetColorRGB(startColor.r, startColor.g, startColor.b)
        ColorPickerFrame:Show()
    end
end

local function CreateColorButton(parent, anchor, point, relativePoint, x, y, initialColor, onChange, label)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(150, 28)
    button:SetPoint(point, anchor, relativePoint, x or 0, y or 0)
    button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER")
    text:SetText(label or "Choose color")
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    button.label = text
    button.SetColor = function(self, color, enabled)
        self:SetBackdropColor(color.r, color.g, color.b, 1)
        self:SetEnabled(enabled ~= false)
        self:SetAlpha(enabled == false and 0.45 or 1)
    end
    button:SetScript("OnClick", function()
        local color = initialColor()
        OpenColorPicker(color, function(selected)
            onChange(selected)
            button:SetColor(selected, true)
        end)
    end)
    button:SetColor(initialColor(), true)
    return button
end

local function MakePanel(titleText, description)
    local panel = CreateFrame("Frame", nil, UIParent)
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(titleText)

    local intro = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    intro:SetText(description)
    intro:SetJustifyH("LEFT")
    return panel, intro
end

local function AddCheckbox(panel, anchor, key, label, y)
    local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -4, y)
    check:SetSize(26, 26)
    check.label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    check.label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    check.label:SetText(label)
    check.key = key
    check:SetScript("OnClick", function(self)
        Options()[self.key] = self:GetChecked() and true or false
        Changed()
    end)
    return check
end

local function CreateRootPanel()
    local panel, intro = MakePanel("Profession Tracker", "General settings and credits for this character's tracker.")
    panel.name = "Profession Tracker"

    panel.checkEnabled = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    panel.checkEnabled:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", -4, -14)
    panel.checkEnabled:SetSize(26, 26)
    local enabledLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    enabledLabel:SetPoint("LEFT", panel.checkEnabled, "RIGHT", 4, 0)
    enabledLabel:SetText("Enable Profession Tracker")
    panel.checkEnabled:SetScript("OnClick", function(self)
        Options().enabled = self:GetChecked() and true or false
        Changed()
    end)

    panel.version = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    panel.version:SetPoint("TOPLEFT", panel.checkEnabled, "BOTTOMLEFT", 6, -10)

    local creditsTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    creditsTitle:SetPoint("TOPLEFT", panel.version, "BOTTOMLEFT", 0, -22)
    creditsTitle:SetText("Credits and integrations")
    panel.credits = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    panel.credits:SetPoint("TOPLEFT", creditsTitle, "BOTTOMLEFT", 0, -8)
    panel.credits:SetWidth(520)
    panel.credits:SetJustifyH("LEFT")
    panel.credits:SetSpacing(5)
    panel.credits:SetText(
        "Auctionator — Auction House pricing API used for material cost estimates. Auctionator must be installed and have current price data for those estimates.\n\n" ..
        "WoW-Professions.com — source for the bundled WoW Forever profession leveling recommendations. Guide steps are stored in the addon and are not fetched live.\n\n" ..
        "EllesmereUI and EllesmereUI Blizzard Skins — optional panel style integration. The tracker also detects several other UI suites for its Modern style.\n\n" ..
        "Blizzard WoW APIs and UI assets — profession skill data, skill-up events, and the default in-game visual style."
    )

    function panel:Refresh()
        self.checkEnabled:SetChecked(Options().enabled ~= false)
        local version
        if C_AddOns and C_AddOns.GetAddOnMetadata then
            version = C_AddOns.GetAddOnMetadata(ADDON_NAME or "ProfessionTracker", "Version")
        elseif GetAddOnMetadata then
            version = GetAddOnMetadata(ADDON_NAME or "ProfessionTracker", "Version")
        end
        self.version:SetText("Version " .. tostring(version or "unknown"))
    end
    panel:SetScript("OnShow", panel.Refresh)
    return panel
end

local function CreateAppearancePanel()
    local panel, intro = MakePanel("UI Appearance", "Customize the tracker style, bar colors, and collapse behavior. Settings are saved for this character.")
    panel.name = "UI Appearance"

    local colorLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    colorLabel:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -24)
    colorLabel:SetText("Default bar color (profession colors can override this)")

    panel.colorButton = CreateColorButton(panel, colorLabel, "TOPLEFT", "BOTTOMLEFT", 0, -12, function()
        local r, g, b = GetCurrentColor()
        return CopyColor(r, g, b)
    end, function(color)
        Options().barColorRGB = color
        Changed()
        if panel.Refresh then panel:Refresh() end
    end, "Choose default color")

    local styleLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    styleLabel:SetPoint("TOPLEFT", panel.colorButton, "BOTTOMLEFT", 0, -20)
    styleLabel:SetText("Panel style")
    panel.styleDropdown = CreateFrame("Frame", "ProfessionTrackerStyleDropdown", panel, "UIDropDownMenuTemplate")
    panel.styleDropdown:SetPoint("TOPLEFT", styleLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(panel.styleDropdown, 190)
    local styleChoices = {
        { "auto", "Automatic (match detected UI)" },
        { "ellesmere", "EllesmereUI (follow its theme)" },
        { "classic", "Classic WoW" },
        { "modern", "Modern" },
    }
    local function StyleText(key)
        for _, choice in ipairs(styleChoices) do
            if choice[1] == key then return choice[2] end
        end
        return styleChoices[1][2]
    end
    UIDropDownMenu_Initialize(panel.styleDropdown, function(_, level)
        for _, choice in ipairs(styleChoices) do
            local styleKey, styleName = choice[1], choice[2]
            local info = UIDropDownMenu_CreateInfo()
            info.text = styleName
            info.checked = (Options().uiStyle or "auto") == styleKey
            info.func = function()
                local options = Options()
                options.uiStyle = styleKey
                options.uiStyleModeSet = true
                UIDropDownMenu_SetText(panel.styleDropdown, StyleText(styleKey))
                Changed()
                if panel.Refresh then panel:Refresh() end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    panel.styleHelp = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    panel.styleHelp:SetPoint("TOPLEFT", panel.styleDropdown, "BOTTOMLEFT", 16, -2)
    panel.styleHelp:SetText("Automatic follows EllesmereUI when its third-party skin is enabled; otherwise it uses Classic WoW or a clean modern look for detected UI suites. The EllesmereUI style follows its theme, font, and accent color.")
    panel.styleHelp:SetWidth(430)
    panel.styleHelp:SetJustifyH("LEFT")

    local directionLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    directionLabel:SetPoint("TOPLEFT", panel.styleHelp, "BOTTOMLEFT", 0, -16)
    directionLabel:SetText("Collapse direction")
    local directionHelp = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    directionHelp:SetPoint("TOPLEFT", directionLabel, "BOTTOMLEFT", 0, -4)
    directionHelp:SetText("Choose which edge stays visible. The collapsed tab stays at that edge's current screen position.")
    local directions = { { "top", "Top" }, { "bottom", "Bottom" } }
    panel.directionDropdown = CreateFrame("Frame", "ProfessionTrackerCollapseDirectionDropdown", panel, "UIDropDownMenuTemplate")
    panel.directionDropdown:SetPoint("TOPLEFT", directionHelp, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(panel.directionDropdown, 190)
    local function DirectionText(key)
        for _, choice in ipairs(directions) do
            if choice[1] == key then return choice[2] end
        end
        return "Top"
    end
    UIDropDownMenu_Initialize(panel.directionDropdown, function(_, level)
        for _, choice in ipairs(directions) do
            local directionKey, directionName = choice[1], choice[2]
            local info = UIDropDownMenu_CreateInfo()
            info.text = directionName
            info.checked = (Options().collapseDirection or "top") == directionKey
            info.func = function()
                Options().collapseDirection = directionKey
                UIDropDownMenu_SetText(panel.directionDropdown, directionName)
                Changed()
                if panel.Refresh then panel:Refresh() end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local titlePositionLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    titlePositionLabel:SetPoint("TOPLEFT", panel.directionDropdown, "BOTTOMLEFT", 16, -20)
    titlePositionLabel:SetText("Title bar position")
    panel.titlePositionDropdown = CreateFrame("Frame", "ProfessionTrackerTitlePositionDropdown", panel, "UIDropDownMenuTemplate")
    panel.titlePositionDropdown:SetPoint("TOPLEFT", titlePositionLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(panel.titlePositionDropdown, 190)
    local titlePositionChoices = { { "top", "Top" }, { "bottom", "Bottom" } }
    local function TitlePositionText(key)
        for _, choice in ipairs(titlePositionChoices) do
            if choice[1] == key then return choice[2] end
        end
        return "Top"
    end
    UIDropDownMenu_Initialize(panel.titlePositionDropdown, function(_, level)
        for _, choice in ipairs(titlePositionChoices) do
            local positionKey, positionLabel = choice[1], choice[2]
            local info = UIDropDownMenu_CreateInfo()
            info.text = positionLabel
            info.checked = (Options().titleBarPosition or "top") == positionKey
            info.func = function()
                Options().titleBarPosition = positionKey
                UIDropDownMenu_SetText(panel.titlePositionDropdown, positionLabel)
                Changed()
                if panel.Refresh then panel:Refresh() end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    panel.titlePositionHelp = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    panel.titlePositionHelp:SetPoint("TOPLEFT", panel.titlePositionDropdown, "BOTTOMLEFT", 16, -2)
    panel.titlePositionHelp:SetText("Applies while the tracker is expanded; the collapsed tab stays at the selected edge.")
    panel.titlePositionHelp:SetWidth(430)
    panel.titlePositionHelp:SetJustifyH("LEFT")

    local displayLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    displayLabel:SetPoint("TOPLEFT", panel.titlePositionHelp, "BOTTOMLEFT", 0, -16)
    displayLabel:SetText("Display")
    panel.checkTier = AddCheckbox(panel, displayLabel, "showTier", "Show profession tier name", -4)
    panel.checkNumbers = AddCheckbox(panel, displayLabel, "showSkillNumbers", "Show current skill numbers on the bars", -34)
    panel.checkGlow = AddCheckbox(panel, displayLabel, "rankUpGlow", "Show rank-up animation", -64)
    panel.checkLock = AddCheckbox(panel, displayLabel, "lockPosition", "Lock tracker position (disable dragging)", -94)

    panel.reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.reset:SetSize(130, 24)
    panel.reset:SetPoint("TOPLEFT", panel.checkLock, "BOTTOMLEFT", 4, -12)
    panel.reset:SetText("Reset defaults")
    panel.reset:SetScript("OnClick", function()
        local options = Options()
        options.barColor = "silver"
        options.barColorRGB = nil
        options.uiStyle = "auto"
        options.uiStyleModeSet = true
        options.collapseDirection = "top"
        options.titleBarPosition = "top"
        options.showTier = true
        options.showSkillNumbers = true
        options.rankUpGlow = true
        options.lockPosition = false
        Changed()
        panel:Refresh()
    end)

    function panel:Refresh()
        local options = Options()
        self.checkTier:SetChecked(options.showTier ~= false)
        self.checkNumbers:SetChecked(options.showSkillNumbers ~= false)
        self.checkGlow:SetChecked(options.rankUpGlow ~= false)
        self.checkLock:SetChecked(options.lockPosition and true or false)
        local r, g, b = GetCurrentColor()
        self.colorButton:SetColor(CopyColor(r, g, b), true)
        UIDropDownMenu_SetText(self.styleDropdown, StyleText(options.uiStyle or "auto"))
        UIDropDownMenu_SetText(self.directionDropdown, DirectionText(options.collapseDirection or "top"))
        UIDropDownMenu_SetText(self.titlePositionDropdown, TitlePositionText(options.titleBarPosition or "top"))
    end
    panel:SetScript("OnShow", panel.Refresh)
    return panel
end

local function CreateProfessionPanel(name)
    local panel, intro = MakePanel(name, "Profession-specific display options for this character.")
    panel.name = name
    local professionOptions = function()
        if ProfessionTracker_GetProfessionSettings then return ProfessionTracker_GetProfessionSettings(name) end
        Options().professionSettings = Options().professionSettings or {}
        Options().professionSettings[name] = Options().professionSettings[name] or {}
        return Options().professionSettings[name]
    end
    local setOption = function(key, value)
        if ProfessionTracker_SetProfessionSetting then
            ProfessionTracker_SetProfessionSetting(name, key, value)
        else
            professionOptions()[key] = value
            Changed()
        end
        if panel.Refresh then panel:Refresh() end
    end
    local function AddDropdown(labelText, anchor, choices, getValue, onSelect)
        local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
        label:SetText(labelText)
        local dropdown = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
        dropdown:SetPoint("TOPLEFT", label, "BOTTOMLEFT", -16, -2)
        UIDropDownMenu_SetWidth(dropdown, 220)
        UIDropDownMenu_Initialize(dropdown, function(_, level)
            for _, choice in ipairs(choices()) do
                local value, text = choice[1], choice[2]
                local info = UIDropDownMenu_CreateInfo()
                info.text = text
                info.checked = getValue() == value
                info.func = function()
                    onSelect(value)
                    UIDropDownMenu_SetText(dropdown, text)
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        dropdown.SetCurrentText = function(self)
            for _, choice in ipairs(choices()) do
                if choice[1] == getValue() then
                    UIDropDownMenu_SetText(self, choice[2])
                    return
                end
            end
            UIDropDownMenu_SetText(self, choices()[1][2])
        end
        return label, dropdown
    end

    local labelTop = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    labelTop:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -24)
    labelTop:SetText("Estimate display")
    panel.showEstimate = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    panel.showEstimate:SetPoint("TOPLEFT", labelTop, "BOTTOMLEFT", -4, -4)
    panel.showEstimate:SetSize(26, 26)
    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", panel.showEstimate, "RIGHT", 4, 0)
    label:SetText("Show estimate under this profession's bar")
    panel.showEstimate:SetScript("OnClick", function(self)
        if ProfessionTracker_SetProfessionExpanded then
            ProfessionTracker_SetProfessionExpanded(name, self:GetChecked())
        end
    end)

    local gathering = name == "Fishing" or name == "Herbalism" or name == "Mining" or name == "Skinning"
    local detailChoices = name == "Fishing" and {
        { "count", "Catch count only" },
        { "recommended", "Count and catch rate" },
        { "full", "Full catch details" },
    } or gathering and {
        { "count", "Action count only" },
        { "recommended", "Count and estimated rate" },
        { "full", "Full gathering details" },
    } or {
        { "count", "Craft count only" },
        { "recommended", "Count and suggested item" },
        { "full", "Full item and cost details" },
    }
    local _, detailDropdown = AddDropdown("Estimate detail", panel.showEstimate, function() return detailChoices end,
        function() return professionOptions().estimateDetail or "full" end,
        function(value) setOption("estimateDetail", value) end)
    panel.detailDropdown = detailDropdown

    if gathering then
        local rateChoices = { { "learn", "Learn from this character (Default)" }, { "custom", "Use a custom rate" } }
        local rateLabel, rateDropdown = AddDropdown(name .. " estimate rate", detailDropdown, function() return rateChoices end,
            function() return professionOptions().gatherRateMode or (professionOptions().fishingRateMode == "custom" and "custom" or "learn") end,
            function(value)
                setOption("gatherRateMode", value)
                if name == "Fishing" then setOption("fishingRateMode", value) end
            end)
        panel.gatherRateDropdown = rateDropdown
        panel.gatherRateLabel = rateLabel
        panel.customRate = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        panel.customRate:SetSize(72, 24)
        panel.customRate:SetPoint("TOPLEFT", rateDropdown, "BOTTOMLEFT", 18, -8)
        panel.customRate:SetAutoFocus(false)
        panel.customRate:SetMaxLetters(5)
        panel.customRate:SetNumeric(false)
        panel.customRate:SetTextInsets(5, 5, 0, 0)
        local rateHelp = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        rateHelp:SetPoint("LEFT", panel.customRate, "RIGHT", 8, 0)
        rateHelp:SetText((name == "Fishing" and "catches" or "gathering actions") .. " per skill point")
        panel.customRateHelp = rateHelp
        local function SaveCustomRate()
            local rateText = (panel.customRate:GetText() or ""):gsub(",", ".")
            local rate = tonumber(rateText)
            if rate then
                rate = math.max(1, math.min(100, rate))
                if name == "Fishing" then
                    setOption("customFishingRate", rate)
                else
                    setOption("customGatherRate", rate)
                end
                panel.customRate:SetText(tostring(rate))
            else
                panel.customRate:SetText(tostring(professionOptions().customGatherRate or professionOptions().customFishingRate or 2.5))
            end
            panel.customRate:ClearFocus()
        end
        panel.customRate:SetScript("OnEnterPressed", SaveCustomRate)
        panel.customRate:SetScript("OnEditFocusLost", SaveCustomRate)
    else
        local source = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        source:SetPoint("TOPLEFT", detailDropdown, "BOTTOMLEFT", 16, -2)
        source:SetWidth(440)
        source:SetJustifyH("LEFT")
        local guideKey = name == "First Aid" and "FirstAid" or name
        if ProfessionTrackerGuideData and ProfessionTrackerGuideData[guideKey] then
            source:SetText("Guide source: WoW-Professions.com/forever. The current skill-range recommendation and learn prompt appear under this profession's bar.")
        else
            source:SetText("Reference: WoW-Professions.com/forever. This route is not bundled yet; the tracker uses scanned learned recipes when available.")
        end
        panel.guideCredit = source
    end

    local colorTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    local colorAnchor = panel.customRateHelp or panel.guideCredit or panel.detailDropdown
    colorTitle:SetPoint("TOPLEFT", colorAnchor, "BOTTOMLEFT", 16, -18)
    colorTitle:SetText("Profession bar color")

    panel.useGlobalColor = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    panel.useGlobalColor:SetPoint("TOPLEFT", colorTitle, "BOTTOMLEFT", -4, -4)
    panel.useGlobalColor:SetSize(26, 26)
    local globalLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    globalLabel:SetPoint("LEFT", panel.useGlobalColor, "RIGHT", 4, 0)
    globalLabel:SetText("Use UI Appearance default color")

    panel.colorButton = CreateColorButton(panel, panel.useGlobalColor, "TOPLEFT", "BOTTOMLEFT", 4, -4, function()
        local r, g, b = GetCurrentColor(name)
        return CopyColor(r, g, b)
    end, function(color)
        if ProfessionTracker_SetProfessionBarColor then
            ProfessionTracker_SetProfessionBarColor(name, color)
        end
        if panel.Refresh then panel:Refresh() end
    end, "Choose profession color")

    panel.useGlobalColor:SetScript("OnClick", function(self)
        if ProfessionTracker_SetProfessionBarColor then
            if self:GetChecked() then
                ProfessionTracker_SetProfessionBarColor(name, nil)
            else
                local r, g, b = GetCurrentColor()
                ProfessionTracker_SetProfessionBarColor(name, CopyColor(r, g, b))
            end
        end
        if panel.Refresh then panel:Refresh() end
    end)

    panel.resetEstimate = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.resetEstimate:SetSize(190, 24)
    panel.resetEstimate:SetPoint("TOPLEFT", panel.colorButton, "BOTTOMLEFT", 0, -20)
    panel.resetEstimate:SetText("Reset learned estimate data")
    panel.resetEstimate:SetScript("OnClick", function()
        if name == "Fishing" then
            if ProfessionTracker_ResetFishingEstimateData then ProfessionTracker_ResetFishingEstimateData() end
        elseif gathering then
            if ProfessionTracker_ResetGatherEstimateData then ProfessionTracker_ResetGatherEstimateData(name) end
        elseif ProfessionTracker_ResetCraftEstimateData then
            ProfessionTracker_ResetCraftEstimateData(name)
        end
        if panel.Refresh then panel:Refresh() end
    end)

    panel:SetScript("OnShow", function(self)
        if ProfessionTracker_IsProfessionExpanded then
            self.showEstimate:SetChecked(ProfessionTracker_IsProfessionExpanded(name))
        end
        if self.Refresh then self:Refresh() end
    end)
    function panel:Refresh()
        local settings = professionOptions()
        local override = ProfessionTracker_GetProfessionBarColorOverride and ProfessionTracker_GetProfessionBarColorOverride(name)
        self.useGlobalColor:SetChecked(not override)
        local r, g, b = GetCurrentColor(name)
        self.colorButton:SetColor(CopyColor(r, g, b), override ~= nil)
        self.detailDropdown:SetCurrentText()
        if self.recipeDropdown then self.recipeDropdown:SetCurrentText() end
        if self.gatherRateDropdown then
            self.gatherRateDropdown:SetCurrentText()
            local custom = (settings.gatherRateMode or settings.fishingRateMode) == "custom"
            self.customRate:SetShown(custom)
            self.customRateHelp:SetShown(custom)
            self.customRate:SetText(tostring(settings.customGatherRate or settings.customFishingRate or 2.5))
        end
    end
    return panel
end

local function RegisterSubcategory(parent, panel, name)
    panel.name = name
    if Settings and Settings.RegisterCanvasLayoutSubcategory then
        return Settings.RegisterCanvasLayoutSubcategory(parent, panel, name)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        return panel
    end
end

local function EnsureProfessionPages()
    if not rootCategory then return end
    local names = {}
    for _, name in ipairs(ALL_PROFESSIONS) do names[name] = true end
    if ProfessionTracker_GetProfessionSkills then
        for _, skill in ipairs(ProfessionTracker_GetProfessionSkills()) do names[skill.name] = true end
    end
    local sortedNames = {}
    for name in pairs(names) do sortedNames[#sortedNames + 1] = name end
    table.sort(sortedNames)
    for _, name in ipairs(sortedNames) do
        if not registeredProfessionNames[name] then
            local panel = CreateProfessionPanel(name)
            professionCategories[name] = RegisterSubcategory(rootCategory, panel, name)
            registeredProfessionNames[name] = true
        end
    end
end

local function RegisterPages()
    if rootCategory then return end
    rootPanel = CreateRootPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        rootCategory = Settings.RegisterCanvasLayoutCategory(rootPanel, rootPanel.name)
        uiCategory = RegisterSubcategory(rootCategory, CreateAppearancePanel(), "UI Appearance")
        EnsureProfessionPages()
        Settings.RegisterAddOnCategory(rootCategory)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(rootPanel)
        uiCategory = CreateAppearancePanel()
        InterfaceOptions_AddCategory(uiCategory)
        EnsureProfessionPages()
    end
end

function ProfessionTracker_OpenOptions()
    RegisterPages()
    if Settings and Settings.OpenToCategory and rootCategory and rootCategory.GetID then
        Settings.OpenToCategory(rootCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory and rootPanel then
        InterfaceOptionsFrame_OpenToCategory(rootPanel)
        InterfaceOptionsFrame_OpenToCategory(rootPanel)
    end
end

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:RegisterEvent("SKILL_LINES_CHANGED")
init:RegisterEvent("CHAT_MSG_SKILL")
init:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        RegisterPages()
    elseif rootCategory then
        EnsureProfessionPages()
    end
end)
