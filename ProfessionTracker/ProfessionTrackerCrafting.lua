local SKILL_ID_NAMES = {
    [171] = "Alchemy", [164] = "Blacksmithing", [333] = "Enchanting",
    [202] = "Engineering", [182] = "Herbalism", [186] = "Mining",
    [393] = "Skinning", [197] = "Tailoring", [165] = "Leatherworking",
    [185] = "Cooking", [356] = "Fishing", [129] = "First Aid",
}
local GATHERING = { Herbalism = true, Mining = true, Skinning = true, Fishing = true }
local recipeWindowOpen = false
local openProfessionName
local MAX_SAMPLES = 10
local GetCraftStats, AddSample
local GATHER_SPELLS = { [2366] = "Herbalism", [2575] = "Mining", [8613] = "Skinning" }

local function GetGatherStats(name)
    local stats = GetCraftStats(name)
    stats.gatherSamples = stats.gatherSamples or {}
    stats.gatherActionsSinceSkill = stats.gatherActionsSinceSkill or 0
    stats.gatherTotalActions = stats.gatherTotalActions or 0
    return stats
end

function ProfessionTracker_RecordGatherSpell(spellID)
    local name = GATHER_SPELLS[spellID]
    if not name then return false end
    local stats = GetGatherStats(name)
    stats.gatherActionsSinceSkill = stats.gatherActionsSinceSkill + 1
    stats.gatherTotalActions = stats.gatherTotalActions + 1
    return true
end

function ProfessionTracker_CaptureGatherSkillups()
    if not ProfessionTrackerDB then return end
    for _, skill in ipairs(ProfessionTracker_GetProfessionSkills()) do
        if skill.name == "Herbalism" or skill.name == "Mining" or skill.name == "Skinning" then
            local stats = GetGatherStats(skill.name)
            if stats.gatherLastSkill == nil then
                stats.gatherLastSkill = skill.rank
            else
                local gained = skill.rank - stats.gatherLastSkill
                if gained > 0 then
                    if stats.gatherActionsSinceSkill > 0 then
                        AddSample(stats.gatherSamples, stats.gatherActionsSinceSkill / gained)
                    end
                    stats.gatherActionsSinceSkill = 0
                end
                stats.gatherLastSkill = skill.rank
            end
        end
    end
end

function ProfessionTracker_GetGatherDetail(skill)
    local settings = ProfessionTracker_GetProfessionSettings(skill.name)
    local stats = GetGatherStats(skill.name)
    local rate
    if settings.gatherRateMode == "custom" then
        rate = math.max(1, math.min(100, tonumber(settings.customGatherRate) or 2.5))
    else
        local total, weight = 5, 2 -- prior estimate: 2.5 successful nodes per skill point
        for _, sample in ipairs(stats.gatherSamples) do
            if sample > 0 and sample < 100 then total, weight = total + sample, weight + 1 end
        end
        rate = total / weight
    end
    local left = math.max(0, math.floor((skill.cap - skill.rank) * rate - stats.gatherActionsSinceSkill + 0.5))
    local noun = skill.name == "Herbalism" and "herbs" or (skill.name == "Mining" and "ore nodes" or "skinnable corpses")
    local line = ("~%d %s to %d"):format(left, noun, skill.cap)
    if settings.estimateDetail == "recommended" then
        return line .. (settings.gatherRateMode == "custom" and (" (%.1f actions/skill)"):format(rate) or " (learning your rate)")
    elseif settings.estimateDetail == "full" then
        local source = settings.gatherRateMode == "custom" and "custom rate" or (#stats.gatherSamples > 0 and "learned rate" or "starting estimate")
        return line .. ("\n%s: %.1f actions/skill; %d since skill-up"):format(source, rate, stats.gatherActionsSinceSkill)
    end
    return line
end

function ProfessionTracker_ResetGatherEstimateData(name)
    local stats = GetGatherStats(name)
    stats.gatherSamples = {}
    stats.gatherActionsSinceSkill = 0
    stats.gatherTotalActions = 0
    stats.gatherLastSkill = nil
    for _, skill in ipairs(ProfessionTracker_GetProfessionSkills()) do
        if skill.name == name then stats.gatherLastSkill = skill.rank; break end
    end
    if ProfessionTracker_ApplyOptions then ProfessionTracker_ApplyOptions() end
end

local function FindGuideStep(name, rank)
    local key = name == "First Aid" and "FirstAid" or name
    local steps = ProfessionTrackerGuideData and ProfessionTrackerGuideData[key]
    if not steps then return nil end
    for _, step in ipairs(steps) do
        if rank >= step.min and rank < step.max then return step end
    end
end

local function FindLearnedRecipe(name, recipeName)
    local recipes = ProfessionTrackerDB.professionRecipes and ProfessionTrackerDB.professionRecipes[name]
    local wanted = recipeName:lower()
    for _, recipe in pairs(recipes or {}) do
        if recipe.name and recipe.name:lower() == wanted then return recipe end
    end
    if ProfessionTrackerDB.professionLearnedRecipeNames and
        ProfessionTrackerDB.professionLearnedRecipeNames[name] and
        ProfessionTrackerDB.professionLearnedRecipeNames[name][wanted] then return true end
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if ok then return a end
end

local function ProfessionName(info)
    if not info then return nil end
    local skillLineID = info.professionID or info.parentProfessionID
    return SKILL_ID_NAMES[skillLineID] or info.professionName
end

GetCraftStats = function(name)
    ProfessionTrackerDB.professionStats = ProfessionTrackerDB.professionStats or {}
    local stats = ProfessionTrackerDB.professionStats[name]
    if not stats then
        stats = { samples = {}, actionsSinceSkill = 0, actionsByRecipe = {} }
        ProfessionTrackerDB.professionStats[name] = stats
    end
    stats.samples = stats.samples or {}
    stats.actionsSinceSkill = stats.actionsSinceSkill or 0
    stats.actionsByRecipe = stats.actionsByRecipe or {}
    stats.recipeSamples = stats.recipeSamples or {}
    return stats
end

AddSample = function(samples, sample)
    if sample <= 0 or sample > 500 then return end
    table.insert(samples, sample)
    while #samples > MAX_SAMPLES do table.remove(samples, 1) end
end

local function Average(samples)
    if not samples or #samples == 0 then return nil end
    local total = 0
    for _, value in ipairs(samples) do total = total + value end
    return total / #samples
end

function ProfessionTracker_CraftingInit()
    if not ProfessionTrackerDB then return end
    ProfessionTrackerDB.professionStats = ProfessionTrackerDB.professionStats or {}
    ProfessionTrackerDB.professionRecipes = ProfessionTrackerDB.professionRecipes or {}
    ProfessionTrackerDB.professionRecipesScanned = ProfessionTrackerDB.professionRecipesScanned or {}
    ProfessionTrackerDB.professionRecipeScanStatus = ProfessionTrackerDB.professionRecipeScanStatus or {}
    ProfessionTracker_CaptureCraftSkillups()
end

function ProfessionTracker_CaptureCraftSkillups()
    if not ProfessionTrackerDB then return end
    for _, skill in ipairs(ProfessionTracker_GetProfessionSkills()) do
        if not GATHERING[skill.name] then
            local stats = GetCraftStats(skill.name)
            if stats.lastSkill == nil then
                stats.lastSkill = skill.rank
            else
                local gained = skill.rank - stats.lastSkill
                if gained > 0 then
                    if stats.actionsSinceSkill > 0 then
                        AddSample(stats.samples, stats.actionsSinceSkill / gained)
                    end
                    local lastRecipeKey = stats.lastRecipeID and tostring(stats.lastRecipeID)
                    local recipeActions = lastRecipeKey and stats.actionsByRecipe[lastRecipeKey]
                    local recipeKinds = 0
                    for _ in pairs(stats.actionsByRecipe) do recipeKinds = recipeKinds + 1 end
                    if recipeKinds == 1 and recipeActions and recipeActions > 0 then
                        stats.recipeSamples[lastRecipeKey] = stats.recipeSamples[lastRecipeKey] or {}
                        AddSample(stats.recipeSamples[lastRecipeKey], recipeActions / gained)
                    end
                    stats.actionsSinceSkill = 0
                    stats.actionsByRecipe = {}
                    stats.lastRecipeID = nil
                end
                stats.lastSkill = skill.rank
            end
        end
    end
end

local function GetOpenProfession()
    local api = C_TradeSkillUI
    if not api then return nil end
    local info = SafeCall(api.GetBaseProfessionInfo)
    if type(info) ~= "table" then return nil end
    return ProfessionName(info), info
end

function ProfessionTracker_CraftingSetOpen(isOpen)
    recipeWindowOpen = isOpen and true or false
    if not isOpen then openProfessionName = nil end
end
function ProfessionTracker_CraftingIsOpen()
    return recipeWindowOpen
end

function ProfessionTracker_ScanCraftRecipes()
    local api = C_TradeSkillUI
    if not api then return false end
    local name = GetOpenProfession()
    if not name or GATHERING[name] then return false end
    openProfessionName = name
    ProfessionTrackerDB.professionRecipeScanStatus = ProfessionTrackerDB.professionRecipeScanStatus or {}

    if SafeCall(api.IsTradeSkillLinked) or SafeCall(api.IsTradeSkillGuild) or SafeCall(api.IsNPCCrafting) then
        ProfessionTrackerDB.professionRecipeScanStatus[name] = "Open your own profession book to scan recipes"
        return false
    end

    local recipeIDs
    if api.GetAllRecipeIDs then recipeIDs = SafeCall(api.GetAllRecipeIDs) end
    if type(recipeIDs) ~= "table" or #recipeIDs == 0 then
        if api.GetFilteredRecipeIDs then recipeIDs = SafeCall(api.GetFilteredRecipeIDs) end
    end
    if type(recipeIDs) ~= "table" then
        ProfessionTrackerDB.professionRecipeScanStatus[name] = "Recipe list API unavailable"
        return false
    elseif #recipeIDs == 0 then
        ProfessionTrackerDB.professionRecipeScanStatus[name] = "No recipes returned; clear profession filters and reopen"
        return false
    end

    local learned = {}
    local learnedNames = {}
    local basicType = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    for _, recipeID in ipairs(recipeIDs) do
        local recipe = SafeCall(api.GetRecipeInfo, recipeID)
        if type(recipe) == "table" and recipe.learned and recipe.name then
            learnedNames[recipe.name:lower()] = true
        end
        if type(recipe) == "table" and recipe.learned and recipe.canSkillUp and recipe.name and recipe.relativeDifficulty ~= 3 then
            local schematic = SafeCall(api.GetRecipeSchematic, recipeID, false)
            if type(schematic) == "table" then
                local reagents = {}
                for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
                    local isBasic = slot.reagentType == nil or basicType == nil or slot.reagentType == basicType
                    if isBasic and slot.reagents and #slot.reagents > 0 then
                        local options = {}
                        for _, reagent in ipairs(slot.reagents) do
                            if reagent.itemID then options[#options + 1] = reagent.itemID end
                        end
                        if #options > 0 then
                            reagents[#reagents + 1] = { quantity = slot.quantityRequired or 1, options = options }
                        end
                    end
                end
                learned[tostring(recipeID)] = {
                    id = recipeID,
                    name = recipe.name,
                    difficulty = recipe.relativeDifficulty,
                    reagents = reagents,
                }
            end
        end
    end
    ProfessionTrackerDB.professionRecipes = ProfessionTrackerDB.professionRecipes or {}
    ProfessionTrackerDB.professionRecipes[name] = learned
    ProfessionTrackerDB.professionLearnedRecipeNames = ProfessionTrackerDB.professionLearnedRecipeNames or {}
    ProfessionTrackerDB.professionLearnedRecipeNames[name] = learnedNames
    ProfessionTrackerDB.professionRecipesScanned = ProfessionTrackerDB.professionRecipesScanned or {}
    ProfessionTrackerDB.professionRecipesScanned[name] = true
    if next(learned) then
        ProfessionTrackerDB.professionRecipeScanStatus[name] = nil
    else
        ProfessionTrackerDB.professionRecipeScanStatus[name] = "No learned recipe can currently grant skill"
    end
    return true
end
function ProfessionTracker_RecordCraft(recipeID)
    if not ProfessionTrackerDB then return end
    local api = C_TradeSkillUI
    local name
    if api and api.GetProfessionInfoByRecipeID and recipeID then
        name = ProfessionName(SafeCall(api.GetProfessionInfoByRecipeID, recipeID))
    end
    name = name or openProfessionName or select(1, GetOpenProfession())
    if not name or GATHERING[name] then return end

    local stats = GetCraftStats(name)
    stats.actionsSinceSkill = stats.actionsSinceSkill + 1
    local key = tostring(recipeID or "unknown")
    stats.actionsByRecipe[key] = (stats.actionsByRecipe[key] or 0) + 1
    stats.lastRecipeID = recipeID
end

local function AuctionPrice(itemID)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not api or not api.GetAuctionPriceByItemID then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, "ProfessionTracker", itemID)
    if ok and type(price) == "number" and price >= 0 then return price end
end

local function FormatMoney(copper)
    copper = math.max(0, math.floor(copper + 0.5))
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local coppers = copper % 100
    if gold > 0 then return ("%dg %ds"):format(gold, silver) end
    if silver > 0 then return ("%ds %dc"):format(silver, coppers) end
    return coppers .. "c"
end

local function GetRecipeCost(recipe)
    local total = 0
    for _, slot in ipairs(recipe.reagents or {}) do
        local cheapest
        for _, itemID in ipairs(slot.options or {}) do
            local price = AuctionPrice(itemID)
            if price and (not cheapest or price < cheapest) then cheapest = price end
        end
        if not cheapest then return nil end
        total = total + cheapest * (slot.quantity or 1)
    end
    return total
end

local function RecipeExpectedCrafts(name, recipe, remaining)
    local stats = GetCraftStats(name)
    local samples = stats.recipeSamples[tostring(recipe.id)]
    local recipeAverage = Average(samples)
    local average = recipeAverage or Average(stats.samples)
    if not average then return nil end
    local completed = recipeAverage and (stats.actionsByRecipe[tostring(recipe.id)] or 0) or stats.actionsSinceSkill
    return math.max(0, math.floor(remaining * average - completed + 0.5))
end

local function RecipeComplexity(recipe)
    local reagentCount, quantity = 0, 0
    for _, slot in ipairs(recipe.reagents or {}) do
        reagentCount = reagentCount + 1
        quantity = quantity + (slot.quantity or 1)
    end
    return reagentCount, quantity
end

local function SelectRecipe(name, remaining)
    local recipes = ProfessionTrackerDB.professionRecipes and ProfessionTrackerDB.professionRecipes[name]
    if not recipes then return nil, nil, false end
    local settings = ProfessionTracker_GetProfessionSettings(name)
    local best, bestScore, bestCost
    local priority = settings.recipePriority or "lowest_cost"
    for _, recipe in pairs(recipes) do
        local cost = GetRecipeCost(recipe)
        local crafts = RecipeExpectedCrafts(name, recipe, remaining)
        local score
        if priority == "quickest" then
            local reagents, quantity = RecipeComplexity(recipe)
            score = reagents * 1000 + quantity
        elseif priority == "fewest_crafts" then
            score = crafts or (recipe.difficulty or 99) * 10000
        elseif cost then
            score = cost * (crafts or 1)
        end
        if score and (not best or score < bestScore or (score == bestScore and (recipe.difficulty or 99) < (best.difficulty or 99))) then
            best, bestScore, bestCost = recipe, score, cost
        end
    end
    return best, bestCost, true
end

function ProfessionTracker_ResetCraftEstimateData(name)
    if not ProfessionTrackerDB then return end
    local stats = GetCraftStats(name)
    stats.samples = {}
    stats.actionsSinceSkill = 0
    stats.actionsByRecipe = {}
    stats.recipeSamples = {}
    stats.lastRecipeID = nil
    stats.lastSkill = nil
    for _, skill in ipairs(ProfessionTracker_GetProfessionSkills()) do
        if skill.name == name then stats.lastSkill = skill.rank; break end
    end
    if ProfessionTracker_ApplyOptions then ProfessionTracker_ApplyOptions() end
end

function ProfessionTracker_GetCraftingDebugLines()
    if not ProfessionTrackerDB then return {} end
    local lines = {}
    local recipeCount, skillCount = 0, 0
    for _, recipes in pairs(ProfessionTrackerDB.professionRecipes or {}) do
        for _ in pairs(recipes) do recipeCount = recipeCount + 1 end
    end
    for _ in pairs(ProfessionTrackerDB.professionStats or {}) do skillCount = skillCount + 1 end
    local source = C_TradeSkillUI and (C_TradeSkillUI.GetAllRecipeIDs and "all recipes" or (C_TradeSkillUI.GetFilteredRecipeIDs and "filtered recipes" or "recipe list unavailable")) or "trade skill API unavailable"
    lines[#lines + 1] = ("Craft tracker: %s; %d recipes cached for %d professions; %s."):format(recipeWindowOpen and "profession open" or "profession closed", recipeCount, skillCount, source)
    for name, recipes in pairs(ProfessionTrackerDB.professionRecipes or {}) do
        local count = 0
        for _ in pairs(recipes) do count = count + 1 end
        local status = ProfessionTrackerDB.professionRecipeScanStatus and ProfessionTrackerDB.professionRecipeScanStatus[name]
        lines[#lines + 1] = ("  %s: %d skill-up recipes%s"):format(name, count, status and (" (" .. status .. ")") or "")
    end
    for _, name in ipairs({ "Herbalism", "Mining", "Skinning" }) do
        local stats = GetGatherStats(name)
        local average = Average(stats.gatherSamples)
        lines[#lines + 1] = ("  %s gathering: %d total actions; %d since skill-up; learned rate %s actions/skill from %d skill-ups."):format(
            name, stats.gatherTotalActions, stats.gatherActionsSinceSkill,
            average and ("%.2f"):format(average) or "not learned", #stats.gatherSamples)
    end
    return lines
end

function ProfessionTracker_CraftingDebug()
    for _, line in ipairs(ProfessionTracker_GetCraftingDebugLines()) do print("  " .. line) end
end
function ProfessionTracker_GetCraftDetail(skill)
    if not ProfessionTrackerDB then return "Open profession to scan recipes" end
    local settings = ProfessionTracker_GetProfessionSettings(skill.name)
    local stats = GetCraftStats(skill.name)
    local remaining = math.max(0, skill.cap - skill.rank)
    local craftsLeft
    local defaultAverage = Average(stats.samples)
    if defaultAverage then
        craftsLeft = math.max(0, math.floor(remaining * defaultAverage - stats.actionsSinceSkill + 0.5))
    end

    local scanned = ProfessionTrackerDB.professionRecipesScanned and ProfessionTrackerDB.professionRecipesScanned[skill.name]
    local scanStatus = ProfessionTrackerDB.professionRecipeScanStatus and ProfessionTrackerDB.professionRecipeScanStatus[skill.name]

    -- A bundled guide target is authoritative for the current skill range, even
    -- when the character has not learned it yet. Learned recipe data is used only
    -- to provide live reagent/Auctionator cost details.
    local guideStep = FindGuideStep(skill.name, skill.rank)
    if guideStep then
        local learnedGuideRecipe = FindLearnedRecipe(skill.name, guideStep.recipe)
        if settings.estimateDetail == "count" then
            local countLine = craftsLeft and ("~%d crafts to %d"):format(craftsLeft, skill.cap) or "Craft rate learning"
            if not learnedGuideRecipe then return countLine .. (scanned and "\nLearn: " or "\nCheck recipe: ") .. guideStep.recipe end
            return countLine
        end
        local guideLine = ("Guide: %s (%d-%d)"):format(guideStep.recipe, guideStep.min, guideStep.max)
        if not learnedGuideRecipe then
            if not scanned then return guideLine .. "\nOpen profession to check; learn it if missing" end
            return guideLine .. "\nRecipe not learned — learn it to use this route"
        end
        if settings.estimateDetail == "recommended" then return guideLine .. "\nRecipe learned" end
        local cost = type(learnedGuideRecipe) == "table" and GetRecipeCost(learnedGuideRecipe) or nil
        local costLine = cost and ("Auctionator: %s/craft"):format(FormatMoney(cost)) or "Auctionator price unavailable"
        return guideLine .. "\nRecipe learned; " .. costLine
    end

    if not scanned then
        if settings.estimateDetail == "count" then
            return craftsLeft and ("~%d crafts to %d"):format(craftsLeft, skill.cap) or "Craft rate learning"
        end
        return scanStatus or "Open profession to scan recipes"
    end

    local best, cost = SelectRecipe(skill.name, remaining)
    if not best then
        if settings.estimateDetail == "count" then
            return craftsLeft and ("~%d crafts to %d"):format(craftsLeft, skill.cap) or "Craft rate learning"
        end
        if scanStatus then return scanStatus end
        if not (Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemID) then
            return "Auctionator price data unavailable"
        end
        return "Scan Auction House in Auctionator"
    end

    local craftsLine
    local recipeSamples = stats.recipeSamples[tostring(best.id)]
    local average = Average(recipeSamples) or Average(stats.samples)
    if average then
        local completed = Average(recipeSamples) and (stats.actionsByRecipe[tostring(best.id)] or 0) or stats.actionsSinceSkill
        craftsLeft = math.max(0, math.floor(remaining * average - completed + 0.5))
        craftsLine = ("~%d crafts to %d"):format(craftsLeft, skill.cap)
    else
        craftsLine = "Craft rate learning"
    end

    if settings.estimateDetail == "count" then return craftsLine end
    if settings.estimateDetail == "recommended" then return craftsLine .. "\nSuggested: " .. best.name end

    local recipeLine
    if cost then
        recipeLine = best.name .. " - " .. FormatMoney(cost) .. "/craft"
        if craftsLeft and craftsLeft > 0 then recipeLine = best.name .. " - " .. FormatMoney(cost * craftsLeft) .. " to cap" end
    else
        recipeLine = best.name .. " - Auctionator price unavailable"
    end
    local label = settings.recipePriority == "quickest" and "Quickest estimate" or (settings.recipePriority == "fewest_crafts" and "Fewest crafts" or "Lowest AH cost")
    return craftsLine .. "\n" .. label .. ": " .. recipeLine
end




