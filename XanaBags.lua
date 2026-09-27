-- XanaBags
-- Borders on gear in the bags: green = can equip and it's an upgrade,
-- yellow = can equip but not an upgrade, red = can't equip.
--
-- "Can't equip" is read from the item's tooltip: the game colours every unmet
-- requirement red (level, armor/weapon proficiency, class, profession), so any
-- red line other than durability means the item can't be equipped.
--
-- "Upgrade" means a higher item level than what is equipped in that slot (an
-- empty slot counts as an upgrade). Stats are not compared.
--
-- Items you have more of than when the bags were last closed are "new": their
-- border is purple (on gear, food and drink only the left half; the right half
-- keeps its colour).
--
-- Food gets a brown border, drinks a light blue one and junk (poor quality
-- items) a grey one. Junk wins over the gear colours.
--
-- Gear you can equip also gets coloured dots in its lower left corner, one for
-- each main stat (and armor) that is higher than on the equipped item it would
-- replace.

local ADDON = ...

local GREEN = { 0.1, 1, 0.1 }
local YELLOW = { 1, 0.85, 0.1 }
local RED = { 1, 0.1, 0.1 }
local PURPLE = { 0.7, 0.3, 1 }
local LIGHT_BLUE = { 0.45, 0.8, 1 } -- drinks
local BROWN = { 0.6, 0.4, 0.2 }     -- food
local GREY = { 0.55, 0.55, 0.55 }   -- junk (poor quality)
local BORDER = 2

-- Food and drink are told apart by the item's use effect, which the game names
-- "Food" or "Drink". The names are read from two of those spells so they match
-- the client's language: 433 is a "Food" effect, 430 a "Drink" effect.
local FOOD_SPELL, DRINK_SPELL = 433, 430

-- Stat dots, left to right in this order, for stats higher than on the equipped item.
-- A dot the player switched off gets `off = true`.
local STAT_DOTS = {
	{ name = "strength",  key = "ITEM_MOD_STRENGTH_SHORT",  color = { 1, 0.2, 0.2 } },   -- red
	{ name = "intellect", key = "ITEM_MOD_INTELLECT_SHORT", color = { 0.25, 0.5, 1 } },  -- blue
	{ name = "agility",   key = "ITEM_MOD_AGILITY_SHORT",   color = { 0.2, 0.9, 0.2 } }, -- green
	{ name = "spirit",    key = "ITEM_MOD_SPIRIT_SHORT",    color = { 1, 0.45, 0.8 } },  -- pink
	{ name = "stamina",   key = "ITEM_MOD_STAMINA_SHORT",   color = { 1, 0.6, 0.1 } },   -- orange
	{ name = "armor",     key = "RESISTANCE0_NAME",         color = { 0.6, 0.6, 0.6 } }, -- grey
}
local DOT_SIZE = 5
local DOT_COLUMNS = 3 -- dots fill a small grid in the corner, bottom row first
local DOT_TEXTURE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" -- a white circle

-- Equip slots that are not gear.
local SKIP_SLOTS = {
	[""] = true,
	INVTYPE_BAG = true,
	INVTYPE_QUIVER = true,
	INVTYPE_NON_EQUIP_IGNORE = true,
}

-- Equipment slots each kind of gear can go in (inventory slot IDs).
local EQUIP_SLOTS = {
	INVTYPE_AMMO = { 0 },
	INVTYPE_HEAD = { 1 },
	INVTYPE_NECK = { 2 },
	INVTYPE_SHOULDER = { 3 },
	INVTYPE_BODY = { 4 },
	INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 },
	INVTYPE_LEGS = { 7 },
	INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 },
	INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16, 17 }, -- off hand only counts for characters who can dual wield
	INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 },
	INVTYPE_SHIELD = { 17 },
	INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 },
	INVTYPE_RANGEDRIGHT = { 18 },
	INVTYPE_THROWN = { 18 },
	INVTYPE_RELIC = { 18 },
	INVTYPE_TABARD = { 19 },
}

local ItemLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
local BagItemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
local BagSlotCount = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local ItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local IsEquippable = (C_Item and C_Item.IsEquippableItem) or IsEquippableItem
local DetailedItemLevel = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
local ItemStats = (C_Item and C_Item.GetItemStats) or GetItemStats
local ItemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
local ItemQualityByID = (C_Item and C_Item.GetItemQualityByID) or GetItemQualityByID

-- Poor quality: vendor trash. nil while the item's data hasn't loaded yet.
local function IsJunk(link)
	local quality = ItemQualityByID and ItemQualityByID(link)
	if quality == nil and GetItemInfo then quality = select(3, GetItemInfo(link)) end
	if quality == nil then return nil end
	return quality == (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor or 0)
end

local function SpellName(id)
	return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id))
		or (GetSpellInfo and GetSpellInfo(id))
end

-- Brown for food, light blue for drinks, nil for anything else.
local function ConsumableColor(link)
	local effect = ItemSpell and ItemSpell(link)
	if not effect then return nil end
	if effect == (SpellName(FOOD_SPELL) or "Food") then return BROWN end
	if effect == (SpellName(DRINK_SPELL) or "Drink") then return LIGHT_BLUE end
end

-- nil while the item's data hasn't loaded yet.
local function ItemLevel(link)
	local level = DetailedItemLevel and DetailedItemLevel(link)
	if not level and GetItemInfo then level = select(4, GetItemInfo(link)) end
	return level
end

-- The equipped item a piece of gear would replace: the weakest (lowest item
-- level) of the items in the slots it fits. Returns
--   true, link, itemLevel   an item to compare with
--   true, nil, 0            one of those slots is empty
--   false                   the gear has no equipment slot
--   nil                     an equipped item's data hasn't loaded yet
local function ReplacedItem(equipLoc)
	local slots = EQUIP_SLOTS[equipLoc]
	if not slots then return false end
	local lowestLink, lowestLevel
	for i, slot in ipairs(slots) do
		local offHandWeapon = equipLoc == "INVTYPE_WEAPON" and i == 2
		if not offHandWeapon or (CanDualWield and CanDualWield()) then
			local equipped = GetInventoryItemLink("player", slot)
			if not equipped then return true, nil, 0 end
			local level = ItemLevel(equipped)
			if not level then return nil end
			if not lowestLevel or level < lowestLevel then lowestLink, lowestLevel = equipped, level end
		end
	end
	return lowestLevel ~= nil, lowestLink, lowestLevel
end

-- true / false, or nil if an item level isn't known yet.
local function IsUpgrade(link, equipLoc)
	local found, _, lowest = ReplacedItem(equipLoc)
	if found == nil then return nil end
	if not found then return false end
	local level = ItemLevel(link)
	if not level then return nil end
	return level > lowest
end

-- STAT_DOTS entries for the stats that are higher than on the item it would
-- replace (an empty slot counts as 0), or nil while item data is loading.
local function BetterStats(link, equipLoc)
	local found, equipped = ReplacedItem(equipLoc)
	if not found then return nil end
	local mine = ItemStats(link)
	local theirs = {}
	if equipped then theirs = ItemStats(equipped) end
	if not mine or not theirs then return nil end
	local better = {}
	for _, stat in ipairs(STAT_DOTS) do
		if not stat.off and (mine[stat.key] or 0) > (theirs[stat.key] or 0) then better[#better + 1] = stat end
	end
	return better
end

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99XanaBags:|r " .. tostring(msg))
end

---------------------------------------------------------------------------
-- Tooltip check
---------------------------------------------------------------------------
local function IsRed(r, g, b)
	return r and r > 0.9 and g < 0.2 and b < 0.2
end

-- A broken item's durability line is red, but it can still be equipped.
local function IsDurability(text)
	return text:find(DURABILITY or "Durability", 1, true) == 1
end

local scanner = CreateFrame("GameTooltip", "XanaBagsScanner", nil, "GameTooltipTemplate")

-- true / false, or nil while the item's data hasn't loaded yet.
local function HasRedLine(bag, slot)
	if C_TooltipInfo and C_TooltipInfo.GetBagItem then
		local data = C_TooltipInfo.GetBagItem(bag, slot)
		if not data or not data.lines or #data.lines == 0 then return nil end
		for i = 2, #data.lines do -- line 1 is the item name
			local line = data.lines[i]
			for _, side in ipairs({ { line.leftText, line.leftColor }, { line.rightText, line.rightColor } }) do
				local text, color = side[1], side[2]
				if text and color and IsRed(color.r, color.g, color.b) and not IsDurability(text) then
					return true
				end
			end
		end
		return false
	end

	scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
	scanner:ClearLines()
	scanner:SetBagItem(bag, slot)
	local lines = scanner:NumLines()
	local red = nil
	if lines > 0 then
		red = false
		for i = 2, lines do
			for _, side in ipairs({ "Left", "Right" }) do
				local fs = _G["XanaBagsScannerText" .. side .. i]
				local text = fs and fs:IsShown() and fs:GetText()
				if text and text ~= "" and IsRed(fs:GetTextColor()) and not IsDurability(text) then
					red = true
				end
			end
		end
	end
	scanner:Hide()
	return red
end

---------------------------------------------------------------------------
-- Borders
---------------------------------------------------------------------------
-- Nothing is drawn on Blizzard's bag buttons themselves. Each bag window gets
-- one frame of ours, and every button's border and dots are plain textures in
-- that frame, anchored to the button. Frames placed on the buttons made the
-- Gamepad UI recalculate what its cursor can interact with, which got the addon
-- blocked ("SetPreferredGamepadInteractTraget"). Textures aren't interactive,
-- and these frames are created once and never shown or hidden afterwards.
local overlays = setmetatable({}, { __mode = "k" }) -- bag window -> our frame
local cells = setmetatable({}, { __mode = "k" })    -- item button -> its textures

-- itemLink -> true (can equip) / false (can't). Cleared whenever what the
-- character can equip may have changed.
local canEquip = {}

-- Draw layers, lowest first.
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN",
	"FULLSCREEN_DIALOG", "TOOLTIP" }
local NEXT_STRATA = {}
for i, name in ipairs(STRATA) do NEXT_STRATA[name] = STRATA[i + 1] or name end

-- The game re-layers bag windows as they open, so the overlay is put back above
-- its window on every refresh, not just when it is created. It sits one whole
-- layer above the window, so nothing drawn inside the window covers it.
local function LiftOverlay(container)
	local overlay = overlays[container]
	if not overlay then return end
	overlay:SetFrameStrata(NEXT_STRATA[container:GetFrameStrata()] or "DIALOG")
	overlay:SetFrameLevel(container:GetFrameLevel() + 10)
end

local function GetOverlay(container)
	local overlay = overlays[container]
	if overlay then return overlay end
	overlay = CreateFrame("Frame", nil, UIParent)
	overlay:SetAllPoints(container)
	overlays[container] = overlay
	LiftOverlay(container)
	return overlay
end

-- The border is six pieces so its left and right halves can differ: left side
-- plus the left halves of top and bottom, and the same on the right.
local function GetCell(button)
	local cell = cells[button]
	if cell then return cell end
	local overlay = GetOverlay(button:GetParent())
	cell = { left = {}, right = {}, dots = {} }

	local function Edge(half, fromPoint, toPoint, toAnchor, horizontal)
		local t = overlay:CreateTexture(nil, "OVERLAY", nil, 3)
		t:SetPoint(fromPoint, button, fromPoint)
		t:SetPoint(toPoint, button, toAnchor or toPoint)
		if horizontal then t:SetHeight(BORDER) else t:SetWidth(BORDER) end
		t:Hide()
		half[#half + 1] = t
	end
	Edge(cell.left, "TOPLEFT", "TOPRIGHT", "TOP", true)
	Edge(cell.left, "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOM", true)
	Edge(cell.left, "TOPLEFT", "BOTTOMLEFT", nil, false)
	Edge(cell.right, "TOPRIGHT", "TOPLEFT", "TOP", true)
	Edge(cell.right, "BOTTOMRIGHT", "BOTTOMLEFT", "BOTTOM", true)
	Edge(cell.right, "TOPRIGHT", "BOTTOMRIGHT", nil, false)

	for i = 1, #STAT_DOTS do
		-- A black ring behind each dot keeps it visible on any icon.
		local outline = overlay:CreateTexture(nil, "OVERLAY", nil, 4)
		outline:SetTexture(DOT_TEXTURE)
		outline:SetVertexColor(0, 0, 0, 1)
		outline:SetSize(DOT_SIZE + 2, DOT_SIZE + 2)
		local column, row = (i - 1) % DOT_COLUMNS, math.floor((i - 1) / DOT_COLUMNS)
		outline:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT",
			3 + column * (DOT_SIZE + 2), 3 + row * (DOT_SIZE + 2))
		outline:Hide()
		local dot = overlay:CreateTexture(nil, "OVERLAY", nil, 5)
		dot:SetTexture(DOT_TEXTURE)
		dot:SetSize(DOT_SIZE, DOT_SIZE)
		dot:SetPoint("CENTER", outline)
		dot:Hide()
		cell.dots[i] = { outline = outline, dot = dot }
	end

	cells[button] = cell
	return cell
end

-- One colour for the whole border, or two for the left and right halves.
local function SetBorder(button, leftColor, rightColor)
	rightColor = rightColor or leftColor
	local cell = cells[button]
	if not leftColor then
		if cell then
			for _, t in ipairs(cell.left) do t:Hide() end
			for _, t in ipairs(cell.right) do t:Hide() end
		end
		return
	end
	cell = GetCell(button)
	for _, t in ipairs(cell.left) do
		t:SetColorTexture(leftColor[1], leftColor[2], leftColor[3], 1)
		t:Show()
	end
	for _, t in ipairs(cell.right) do
		t:SetColorTexture(rightColor[1], rightColor[2], rightColor[3], 1)
		t:Show()
	end
end

-- Shows one dot per STAT_DOTS entry in `stats`, packed into the lower left corner.
local function SetDots(button, stats)
	local cell = cells[button]
	if not stats or #stats == 0 then
		if cell then
			for _, d in ipairs(cell.dots) do d.dot:Hide() d.outline:Hide() end
		end
		return
	end
	cell = GetCell(button)
	for i, d in ipairs(cell.dots) do
		local stat = stats[i]
		if stat then
			d.dot:SetVertexColor(stat.color[1], stat.color[2], stat.color[3], 1)
		end
		d.dot:SetShown(stat ~= nil)
		d.outline:SetShown(stat ~= nil)
	end
end

-- Our textures live in a frame of our own, so they don't disappear with the bag
-- window. Everything belonging to a hidden button is hidden by hand.
local function HideHiddenCells()
	for button in pairs(cells) do
		-- IsVisible, not IsShown: a button in a closed bag window is still "shown".
		if not button:IsVisible() then
			SetBorder(button, nil)
			SetDots(button, nil)
		end
	end
end

-- Grey (junk), green, yellow, red, brown (food), light blue (drink), or nil for
-- "nothing to mark" / "don't know yet".
-- Green and yellow also return the item's link and equip slot.
local function ColorFor(bag, slot)
	local link = ItemLink(bag, slot)
	if not link then return nil end
	-- Junk first: on grey gear, "sell this" beats "you could equip this".
	local junk = IsJunk(link)
	if junk == nil then return nil end -- try again when the item data arrives
	if junk then return GREY end
	local equipLoc = select(4, ItemInfoInstant(link))
	if not equipLoc or SKIP_SLOTS[equipLoc] then return ConsumableColor(link) end
	if IsEquippable and not IsEquippable(link) then return nil end
	local can = canEquip[link]
	if can == nil then
		local red = HasRedLine(bag, slot)
		if red == nil then return nil end -- try again when the item data arrives
		can = not red
		canEquip[link] = can
	end
	if not can then return RED end
	local upgrade = IsUpgrade(link, equipLoc)
	if upgrade == nil then return nil end -- try again when the item data arrives
	return upgrade and GREEN or YELLOW, link, equipLoc
end

---------------------------------------------------------------------------
-- New items: anything you have more of than when the bags were last closed.
-- Equipped gear is counted too, so swapping gear doesn't make it "new".
-- (Kept in memory only: the Forever beta doesn't reload addon data at login.)
---------------------------------------------------------------------------
local SortBagsNow       -- defined below, used by the refresh above it
local autoSort = true   -- sort the bags each time they are opened
local bagsOpen          -- were the bags open at the last refresh?
local warnedNoSort
local seenCounts        -- itemID -> count when the bags were last closed
local currentCounts = {} -- itemID -> count now, recounted on every refresh

local function StackSize(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local info = C_Container.GetContainerItemInfo(bag, slot)
		return info and info.stackCount or 0
	end
	return select(2, GetContainerItemInfo(bag, slot)) or 0
end

local function CountItems()
	local counts = {}
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, BagSlotCount(bag) or 0 do
			local id = BagItemID(bag, slot)
			if id then counts[id] = (counts[id] or 0) + StackSize(bag, slot) end
		end
	end
	for slot = 0, 19 do
		local id = GetInventoryItemID("player", slot)
		if id then counts[id] = (counts[id] or 0) + (GetInventoryItemCount("player", slot) or 1) end
	end
	return counts
end

local function MarkAllSeen()
	seenCounts = CountItems()
end

local function IsNew(id)
	if not id or not seenCounts then return false end
	return (currentCounts[id] or 0) > (seenCounts[id] or 0)
end

---------------------------------------------------------------------------
-- Bag windows
---------------------------------------------------------------------------
local function ButtonBagSlot(button)
	local bag = button.GetBagID and button:GetBagID() or button:GetParent():GetID()
	return bag, button:GetID()
end

local function BagFrames()
	local frames = {}
	for i = 1, NUM_CONTAINER_FRAMES or 13 do frames[#frames + 1] = _G["ContainerFrame" .. i] end
	frames[#frames + 1] = ContainerFrameCombinedBags
	return frames
end

local function AnyBagShown()
	for _, frame in ipairs(BagFrames()) do
		if frame and frame:IsShown() then return true end
	end
	return false
end

local function ForEachBagButton(fn)
	for _, frame in ipairs(BagFrames()) do
		if frame and frame:IsShown() then
			if frame.EnumerateValidItems then
				for _, button in frame:EnumerateValidItems() do fn(button) end
			else
				local name = frame:GetName()
				for j = 1, frame.size or 36 do
					local button = _G[name .. "Item" .. j]
					if button then fn(button) end
				end
			end
		end
	end
end

-- New gear: left half purple, right half its equip colour. Anything else new: all purple.
-- Stat dots only on gear this character can equip (green or yellow).
local function UpdateButton(button)
	if not button:IsVisible() then
		SetBorder(button, nil)
		SetDots(button, nil)
		return
	end
	local bag, slot = ButtonBagSlot(button)
	local color, link, equipLoc = ColorFor(bag, slot)
	if IsNew(BagItemID(bag, slot)) then
		SetBorder(button, PURPLE, color)
	else
		SetBorder(button, color)
	end
	SetDots(button, link and BetterStats(link, equipLoc))
end

local refreshQueued
local function RequestRefresh()
	if refreshQueued then return end
	refreshQueued = true
	-- Next frame, so the bag window has filled its buttons first.
	C_Timer.After(0, function()
		refreshQueued = false
		HideHiddenCells()
		if not AnyBagShown() then
			bagsOpen = nil
			return
		end
		if not bagsOpen then
			bagsOpen = true
			if autoSort then SortBagsNow() end
		end
		for _, frame in ipairs(BagFrames()) do
			if frame and frame:IsShown() then LiftOverlay(frame) end
		end
		currentCounts = CountItems()
		ForEachBagButton(UpdateButton)
	end)
end

-- Closing the bags counts as having seen everything in them. Bag windows close
-- one after another, so wait a frame and check that they're all gone.
-- The game's own bag cleanup, which groups items by type the way the
-- "Clean Up Bags" button does. Returns false if it couldn't run.
function SortBagsNow()
	local sort = (C_Container and C_Container.SortBags) or SortBags
	if not sort then
		if not warnedNoSort then
			warnedNoSort = true
			Print("This client has no bag sorting, so /xbags sort does nothing.")
		end
		return false
	end
	if InCombatLockdown() then return false end
	if CursorHasItem and CursorHasItem() then return false end -- don't sort mid-drag
	return pcall(sort)
end

local function OnBagHidden()
	C_Timer.After(0, function()
		HideHiddenCells()
		if not AnyBagShown() then
			bagsOpen = nil
			if seenCounts then MarkAllSeen() end
		end
	end)
end

local function ResetAndRefresh()
	wipe(canEquip)
	RequestRefresh()
end

local function HookBagFrames()
	for _, frame in ipairs(BagFrames()) do
		if frame then
			frame:HookScript("OnShow", RequestRefresh)
			frame:HookScript("OnHide", OnBagHidden)
		end
	end
	if ContainerFrame_Update then hooksecurefunc("ContainerFrame_Update", RequestRefresh) end
end

---------------------------------------------------------------------------
-- Colour settings. Each entry points at the colour table used above; edits
-- change that table in place, so everything using it follows.
---------------------------------------------------------------------------
local COLOR_SETTINGS = {
	{ name = "upgrade",    label = "gear: equippable upgrade",       color = GREEN },
	{ name = "equippable", label = "gear: equippable, not upgrade",  color = YELLOW },
	{ name = "unusable",   label = "gear: can't equip",              color = RED },
	{ name = "new",        label = "new item",                       color = PURPLE },
	{ name = "food",       label = "food",                           color = BROWN },
	{ name = "junk",       label = "junk (poor quality)",            color = GREY },
	{ name = "drink",      label = "drink",                          color = LIGHT_BLUE },
	{ name = "strength",   label = "dot: higher Strength",           color = STAT_DOTS[1].color },
	{ name = "intellect",  label = "dot: higher Intellect",          color = STAT_DOTS[2].color },
	{ name = "agility",    label = "dot: higher Agility",            color = STAT_DOTS[3].color },
	{ name = "spirit",     label = "dot: higher Spirit",             color = STAT_DOTS[4].color },
	{ name = "stamina",    label = "dot: higher Stamina",            color = STAT_DOTS[5].color },
	{ name = "armor",      label = "dot: higher Armor",              color = STAT_DOTS[6].color },
}
for _, s in ipairs(COLOR_SETTINGS) do s.default = { s.color[1], s.color[2], s.color[3] } end

local function ToHex(c)
	local function byte(v) return math.floor(v * 255 + 0.5) end
	return ("%02x%02x%02x"):format(byte(c[1]), byte(c[2]), byte(c[3]))
end

-- "ff8800" or "#ff8800" -> { r, g, b }, or nil.
local function FromHex(text)
	local r, g, b = (text or ""):match("^#?(%x%x)(%x%x)(%x%x)$")
	if not r then return nil end
	return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 }
end

local function SetColor(setting, c)
	setting.color[1], setting.color[2], setting.color[3] = c[1], c[2], c[3]
end

-- Full name or its first three or more letters.
local function FindColorSetting(name)
	name = strlower(name or "")
	if #name < 3 then return nil end
	for _, s in ipairs(COLOR_SETTINGS) do
		if s.name:sub(1, #name) == name then return s end
	end
end

-- Saved in a character-specific macro, like XanaBars' settings, because the
-- Forever beta writes SavedVariables but never loads them back. Only colours
-- that differ from the default are stored, then the stat dots switched off:
--   /xbagdata 1|upgrade=19ff19,new=b24cff|strength,agility
local MACRO_NAME = "XanaBags"
local DATA_TAG = "/xbagdata "
local MACRO_SCAN_END = 300 -- past the last possible macro index on any client
local macrosReady, saveWanted, warnedMacro

-- Only character-specific macros count: General (account) macros fill indexes
-- 1..numAccount with no gaps and character macros come after them.
local function FindSettingsMacro()
	for i = (GetNumMacros() or 0) + 1, MACRO_SCAN_END do
		local name, _, body = GetMacroInfo(i)
		if name and body and body:find(DATA_TAG, 1, true) then return i end
	end
end

-- Full stat name or its first three or more letters.
local function FindStat(name)
	name = strlower(name or "")
	if #name < 3 then return nil end
	for _, stat in ipairs(STAT_DOTS) do
		if stat.name:sub(1, #name) == name then return stat end
	end
end

local function SettingsData()
	local colors, off = {}, {}
	for _, s in ipairs(COLOR_SETTINGS) do
		local hex = ToHex(s.color)
		if hex ~= ToHex(s.default) then colors[#colors + 1] = s.name .. "=" .. hex end
	end
	for _, stat in ipairs(STAT_DOTS) do
		if stat.off then off[#off + 1] = stat.name end
	end
	return ("1|%s|%s|%s"):format(table.concat(colors, ","), table.concat(off, ","),
		autoSort and "" or "autosort=0")
end

-- Replaces all colour and dot settings with a SettingsData() line (anything it
-- doesn't mention goes back to default). Returns false if it isn't one.
local function ApplySettingsData(data)
	local version, colors, off, options = strsplit("|", data)
	if version ~= "1" then return false end
	for _, s in ipairs(COLOR_SETTINGS) do SetColor(s, s.default) end
	for _, stat in ipairs(STAT_DOTS) do stat.off = nil end
	autoSort = not (options or ""):find("autosort=0", 1, true)
	for pair in (colors or ""):gmatch("[^,]+") do
		local name, hex = pair:match("^(%a+)=(%x+)$")
		local setting, color = FindColorSetting(name), FromHex(hex)
		if setting and color then SetColor(setting, color) end
	end
	for name in (off or ""):gmatch("[^,]+") do
		local stat = FindStat(name)
		if stat then stat.off = true end
	end
	return true
end

local function LoadSettingsMacro()
	local index = FindSettingsMacro()
	if not index then return false end
	local _, _, body = GetMacroInfo(index)
	return ApplySettingsData(body:match("/xbagdata ([^\n]*)") or "")
end

-- Macros can't be edited in combat, and must not be written before the
-- existing ones have loaded (or a second settings macro would be created).
local function SaveSettings()
	if InCombatLockdown() or not macrosReady then saveWanted = true return end
	saveWanted = nil
	local body = DATA_TAG .. SettingsData()
	local index = FindSettingsMacro()
	if index then
		local _, _, old = GetMacroInfo(index)
		if old ~= body then EditMacro(index, nil, nil, body) end
		return
	end
	local ok, created = pcall(CreateMacro, MACRO_NAME, 134400, body, true)
	if (not ok or not created or created == 0) and not warnedMacro then
		warnedMacro = true
		Print("Couldn't create the XanaBags settings macro (are this character's macro slots full?). " ..
			"Colour changes won't survive a logout until one is free.")
	end
end

-- Runs once, as soon as the player's macros are known to be loaded.
local function OnMacrosReady()
	if macrosReady then return end
	macrosReady = true
	if LoadSettingsMacro() then RequestRefresh() end
	if saveWanted then SaveSettings() end
end

local function ListColors()
	Print("Colours (change one with /xbags color <name> <hex>, e.g. /xbags color food 8b5a2b):")
	for _, s in ipairs(COLOR_SETTINGS) do
		local hex = ToHex(s.color)
		Print(("  |cff%s%s|r - %s, #%s%s"):format(hex, s.name, s.label, hex,
			hex == ToHex(s.default) and "" or (" (default #" .. ToHex(s.default) .. ")")))
	end
end

-- "/xbags color <name> <hex>", "/xbags color <name> reset", "/xbags color reset".
local function ColorCommand(args)
	local name, value = strsplit(" ", strtrim(args or ""), 2)
	if name == "reset" and not value then
		for _, s in ipairs(COLOR_SETTINGS) do SetColor(s, s.default) end
		Print("All colours reset to their defaults.")
	else
		local setting = FindColorSetting(name)
		if not setting then
			Print("Unknown colour. Type /xbags colors to see the names.")
			return
		end
		local color = (value == "reset") and setting.default or FromHex(value)
		if not color then
			Print("Give the colour as 6 hex digits (like ff8800), or 'reset'.")
			return
		end
		SetColor(setting, color)
		Print(("%s is now |cff%s#%s|r."):format(setting.name, ToHex(setting.color), ToHex(setting.color)))
	end
	SaveSettings()
	RequestRefresh()
end

local function ListDots()
	Print("Stat dots (switch with /xbags stat <stat> on|off):")
	for _, stat in ipairs(STAT_DOTS) do
		Print(("  |cff%s%s|r - %s"):format(ToHex(stat.color), stat.name,
			stat.off and "|cffff5555off|r" or "|cff55ff55on|r"))
	end
end

-- "/xbags stat <stat|all> on|off".
local function DotCommand(args)
	local name, value = strsplit(" ", strtrim(args or ""), 2)
	if value ~= "on" and value ~= "off" then
		Print("Usage: /xbags stat <stat | all> on|off   (stats: strength, intellect, agility, spirit, stamina, armor)")
		return
	end
	local stats = {}
	if name == "all" then
		stats = STAT_DOTS
	else
		stats[1] = FindStat(name)
		if not stats[1] then Print("Unknown stat. Type /xbags stats to see them.") return end
	end
	for _, stat in ipairs(stats) do stat.off = (value == "off") or nil end
	ListDots()
	SaveSettings()
	RequestRefresh()
end

-- The settings macro's data line. Deliberately does nothing.
SLASH_XANABAGSDATA1 = "/xbagdata"
SlashCmdList.XANABAGSDATA = function() end

---------------------------------------------------------------------------
-- Export / import strings: "XG1:" + base64 of SettingsData().
-- Base64 keeps "|" out of the edit box, where WoW would read it as an escape code.
---------------------------------------------------------------------------
local EXPORT_PREFIX = "XG1:"
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function Base64Encode(s)
	local out = {}
	for i = 1, #s, 3 do
		local a, b, c = s:byte(i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local d1, d2 = math.floor(n / 262144) % 64, math.floor(n / 4096) % 64
		local d3, d4 = math.floor(n / 64) % 64, n % 64
		out[#out + 1] = B64:sub(d1 + 1, d1 + 1) .. B64:sub(d2 + 1, d2 + 1)
			.. (b and B64:sub(d3 + 1, d3 + 1) or "=") .. (c and B64:sub(d4 + 1, d4 + 1) or "=")
	end
	return table.concat(out)
end

-- Returns nil for anything that isn't valid base64.
local function Base64Decode(s)
	s = s:gsub("%s", "")
	if #s % 4 ~= 0 then return nil end
	local out = {}
	for i = 1, #s, 4 do
		local n, pad = 0, 0
		for j = i, i + 3 do
			local ch = s:sub(j, j)
			local v = B64:find(ch, 1, true)
			if ch == "=" and j >= i + 2 then
				pad, n = pad + 1, n * 64
			elseif v and pad == 0 then
				n = n * 64 + v - 1
			else
				return nil
			end
		end
		out[#out + 1] = string.char(math.floor(n / 65536) % 256)
			.. (pad < 2 and string.char(math.floor(n / 256) % 256) or "")
			.. (pad < 1 and string.char(n % 256) or "")
	end
	return table.concat(out)
end

-- Returns true if the string was valid.
local function ImportSettings(text)
	text = strtrim(text or "")
	local data = text:sub(1, #EXPORT_PREFIX) == EXPORT_PREFIX and Base64Decode(text:sub(#EXPORT_PREFIX + 1))
	if not data or not ApplySettingsData(data) then
		Print("That isn't a XanaBags export string.")
		return false
	end
	SaveSettings()
	RequestRefresh()
	Print("Colour and dot settings imported.")
	return true
end

-- Window with one text box: shows an export string to copy, or takes one to import.
-- It never moves keyboard focus by itself: doing that from addon code got the
-- addon blocked (and crashed the Forever beta client), so the player clicks the
-- box instead. For the same reason it is a plain EditBox, not InputBoxTemplate,
-- and not registered in UISpecialFrames.
local dialog = CreateFrame("Frame", "XanaBagsDialog", UIParent)
dialog:SetSize(480, 130)
dialog:SetPoint("CENTER", 0, 150)
dialog:SetFrameStrata("FULLSCREEN_DIALOG")
dialog:EnableMouse(true)
dialog:Hide()
dialog.bg = dialog:CreateTexture(nil, "BACKGROUND")
dialog.bg:SetAllPoints()
dialog.bg:SetColorTexture(0, 0, 0, 0.85)
dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
dialog.title:SetPoint("TOP", 0, -12)
dialog.hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
dialog.hint:SetPoint("TOP", 0, -36)

dialog.box = CreateFrame("EditBox", nil, dialog)
dialog.box:SetSize(440, 24)
dialog.box:SetPoint("TOP", 0, -56)
dialog.box:SetFontObject(ChatFontNormal)
dialog.box:SetTextInsets(6, 6, 0, 0)
dialog.box:SetAutoFocus(false)
dialog.box:SetMaxLetters(0)
dialog.box.bg = dialog.box:CreateTexture(nil, "BACKGROUND")
dialog.box.bg:SetAllPoints()
dialog.box.bg:SetColorTexture(1, 1, 1, 0.12)
dialog.box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
dialog.box:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)

dialog.action = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
dialog.action:SetSize(100, 22)
dialog.action:SetPoint("BOTTOM", -56, 14)
dialog.action:SetText("Import")
dialog.action:SetScript("OnClick", function()
	if ImportSettings(dialog.box:GetText()) then dialog:Hide() end
end)

dialog.close = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
dialog.close:SetSize(100, 22)
dialog.close:SetText(CLOSE or "Close")
dialog.close:SetScript("OnClick", function() dialog:Hide() end)

dialog.box:SetScript("OnEscapePressed", function() dialog:Hide() end)
dialog.box:SetScript("OnEnterPressed", function()
	if dialog.mode == "import" then dialog.action:Click() end
end)
dialog.box:SetScript("OnTextChanged", function(self, userInput)
	-- An export string stays as it is, whatever gets typed into it.
	if userInput and dialog.mode == "export" then
		self:SetText(dialog.exportText)
		self:HighlightText()
	end
end)

-- Opens on the next frame, so the chat box that ran the slash command has
-- finished closing first.
function dialog:Open(mode, title, hint, text)
	C_Timer.After(0, function()
		self.mode, self.exportText = mode, text
		self.title:SetText(title)
		self.hint:SetText(hint)
		self.action:SetShown(mode == "import")
		self.close:ClearAllPoints()
		self.close:SetPoint("BOTTOM", mode == "import" and 56 or 0, 14)
		self.box:SetText(text or "")
		self:Show()
	end)
end

-- If anything still gets blocked, say which function it was.
local blockWatch = CreateFrame("Frame")
blockWatch:RegisterEvent("ADDON_ACTION_FORBIDDEN")
blockWatch:RegisterEvent("ADDON_ACTION_BLOCKED")
blockWatch:SetScript("OnEvent", function(_, event, addon, fn)
	if addon == ADDON then Print(("%s: the game blocked %s"):format(event, tostring(fn))) end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
-- Names the frame under the cursor and its parents, to find the bag window
-- the Gamepad UI uses if it isn't one of the standard ones.
local function DescribeFrameUnderCursor()
	local focus = (GetMouseFoci and GetMouseFoci()[1]) or (GetMouseFocus and GetMouseFocus())
	if not focus then Print("No frame under the cursor.") return end
	local chain, frame = {}, focus
	while frame and #chain < 8 do
		chain[#chain + 1] = (frame.GetName and frame:GetName()) or ("<unnamed " .. (frame.GetObjectType and frame:GetObjectType() or "?") .. ">")
		frame = frame.GetParent and frame:GetParent()
	end
	Print("Under the cursor: " .. table.concat(chain, " < "))
end

-- Reports how the bag windows and our overlays are laid out, for when borders
-- don't show up where they should.
local function ReportFrames()
	local any
	for _, frame in ipairs(BagFrames()) do
		if frame and frame:IsShown() then
			any = true
			local overlay = overlays[frame]
			Print(("%s: %s level %d%s"):format(frame:GetName() or "?", frame:GetFrameStrata(),
				frame:GetFrameLevel(),
				overlay and (", overlay " .. overlay:GetFrameStrata() .. " level " .. overlay:GetFrameLevel())
					or ", no overlay yet"))
		end
	end
	if not any then Print("No standard bag window is open. Open your bags and try again.") end
	local shown, withCell = 0, 0
	for button in pairs(cells) do
		withCell = withCell + 1
		if button:IsVisible() then shown = shown + 1 end
	end
	Print(("%d buttons drawn on, %d of them visible."):format(withCell, shown))
end

SLASH_XANABAGS1 = "/xbags"
SlashCmdList.XANABAGS = function(msg)
	local cmd, rest = strsplit(" ", strtrim(msg or ""), 2)
	cmd = strlower(cmd or "")
	if cmd == "colors" or cmd == "colours" then
		ListColors()
	elseif cmd == "color" or cmd == "colour" then
		ColorCommand(strlower(rest or ""))
	elseif cmd == "export" then
		dialog:Open("export", "Export bag settings",
			"Click the box, then press Ctrl+C. Paste it into /xbags import on another character.",
			EXPORT_PREFIX .. Base64Encode(SettingsData()))
	elseif cmd == "import" then
		dialog:Open("import", "Import bag settings",
			"Click the box and paste an export string with Ctrl+V. It replaces all colour and dot settings.")
	elseif cmd == "stats" then
		ListDots()
	elseif cmd == "stat" then
		DotCommand(strlower(rest or ""))
	elseif cmd == "frame" then
		DescribeFrameUnderCursor()
	elseif cmd == "debug" then
		ReportFrames()
	elseif cmd == "sort" then
		local value = strlower(strtrim(rest or ""))
		if value == "on" or value == "off" then
			autoSort = (value == "on")
			SaveSettings()
			Print("Sorting the bags when they open: " .. (autoSort and "on" or "off"))
		elseif value == "" then
			if SortBagsNow() then Print("Sorting the bags.") else Print("Can't sort right now.") end
		else
			Print("Usage: /xbags sort   (sorts now), or /xbags sort on|off")
		end
	elseif cmd == "refresh" then
		ResetAndRefresh()
		Print("Bag borders refreshed.")
	elseif cmd == "seen" then
		MarkAllSeen()
		RequestRefresh()
		Print("All items marked as seen.")
	else
		Print("Borders mark gear (upgrade / equippable / can't equip), food, drink and new items;")
		Print("dots mark stats higher than on your equipped item.")
		Print("  /xbags colors  - show what each colour means")
		Print("  /xbags color <name> <hex | reset>  - change a colour")
		Print("  /xbags color reset  - put all colours back to default")
		Print("  /xbags stats  - show which stat dots are on")
		Print("  /xbags stat <stat | all> on|off  - show or hide a stat's dot")
		Print("  /xbags export | import  - copy colour and dot settings to another character")
		Print("  /xbags sort  - sort the bags now; /xbags sort on|off for sorting on open")
		Print("  /xbags refresh  - recheck every item")
		Print("  /xbags seen  - mark everything as seen now")
		Print("  /xbags frame  - name the window under the cursor (for bug reports)")
		Print("  /xbags debug  - report how the bag windows are drawn (for bug reports)")
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		HookBagFrames()
		for _, e in ipairs({
			"BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "PLAYER_EQUIPMENT_CHANGED",
			"PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_ENTERING_WORLD",
			"UPDATE_MACROS", "PLAYER_REGEN_ENABLED",
		}) do
			pcall(self.RegisterEvent, self, e)
		end
		local accountMacros, characterMacros = GetNumMacros()
		if (accountMacros or 0) + (characterMacros or 0) > 0 then OnMacrosReady() end
		RequestRefresh()
	elseif event == "UPDATE_MACROS" then
		OnMacrosReady()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if saveWanted then SaveSettings() end
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- Everything carried at login counts as seen. Wait a moment so the bag
		-- contents have loaded, or all of it would show up as new.
		if not seenCounts then
			C_Timer.After(2, function()
				if not seenCounts then MarkAllSeen() end
			end)
		end
		-- Fallback for a player with no macros at all, where no macro event may come.
		C_Timer.After(2, OnMacrosReady)
	elseif event == "PLAYER_LEVEL_UP" then
		-- The new level isn't applied to tooltips straight away.
		C_Timer.After(1, ResetAndRefresh)
	elseif event == "SKILL_LINES_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
		ResetAndRefresh()
	else
		RequestRefresh()
	end
end)
