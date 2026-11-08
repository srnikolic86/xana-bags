-- XanaBags
-- Gives chosen items in the bags a colored border. Alt+click an item, or press
-- R3 on it with a gamepad, to pick its color, either from the colors used before or a new one. The color
-- belongs to the item (by item ID), so it follows the item around the bags and
-- applies to every stack of it.
--
-- Opening the bags moves the colored items to the front, grouped by color, with
-- the hearthstone's color first. Quest items come next, then everything else.
-- Opening the bank does the same inside the bank.
--
-- The bank's contents are remembered at every visit, and /xbank lists them from
-- anywhere.

local ADDON = ...

local BORDER = 2
local HISTORY_MAX = 20
local HISTORY_COLUMNS = 10
local SWATCH_SIZE = 24
local SWATCH_GAP = 4
local HISTORY_ROWS = math.ceil(HISTORY_MAX / HISTORY_COLUMNS)
-- The fixed colors, for picking with a gamepad: strong colors, then neutrals and pale ones.
local PALETTE = {
	"ff0000", "ff8000", "ffd500", "80ff00", "00cc33", "00e6e6", "0080ff", "3333ff", "9933ff", "ff33cc",
	"ffffff", "bfbfbf", "808080", "262626", "8b5a2b", "ffb3b3", "ffe699", "b3ffb3", "b3e6ff", "d9b3ff",
}
local GRID_ROWS = HISTORY_ROWS + math.ceil(#PALETTE / HISTORY_COLUMNS)
local HEARTHSTONE_ID = 6948
-- Forever numbers its bank differently from other clients (the usual main bank
-- is -1), and the enums can't be trusted for this.
local BANK_MAIN_BAG = 6
local BANK_BAGS = { BANK_MAIN_BAG, 7, 8, 9, 10, 11, 12, 13, 14 }
local QUEST_ITEM_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12
local SORT_INTERVAL = 0.1     -- seconds between passes, giving the server time to answer
local SORT_MOVES_PER_PASS = 4
local SORT_MAX_PASSES = 300   -- gives up after about 30 seconds

local ItemLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
local BagItemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
local ItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local ItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local BagSlotCount = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local BagFreeSlots = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
local PickupItem = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99XanaBags:|r " .. tostring(msg))
end

---------------------------------------------------------------------------
-- Data. Colors are "rrggbb" strings.
---------------------------------------------------------------------------
local itemColors = {} -- itemID -> color
local history = {}    -- colors, most recently used first

local function ToHex(r, g, b)
	local function byte(v) return math.floor(v * 255 + 0.5) end
	return ("%02x%02x%02x"):format(byte(r), byte(g), byte(b))
end

local function FromHex(hex)
	return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

local function RememberColor(hex)
	for i = #history, 1, -1 do
		if history[i] == hex then table.remove(history, i) end
	end
	table.insert(history, 1, hex)
	history[HISTORY_MAX + 1] = nil
end

---------------------------------------------------------------------------
-- Storage. The Forever beta writes SavedVariables but never loads them back,
-- so the data lives in character-specific macros. A macro body holds only 255
-- characters, so it takes as many macros as the data needs. Each one stands on
-- its own, as ";"-separated records:
--   /xbagdata 2 h:ff0000,00ff00;ff0000:6948,2589;00ff00:117
-- "h" is the color history, newest first (it always fits in the first macro);
-- the others are a color and the IDs of the items that have it.
--
-- Macros from the old XanaBags (/xbagdata 1|...) aren't read, and are reused by
-- the first save.
---------------------------------------------------------------------------
local MACRO_NAME = "XanaBags"
local MACRO_ICON = 134400 -- the question mark
local DATA_TAG = "/xbagdata "
local LINE_START = DATA_TAG .. "2 "
local MACRO_MAX = 255
local MACRO_SCAN_END = 300 -- past the last possible macro index on any client
local macrosReady, dataLoaded, saveWanted
local warnedMacro = {} -- data tag -> true once the player has been told

-- Only character-specific macros count: General (account) macros fill indexes
-- 1..numAccount with no gaps and character macros come after them.
local function FindDataMacros(tag)
	local found = {}
	for i = (GetNumMacros() or 0) + 1, MACRO_SCAN_END do
		local name, _, body = GetMacroInfo(i)
		if name and body and body:find(tag, 1, true) then found[#found + 1] = i end
	end
	return found
end

-- The full macro bodies for the current data. Sorted, so unchanged data gives
-- unchanged macros.
local function BuildBodies()
	local byColor, colors = {}, {}
	for id, hex in pairs(itemColors) do
		if not byColor[hex] then
			byColor[hex] = {}
			colors[#colors + 1] = hex
		end
		table.insert(byColor[hex], id)
	end
	table.sort(colors)

	local room = MACRO_MAX - #LINE_START
	local bodies, line, lineColor = {}, "", nil
	local function Flush()
		if line ~= "" then bodies[#bodies + 1] = LINE_START .. line end
		line, lineColor = "", nil
	end

	if #history > 0 then
		line, lineColor = "h:" .. table.concat(history, ","), "h"
	end
	for _, hex in ipairs(colors) do
		table.sort(byColor[hex])
		for _, id in ipairs(byColor[hex]) do
			local piece
			if lineColor == hex then
				piece = "," .. id
			else
				piece = (line ~= "" and ";" or "") .. hex .. ":" .. id
			end
			if #line + #piece > room then
				Flush()
				piece = hex .. ":" .. id
			end
			line, lineColor = line .. piece, hex
		end
	end
	Flush()
	return bodies
end

-- Adds a macro's data to what is in memory. What is in memory wins, so a color
-- set before the macros loaded isn't lost.
local function ParseData(data)
	for record in data:gmatch("[^;]+") do
		local key, list = record:match("^(%w+):(.*)$")
		if key == "h" then
			for hex in list:gmatch("%x%x%x%x%x%x") do
				local known = false
				for _, h in ipairs(history) do known = known or h == hex end
				if not known and #history < HISTORY_MAX then history[#history + 1] = strlower(hex) end
			end
		elseif key and key:match("^%x%x%x%x%x%x$") then
			for id in list:gmatch("%d+") do
				id = tonumber(id)
				itemColors[id] = itemColors[id] or strlower(key)
			end
		end
	end
end

-- Returns true if any macro had data.
local function LoadData()
	local found = false
	for _, index in ipairs(FindDataMacros(DATA_TAG)) do
		local _, _, body = GetMacroInfo(index)
		local data = body:match(LINE_START .. "([^\n]*)")
		if data then
			found = true
			ParseData(data)
		end
	end
	return found
end

-- Makes the macros carrying a tag hold exactly these bodies, leaving a macro
-- alone if it already does.
local function WriteMacros(tag, baseName, bodies, fullWarning)
	local existing = FindDataMacros(tag)
	for i, body in ipairs(bodies) do
		local index = existing[i]
		if index then
			local _, _, old = GetMacroInfo(index)
			if old ~= body then EditMacro(index, nil, nil, body) end
		else
			local name = i == 1 and baseName or (baseName .. " " .. i)
			local ok, created = pcall(CreateMacro, name, MACRO_ICON, body, true)
			if not ok or not created or created == 0 then
				if not warnedMacro[tag] then
					warnedMacro[tag] = true
					Print(fullWarning)
				end
				break
			end
		end
	end
	-- Highest first, because deleting a macro moves the ones after it.
	for i = #existing, #bodies + 1, -1 do DeleteMacro(existing[i]) end
end

-- Macros can't be edited in combat, and must not be written before the existing
-- ones have loaded (or a second set would be created).
local function SaveData()
	if InCombatLockdown() or not macrosReady then
		saveWanted = true
		return
	end
	saveWanted = nil
	WriteMacros(DATA_TAG, MACRO_NAME, BuildBodies(),
		"Couldn't create a XanaBags macro (are this character's macro slots full?). " ..
		"Some item colors won't survive a logout until one is free.")
end

-- The macro's data line. Deliberately does nothing.
SLASH_XANABAGSDATA1 = "/xbagdata"
SlashCmdList.XANABAGSDATA = function() end

-- The bank as last seen has macros of its own, with a different tag so the color
-- macros never pick them up:
--   /xbagbank 1 2589x20,6948,14047x7
-- Item IDs, with "x" and the total count if it is more than one. "-" stands for
-- an empty bank, so that a bank seen empty differs from one never seen.
local BANK_MACRO_NAME = "XanaBags Bank"
local BANK_TAG = "/xbagbank "
local BANK_LINE_START = BANK_TAG .. "1 "
local BANK_EMPTY = "-"
local bankItems -- itemID -> total count at the last visit; nil if none is known
local bankSaveWanted

-- Sorted, so an unchanged bank gives unchanged macros.
local function BuildBankBodies()
	local ids = {}
	for id in pairs(bankItems) do ids[#ids + 1] = id end
	table.sort(ids)

	local room = MACRO_MAX - #BANK_LINE_START
	local bodies, line = {}, ""
	for _, id in ipairs(ids) do
		local count = bankItems[id]
		local piece = count > 1 and (id .. "x" .. count) or tostring(id)
		if #line + 1 + #piece > room then
			bodies[#bodies + 1] = BANK_LINE_START .. line
			line = ""
		end
		line = line == "" and piece or (line .. "," .. piece)
	end
	bodies[#bodies + 1] = BANK_LINE_START .. (line ~= "" and line or BANK_EMPTY)
	return bodies
end

local function LoadBank()
	local loaded
	for _, index in ipairs(FindDataMacros(BANK_TAG)) do
		local _, _, body = GetMacroInfo(index)
		local data = body:match(BANK_LINE_START .. "([^\n]*)")
		if data then
			loaded = loaded or {}
			for id, count in data:gmatch("(%d+)x?(%d*)") do
				loaded[tonumber(id)] = tonumber(count) or 1
			end
		end
	end
	bankItems = loaded
end

local function SaveBank()
	if InCombatLockdown() or not macrosReady then
		bankSaveWanted = true
		return
	end
	bankSaveWanted = nil
	WriteMacros(BANK_TAG, BANK_MACRO_NAME, BuildBankBodies(),
		"Couldn't create a XanaBags Bank macro (are this character's macro slots full?). " ..
		"Part of the bank list won't survive a logout until one is free.")
end

-- The bank macros' data line. Deliberately does nothing.
SLASH_XANABAGSBANKDATA1 = "/xbagbank"
SlashCmdList.XANABAGSBANKDATA = function() end

---------------------------------------------------------------------------
-- Borders
---------------------------------------------------------------------------
-- Nothing is drawn on Blizzard's bag buttons themselves. Each bag window gets
-- one frame of ours, and every button's border is plain textures in that frame,
-- anchored to the button. Frames placed on the buttons made the Gamepad UI
-- recalculate what its cursor can interact with, which got the addon blocked
-- ("SetPreferredGamepadInteractTraget"). Textures aren't interactive, and these
-- frames are created once and never shown or hidden afterwards.
local overlays = setmetatable({}, { __mode = "k" }) -- bag window -> our frame
local cells = setmetatable({}, { __mode = "k" })    -- item button -> its four edges
local hooked = setmetatable({}, { __mode = "k" })   -- item button -> true

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

local function GetCell(button)
	local cell = cells[button]
	if cell then return cell end
	local overlay = GetOverlay(button:GetParent())
	cell = {}
	local function Edge(fromPoint, toPoint, horizontal)
		local t = overlay:CreateTexture(nil, "OVERLAY", nil, 3)
		t:SetPoint(fromPoint, button, fromPoint)
		t:SetPoint(toPoint, button, toPoint)
		if horizontal then t:SetHeight(BORDER) else t:SetWidth(BORDER) end
		t:Hide()
		cell[#cell + 1] = t
	end
	Edge("TOPLEFT", "TOPRIGHT", true)
	Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
	Edge("TOPLEFT", "BOTTOMLEFT", false)
	Edge("TOPRIGHT", "BOTTOMRIGHT", false)
	cells[button] = cell
	return cell
end

local function SetBorder(button, hex)
	local cell = cells[button]
	if not hex then
		if cell then
			for _, t in ipairs(cell) do t:Hide() end
		end
		return
	end
	cell = GetCell(button)
	local r, g, b = FromHex(hex)
	for _, t in ipairs(cell) do
		t:SetColorTexture(r, g, b, 1)
		t:Show()
	end
end

-- Our textures live in a frame of our own, so they don't disappear with the bag
-- window. Everything belonging to a hidden button is hidden by hand.
local function HideHiddenCells()
	for button in pairs(cells) do
		-- IsVisible, not IsShown: a button in a closed bag window is still "shown".
		if not button:IsVisible() then SetBorder(button, nil) end
	end
end

---------------------------------------------------------------------------
-- Bag windows
---------------------------------------------------------------------------
local function ButtonBagSlot(button)
	if button.GetBankTabID and button.GetContainerSlotID then
		return button:GetBankTabID(), button:GetContainerSlotID()
	end
	local name = button.GetName and button:GetName()
	if name and name:find("^BankFrameItem") then return BANK_MAIN_BAG, button:GetID() end
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

local bankOpen -- between BANKFRAME_OPENED and BANKFRAME_CLOSED

-- The bank's main slots, from a bank panel if the client has one, or else by name.
local function ForEachBankButton(fn)
	local panel = BankPanel
	if panel and panel.EnumerateValidItems then
		-- Depending on the kind of list, the button is the key or the value.
		for key, value in panel:EnumerateValidItems() do
			fn(type(key) == "table" and key or value)
		end
		return
	end
	local i = 1
	while _G["BankFrameItem" .. i] do
		fn(_G["BankFrameItem" .. i])
		i = i + 1
	end
end

-- Bank bags open in ordinary bag windows, so those come from the loop below. The
-- main bank counts as window 0, ahead of them when sorting by position.
local function ForEachBagButton(fn)
	if bankOpen then
		ForEachBankButton(function(button) fn(button, 0) end)
	end
	for frameIndex, frame in ipairs(BagFrames()) do
		if frame and frame:IsShown() then
			if frame.EnumerateValidItems then
				for _, button in frame:EnumerateValidItems() do fn(button, frameIndex) end
			else
				local name = frame:GetName()
				for j = 1, frame.size or 36 do
					local button = _G[name .. "Item" .. j]
					if button then fn(button, frameIndex) end
				end
			end
		end
	end
end

local OnItemClick -- defined with the picker below
local hoveredButton -- the item button last entered: the gamepad's selection too

local function UpdateButton(button)
	if not hooked[button] then
		hooked[button] = true
		button:HookScript("OnClick", OnItemClick)
		button:HookScript("OnEnter", function(self) hoveredButton = self end)
		button:HookScript("OnLeave", function(self)
			if hoveredButton == self then hoveredButton = nil end
		end)
	end
	if not button:IsVisible() then
		SetBorder(button, nil)
		return
	end
	local id = BagItemID(ButtonBagSlot(button))
	SetBorder(button, id and itemColors[id])
end

local StartSort -- defined with the sorting below
local UpdatePadBinding -- defined with the gamepad code below
local RememberBank, RedrawBankWindow -- defined with the bank list below
local bagsOpen  -- were the bags open at the last refresh?
local bankSorted -- has the bank been sorted since it opened?

local refreshQueued
local function RequestRefresh()
	if refreshQueued then return end
	refreshQueued = true
	-- Next frame, so the bag window has filled its buttons first.
	C_Timer.After(0, function()
		refreshQueued = false
		HideHiddenCells()
		for _, frame in ipairs(BagFrames()) do
			if frame and frame:IsShown() then LiftOverlay(frame) end
		end
		if bankOpen then
			ForEachBankButton(function(button) LiftOverlay(button:GetParent()) end)
		end
		ForEachBagButton(UpdateButton)
		if not AnyBagShown() then
			bagsOpen = nil
		elseif not bagsOpen then
			bagsOpen = true
			StartSort("bags")
		end
		if bankOpen and not bankSorted then
			bankSorted = true
			StartSort("bank")
		end
		if bankOpen then RememberBank() end
		RedrawBankWindow()
		UpdatePadBinding()
	end)
end

---------------------------------------------------------------------------
-- Picker window. Like the addon's other windows it is not registered in
-- UISpecialFrames, and it takes no keyboard focus: both got the addons blocked
-- on the Forever beta.
---------------------------------------------------------------------------
local PICKER_PADDING = 12
local pickerWidth = HISTORY_COLUMNS * SWATCH_SIZE + (HISTORY_COLUMNS - 1) * SWATCH_GAP + 2 * PICKER_PADDING
local BUTTON_WIDTH = math.floor((pickerWidth - 2 * PICKER_PADDING - 2 * SWATCH_GAP) / 3)

local picker = CreateFrame("Frame", "XanaBagsPicker", UIParent)
picker:SetSize(pickerWidth, 252)
picker:SetFrameStrata("FULLSCREEN_DIALOG")
picker:SetClampedToScreen(true)
picker:EnableMouse(true)
picker:Hide()
picker.bg = picker:CreateTexture(nil, "BACKGROUND")
picker.bg:SetAllPoints()
picker.bg:SetColorTexture(0, 0, 0, 0.85)

-- The item's icon, on a square showing its current color.
picker.iconBack = picker:CreateTexture(nil, "ARTWORK", nil, 1)
picker.iconBack:SetSize(32, 32)
picker.iconBack:SetPoint("TOPLEFT", PICKER_PADDING, -PICKER_PADDING)
picker.icon = picker:CreateTexture(nil, "ARTWORK", nil, 2)
picker.icon:SetPoint("TOPLEFT", picker.iconBack, "TOPLEFT", BORDER, -BORDER)
picker.icon:SetPoint("BOTTOMRIGHT", picker.iconBack, "BOTTOMRIGHT", -BORDER, BORDER)

picker.title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
picker.title:SetPoint("LEFT", picker.iconBack, "RIGHT", 8, 0)
picker.title:SetPoint("RIGHT", picker, "RIGHT", -PICKER_PADDING, 0)
picker.title:SetJustifyH("LEFT")

picker.label = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
picker.label:SetPoint("TOPLEFT", PICKER_PADDING, -52)
picker.label:SetText("Previous colors")

picker.empty = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
picker.empty:SetPoint("TOPLEFT", PICKER_PADDING, -72)
picker.empty:SetText("None yet. Choose a color below, or New color.")

picker.paletteLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
picker.paletteLabel:SetPoint("TOPLEFT", PICKER_PADDING, -126)
picker.paletteLabel:SetText("Colors")

picker.hint = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
picker.hint:SetPoint("TOP", 0, -198)
picker.hint:SetText("D-pad: move    A: apply    X: remove    B: close")

-- Sets the color without saving it. The color picker uses this directly to show
-- its color on the item while the player is still choosing.
local function ShowItemColor(id, hex)
	itemColors[id] = hex
	RequestRefresh()
end

local function SetItemColor(id, hex)
	RememberColor(hex)
	ShowItemColor(id, hex)
	SaveData()
end

-- swatchGrid[row][column]: the history's rows, then the palette's. A swatch with
-- no hex has no color yet and is hidden.
local swatchGrid = {}
local function MakeSwatch(row, column, top)
	local swatch = CreateFrame("Button", nil, picker)
	swatch.row, swatch.column = row, column
	swatch:SetSize(SWATCH_SIZE, SWATCH_SIZE)
	swatch:SetPoint("TOPLEFT", PICKER_PADDING + (column - 1) * (SWATCH_SIZE + SWATCH_GAP), top)
	swatch.back = swatch:CreateTexture(nil, "BACKGROUND")
	swatch.back:SetAllPoints()
	swatch.color = swatch:CreateTexture(nil, "ARTWORK")
	swatch.color:SetPoint("TOPLEFT", BORDER, -BORDER)
	swatch.color:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
	swatch.hover = swatch:CreateTexture(nil, "HIGHLIGHT")
	swatch.hover:SetAllPoints()
	swatch.hover:SetColorTexture(1, 1, 1, 0.25)
	swatch:SetScript("OnClick", function(self)
		SetItemColor(picker.itemID, self.hex)
		picker:Hide()
	end)
	swatchGrid[row] = swatchGrid[row] or {}
	swatchGrid[row][column] = swatch
	return swatch
end

for row = 1, GRID_ROWS do
	local inPalette = row > HISTORY_ROWS
	local top = inPalette and (-142 - (row - HISTORY_ROWS - 1) * (SWATCH_SIZE + SWATCH_GAP))
		or (-68 - (row - 1) * (SWATCH_SIZE + SWATCH_GAP))
	for column = 1, HISTORY_COLUMNS do
		local swatch = MakeSwatch(row, column, top)
		if inPalette then
			swatch.hex = PALETTE[(row - HISTORY_ROWS - 1) * HISTORY_COLUMNS + column]
			swatch.color:SetColorTexture(FromHex(swatch.hex))
		end
	end
end

local function UpdatePicker()
	local current = itemColors[picker.itemID]
	picker.title:SetText(picker.link)
	picker.icon:SetTexture(select(5, ItemInfoInstant(picker.itemID)))
	if current then
		local r, g, b = FromHex(current)
		picker.iconBack:SetColorTexture(r, g, b, 1)
	else
		picker.iconBack:SetColorTexture(0.25, 0.25, 0.25, 1)
	end
	for row = 1, GRID_ROWS do
		for column = 1, HISTORY_COLUMNS do
			local swatch = swatchGrid[row][column]
			if row <= HISTORY_ROWS then
				local hex = history[(row - 1) * HISTORY_COLUMNS + column]
				swatch.hex = hex
				swatch:SetShown(hex ~= nil)
				if hex then swatch.color:SetColorTexture(FromHex(hex)) end
			end
			-- A gold frame marks the gamepad's selection, a white one the item's color.
			if picker.padMode and swatch == picker.selected then
				swatch.back:SetColorTexture(1, 0.8, 0, 1)
			else
				local frame = swatch.hex == current and 1 or 0.25
				swatch.back:SetColorTexture(frame, frame, frame, 1)
			end
		end
	end
	picker.empty:SetShown(#history == 0)
	picker.hint:SetShown(picker.padMode == true)
	picker.remove:SetEnabled(current ~= nil)
end

---------------------------------------------------------------------------
-- Choosing a new color with the game's color picker. Both its OK button and
-- its Cancel button just hide it, and the cancel callback is the only way to
-- tell them apart, in an order that differs between client versions. So the
-- outcome is decided a frame after it hides: no cancel call means OK.
---------------------------------------------------------------------------
local colorSession -- { itemID, previous, cancelled } while the picker is open
local FirstSelection -- defined with the gamepad code below
local colorPickerHooked

local function OnColorPickerHidden()
	local session = colorSession
	if not session then return end
	C_Timer.After(0, function()
		if colorSession ~= session then return end
		colorSession = nil
		if session.cancelled then
			if AnyBagShown() then
				UpdatePicker()
				picker:Show()
			end
		else
			SetItemColor(session.itemID, ToHex(ColorPickerFrame:GetColorRGB()))
		end
	end)
end

local function ChooseNewColor()
	if not ColorPickerFrame then
		Print("This client has no color picker.")
		return
	end
	if not colorPickerHooked then
		colorPickerHooked = true
		ColorPickerFrame:HookScript("OnHide", OnColorPickerHidden)
	end
	if ColorPickerFrame:IsShown() then ColorPickerFrame:Hide() end

	local id = picker.itemID
	local session = { itemID = id, previous = itemColors[id] }
	local r, g, b = FromHex(session.previous or history[1] or "ffffff")
	local function Preview()
		if colorSession == session then ShowItemColor(id, ToHex(ColorPickerFrame:GetColorRGB())) end
	end
	local function Cancel()
		session.cancelled = true
		if colorSession == session then ShowItemColor(id, session.previous) end
	end

	picker:Hide()
	colorSession = session
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r, g = g, b = b, hasOpacity = false, swatchFunc = Preview, cancelFunc = Cancel,
		})
	else
		ColorPickerFrame.hasOpacity = false
		ColorPickerFrame.opacityFunc = nil
		ColorPickerFrame.previousValues = { r, g, b }
		ColorPickerFrame.func = Preview
		ColorPickerFrame.cancelFunc = Cancel
		ColorPickerFrame:SetColorRGB(r, g, b)
		ColorPickerFrame:Show()
	end
end

local function PickerButton(text, index, onClick)
	local button = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
	button:SetSize(BUTTON_WIDTH, 22)
	button:SetPoint("BOTTOMLEFT", PICKER_PADDING + (index - 1) * (BUTTON_WIDTH + SWATCH_GAP), PICKER_PADDING)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

PickerButton("New color", 1, ChooseNewColor)
picker.remove = PickerButton("Remove", 2, function()
	itemColors[picker.itemID] = nil
	RequestRefresh()
	SaveData()
	picker:Hide()
end)
PickerButton(CLOSE or "Close", 3, function() picker:Hide() end)

-- Beside the cursor, or beside the button if one is given (the gamepad has no
-- cursor). As a position on the screen: anchoring a frame to the bag button could
-- upset the Gamepad UI the same way a frame on it does.
local function OpenPicker(id, link, button)
	picker.itemID, picker.link = id, link
	picker.selected = nil
	if picker.padMode then
		-- History first, so that the selection can be chosen among current colors.
		UpdatePicker()
		picker.selected = FirstSelection()
	end
	UpdatePicker()
	local uiScale = UIParent:GetEffectiveScale()
	local x, y
	local left, top = button and button:GetLeft(), button and button:GetTop()
	if left and top then
		local scale = button:GetEffectiveScale() / uiScale
		x, y = left * scale - 8, top * scale
	else
		x, y = GetCursorPosition()
		x, y = x / uiScale - 12, y / uiScale + 12
	end
	picker:ClearAllPoints()
	picker:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x, y)
	picker:Show()
end

-- Alt+click, with either mouse button.
function OnItemClick(button)
	if not IsAltKeyDown() then return end
	if colorSession or (CursorHasItem and CursorHasItem()) then return end
	if picker.padMode then picker:Hide() end
	local bag, slot = ButtonBagSlot(button)
	local id, link = BagItemID(bag, slot), ItemLink(bag, slot)
	if id and link then OpenPicker(id, link) end
end

---------------------------------------------------------------------------
-- Sorting when the bags open. Items move one swap at a time, and the server
-- locks both slots until it has answered. So each pass reads the bags afresh,
-- works out the order they should be in, makes a few swaps among unlocked slots
-- and comes back later. Reading afresh also copes with the game merging two
-- partial stacks instead of swapping them.
--
-- The bags and the bank each sort within themselves; nothing moves between them.
-- Special bags (soul, herb, quiver...) are left alone, since most items can't go
-- in them.
---------------------------------------------------------------------------
local function ItemState(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local info = C_Container.GetContainerItemInfo(bag, slot)
		if info then return info.stackCount or 1, info.isLocked end
		return 1, false
	end
	local _, count, locked = GetContainerItemInfo(bag, slot)
	return count or 1, locked
end

-- By the item's class, or the game's flag on the bag slot, which also covers
-- items that start a quest.
local function IsQuestItem(id, bag, slot)
	if select(6, ItemInfoInstant(id)) == QUEST_ITEM_CLASS then return true end
	if C_Container and C_Container.GetContainerItemQuestInfo then
		local info = C_Container.GetContainerItemQuestInfo(bag, slot)
		return info ~= nil and (info.isQuestItem or info.questID ~= nil)
	end
	if GetContainerItemQuestInfo then
		local isQuestItem, questID = GetContainerItemQuestInfo(bag, slot)
		return isQuestItem or questID ~= nil
	end
	return false
end

-- The slots of the normal bags in the order the player sees them: left to right,
-- top to bottom in each window. The game's own slot numbers don't say where a
-- slot appears. Slots with no button on screen (a closed bag) come last.
local function ReadSlots(bags)
	local onScreen = {}
	ForEachBagButton(function(button, frameIndex)
		local top, left = button:GetTop(), button:GetLeft()
		if top and left and button:IsVisible() then
			local bag, slot = ButtonBagSlot(button)
			onScreen[bag * 1000 + slot] = { frameIndex, -math.floor(top + 0.5), math.floor(left + 0.5) }
		end
	end)

	local slots = {}
	for _, bag in ipairs(bags) do
		local _, family = BagFreeSlots(bag)
		if (family or 0) == 0 then
			for slot = 1, BagSlotCount(bag) or 0 do
				local s = { bag = bag, slot = slot, screen = onScreen[bag * 1000 + slot] }
				s.id = BagItemID(bag, slot)
				if s.id then
					s.link = ItemLink(bag, slot) or ""
					s.count, s.locked = ItemState(bag, slot)
					s.name = s.link:match("%[(.-)%]") or ""
					s.signature = s.link .. "x" .. s.count
				end
				slots[#slots + 1] = s
			end
		end
	end

	table.sort(slots, function(a, b)
		if a.screen and b.screen then
			for i = 1, 3 do
				if a.screen[i] ~= b.screen[i] then return a.screen[i] < b.screen[i] end
			end
		elseif a.screen or b.screen then
			return a.screen ~= nil
		end
		if a.bag ~= b.bag then return a.bag < b.bag end
		return a.slot < b.slot
	end)
	return slots
end

-- Whether color a goes before color b, which is different: the hearthstone's
-- color first, then the others, then no color.
local function ColorComesFirst(a, b, firstColor)
	if not a then return false end
	if not b then return true end
	if a == firstColor then return true end
	if b == firstColor then return false end
	return a < b
end

-- The items in the order they should end up in, or nil if none are colored or
-- quest items: the hearthstone's color, the other colors, the uncolored quest
-- items, then everything else. The last group has no order of its own, so an
-- item a swap moved out of the way stays where it landed. Within a group: by
-- name, and the fullest stack first.
local function WantedOrder(slots)
	local front, rest = {}, {}
	for position, s in ipairs(slots) do
		if s.id then
			s.position = position
			s.hex = itemColors[s.id]
			if s.hex or IsQuestItem(s.id, s.bag, s.slot) then
				front[#front + 1] = s
			else
				rest[#rest + 1] = s
			end
		end
	end
	if #front == 0 then return nil end
	local firstColor = itemColors[HEARTHSTONE_ID]
	table.sort(front, function(a, b)
		if a.hex ~= b.hex then return ColorComesFirst(a.hex, b.hex, firstColor) end
		if a.name ~= b.name then return a.name < b.name end
		if a.id ~= b.id then return a.id < b.id end
		if a.count ~= b.count then return a.count > b.count end
		if a.link ~= b.link then return a.link < b.link end
		return a.position < b.position
	end)
	for _, s in ipairs(rest) do front[#front + 1] = s end
	return front
end

-- Clicks one slot and then the other. If the item doesn't land, it goes back
-- rather than staying on the cursor. Returns false if nothing could be moved.
local function SwapSlots(from, to)
	PickupItem(from.bag, from.slot)
	if not CursorHasItem() then return false end
	PickupItem(to.bag, to.slot)
	if CursorHasItem() then
		ClearCursor()
		return false
	end
	return true
end

-- Makes up to SORT_MOVES_PER_PASS swaps. Returns true when everything is in place.
local function SortPass(slots, wanted)
	local busy = {}
	for _, s in ipairs(slots) do
		if s.locked then busy[s] = true end
	end
	local finished, moves = true, 0
	for i, want in ipairs(wanted) do
		local here = slots[i]
		if here.signature ~= want.signature then
			finished = false
			if not busy[here] and moves < SORT_MOVES_PER_PASS then
				for j = i + 1, #slots do
					local source = slots[j]
					if source.signature == want.signature and not busy[source] then
						busy[here], busy[source] = true, true
						if not SwapSlots(source, here) then return false end
						moves = moves + 1
						break
					end
				end
			end
		end
	end
	return finished
end

local sorts = {
	bags = {
		label = "bags",
		IsOpen = AnyBagShown,
		Bags = function()
			local bags = {}
			for bag = 0, NUM_BAG_SLOTS or 4 do bags[#bags + 1] = bag end
			return bags
		end,
	},
	bank = {
		label = "bank",
		IsOpen = function() return bankOpen end,
		Bags = function() return BANK_BAGS end,
	},
}

-- Stops for anything that needs the cursor or the window to itself; the next time
-- the window opens it starts over. job.passes is nil when no sort is running.
local function SortStep(job)
	if InCombatLockdown() or not job.IsOpen() or colorSession or CursorHasItem()
		or (SpellIsTargeting and SpellIsTargeting()) then
		job.passes = nil
		return
	end
	job.passes = job.passes + 1
	local slots = ReadSlots(job.Bags())
	local wanted = WantedOrder(slots)
	if not wanted or SortPass(slots, wanted) then
		job.passes = nil
	elseif job.passes >= SORT_MAX_PASSES then
		job.passes = nil
		Print(("Couldn't finish sorting the %s. Is an item locked, for example in a trade?"):format(job.label))
	else
		C_Timer.After(SORT_INTERVAL, function() SortStep(job) end)
	end
end

-- Not before the macros have loaded, when no item has its color yet.
function StartSort(name)
	local job = sorts[name]
	if job.passes or not macrosReady then return end
	job.passes = 0
	SortStep(job)
end

---------------------------------------------------------------------------
-- Gamepad. While the bags or bank are open, R3 opens the picker for the selected
-- item. While a picker opened that way is showing, the D-pad, A, X, B and Escape
-- control it. Override bindings can't change in combat, and leaving A or the
-- D-pad taken over would be far worse than losing the picker, so the picker
-- closes the moment combat starts (PLAYER_REGEN_DISABLED comes just before the
-- lockdown).
---------------------------------------------------------------------------
local PAD_OPEN_KEY = "PADRSTICK"
local PAD_NAV_KEYS = {
	PADDUP = "UP", PADDDOWN = "DOWN", PADDLEFT = "LEFT", PADDRIGHT = "RIGHT",
	PAD1 = "APPLY", PAD3 = "REMOVE", PAD2 = "CLOSE", ESCAPE = "CLOSE",
}
local padOwner = CreateFrame("Frame")
local navOwner = CreateFrame("Frame")
local padBound, navBound = false, false

function UpdatePadBinding()
	local wanted = (AnyBagShown() or bankOpen) and true or false
	if wanted == padBound or InCombatLockdown() then return end
	if wanted then
		SetOverrideBindingClick(padOwner, true, PAD_OPEN_KEY, "XanaBagsPadOpen", "LeftButton")
	else
		ClearOverrideBindings(padOwner)
	end
	padBound = wanted
end

local function ReleaseNavKeys()
	if navBound and not InCombatLockdown() then
		ClearOverrideBindings(navOwner)
		navBound = false
	end
end

-- The last column with a color in a row, or nil if the row is empty. Rows fill
-- from the left, so everything before it has a color too.
local function LastColumn(row)
	for column = HISTORY_COLUMNS, 1, -1 do
		if swatchGrid[row][column].hex then return column end
	end
end

local function MoveSelection(direction)
	local row, column = picker.selected.row, picker.selected.column
	if direction == "LEFT" or direction == "RIGHT" then
		local step = direction == "RIGHT" and 1 or -1
		column = (column - 1 + step) % LastColumn(row) + 1
	else
		local step = direction == "DOWN" and 1 or -1
		for _ = 1, GRID_ROWS do
			row = (row - 1 + step) % GRID_ROWS + 1
			local last = LastColumn(row)
			if last then
				column = math.min(column, last)
				break
			end
		end
	end
	picker.selected = swatchGrid[row][column]
	UpdatePicker()
end

-- A, X and B act when released, like the rings: acting on the press would hand
-- the key back to the game while it is still down, and its release would reach
-- whatever is behind the picker.
local armed = {}
local padNav = CreateFrame("Button", "XanaBagsPadNav", UIParent)
padNav:RegisterForClicks("AnyDown", "AnyUp")
padNav:SetScript("OnClick", function(_, action, down)
	if not picker:IsShown() or not picker.padMode then return end
	if action == "APPLY" or action == "REMOVE" or action == "CLOSE" then
		if down then
			armed[action] = true
		elseif armed[action] then
			armed[action] = nil
			if action == "APPLY" then
				picker.selected:Click()
			elseif action == "CLOSE" then
				picker:Hide()
			elseif itemColors[picker.itemID] then
				picker.remove:Click()
			end
		end
	elseif down then
		MoveSelection(action)
	end
end)

function FirstSelection()
	local current = itemColors[picker.itemID]
	local first
	for row = 1, GRID_ROWS do
		for column = 1, HISTORY_COLUMNS do
			local swatch = swatchGrid[row][column]
			if swatch.hex then
				first = first or swatch
				if swatch.hex == current then return swatch end
			end
		end
	end
	return first
end

local function OpenPickerFromPad()
	if picker:IsShown() then
		picker:Hide()
		return
	end
	if colorSession or CursorHasItem() then return end
	if InCombatLockdown() then
		Print("The color window can't open from the gamepad in combat.")
		return
	end
	if not hoveredButton or not hoveredButton:IsVisible() then
		Print("Select an item in your bags or bank first.")
		return
	end
	local bag, slot = ButtonBagSlot(hoveredButton)
	local id, link = BagItemID(bag, slot), ItemLink(bag, slot)
	if not id or not link then return end

	wipe(armed)
	picker.padMode = true
	for key, action in pairs(PAD_NAV_KEYS) do
		SetOverrideBindingClick(navOwner, true, key, "XanaBagsPadNav", action)
	end
	navBound = true
	OpenPicker(id, link, hoveredButton)
end

local padOpen = CreateFrame("Button", "XanaBagsPadOpen", UIParent)
padOpen:RegisterForClicks("AnyDown", "AnyUp")
padOpen:SetScript("OnClick", function(_, _, down)
	if down then OpenPickerFromPad() end
end)

picker:SetScript("OnHide", function()
	picker.padMode = false
	ReleaseNavKeys()
end)

---------------------------------------------------------------------------
-- The bank as last seen. What is in the bank can only be read while it is open,
-- so the list is refreshed on every change during a visit. The window is opened
-- by /xbank, and running that again closes it, which is all a gamepad needs. It
-- doesn't scroll, for the same reason: the columns grow to fit, and the window
-- shrinks if they don't fit across the screen.
--
-- Its rows are plain textures and text in the one frame, like the borders, and
-- like the picker it takes no keyboard focus and isn't in UISpecialFrames.
---------------------------------------------------------------------------
local BANK_ICON_SIZE = 20
local BANK_ROW_STEP = 24
local BANK_COLUMN_WIDTH = 230
local BANK_COUNT_WIDTH = 40
local BANK_PADDING = 12
local BANK_ROWS_TOP = 40
local BANK_MIN_WIDTH = 300
local BANK_SCREEN_MARGIN = 40

-- Nothing is kept if the bank's bags have no size yet: they can't be read, and
-- that mustn't replace what was remembered with an empty bank.
function RememberBank()
	local seen, slots = {}, 0
	for _, bag in ipairs(BANK_BAGS) do
		local size = BagSlotCount(bag) or 0
		slots = slots + size
		for slot = 1, size do
			local id = BagItemID(bag, slot)
			if id then seen[id] = (seen[id] or 0) + ItemState(bag, slot) end
		end
	end
	if slots == 0 then return end
	bankItems = seen
	SaveBank()
end

local bankWindow = CreateFrame("Frame", "XanaBagsBankList", UIParent)
bankWindow:SetPoint("CENTER")
bankWindow:SetFrameStrata("FULLSCREEN_DIALOG") -- above the bag windows' borders
bankWindow:SetClampedToScreen(true)
bankWindow:EnableMouse(true)
bankWindow:Hide()
bankWindow.bg = bankWindow:CreateTexture(nil, "BACKGROUND")
bankWindow.bg:SetAllPoints()
bankWindow.bg:SetColorTexture(0, 0, 0, 0.85)

bankWindow.title = bankWindow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
bankWindow.title:SetPoint("TOPLEFT", BANK_PADDING, -BANK_PADDING)
bankWindow.title:SetText("Bank, as of your last visit")

bankWindow.empty = bankWindow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
bankWindow.empty:SetPoint("TOPLEFT", BANK_PADDING, -BANK_ROWS_TOP)

bankWindow.close = CreateFrame("Button", nil, bankWindow, "UIPanelButtonTemplate")
bankWindow.close:SetSize(70, 22)
bankWindow.close:SetPoint("TOPRIGHT", -BANK_PADDING, -8)
bankWindow.close:SetText(CLOSE or "Close")
bankWindow.close:SetScript("OnClick", function() bankWindow:Hide() end)

local bankRows = {}

local function BankRow(index)
	local row = bankRows[index]
	if row then return row end
	row = {}
	row.border = bankWindow:CreateTexture(nil, "ARTWORK", nil, 1)
	row.border:SetSize(BANK_ICON_SIZE, BANK_ICON_SIZE)
	row.icon = bankWindow:CreateTexture(nil, "ARTWORK", nil, 2)
	row.icon:SetPoint("TOPLEFT", row.border, "TOPLEFT", BORDER, -BORDER)
	row.icon:SetPoint("BOTTOMRIGHT", row.border, "BOTTOMRIGHT", -BORDER, BORDER)
	row.name = bankWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", row.border, "RIGHT", 6, 0)
	row.name:SetWidth(BANK_COLUMN_WIDTH - BANK_ICON_SIZE - 6 - BANK_COUNT_WIDTH - 8)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.count = bankWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.count:SetPoint("LEFT", row.name, "RIGHT")
	row.count:SetWidth(BANK_COUNT_WIDTH)
	row.count:SetJustifyH("RIGHT")
	bankRows[index] = row
	return row
end

local function ShowBankRow(row, shown)
	row.border:SetShown(shown)
	row.icon:SetShown(shown)
	row.name:SetShown(shown)
	row.count:SetShown(shown)
end

-- Colored items first, in the order the sort uses, then the rest by name. The
-- game may not know an item's name yet: GET_ITEM_INFO_RECEIVED redraws when it does.
local function BankList()
	local items = {}
	for id, count in pairs(bankItems or {}) do
		local name, link = ItemInfo(id)
		items[#items + 1] = { id = id, count = count, hex = itemColors[id], name = name or "", link = link }
	end
	local firstColor = itemColors[HEARTHSTONE_ID]
	table.sort(items, function(a, b)
		if a.hex ~= b.hex then return ColorComesFirst(a.hex, b.hex, firstColor) end
		if a.name ~= b.name then return a.name < b.name end
		return a.id < b.id
	end)
	return items
end

function RedrawBankWindow()
	if not bankWindow:IsShown() then return end
	local items = BankList()

	local fitting = math.floor((UIParent:GetHeight() - BANK_ROWS_TOP - BANK_PADDING - BANK_SCREEN_MARGIN) / BANK_ROW_STEP)
	local columns = math.max(1, math.ceil(#items / math.max(1, fitting)))
	local rows = math.ceil(#items / columns)

	for i, item in ipairs(items) do
		local row = BankRow(i)
		local column, line = math.floor((i - 1) / rows), (i - 1) % rows
		row.border:ClearAllPoints()
		row.border:SetPoint("TOPLEFT", BANK_PADDING + column * BANK_COLUMN_WIDTH, -BANK_ROWS_TOP - line * BANK_ROW_STEP)
		ShowBankRow(row, true)
		if item.hex then
			local r, g, b = FromHex(item.hex)
			row.border:SetColorTexture(r, g, b, 1)
		else
			row.border:Hide()
		end
		row.icon:SetTexture(select(5, ItemInfoInstant(item.id)))
		row.name:SetText(item.link or ("Item " .. item.id))
		row.count:SetText(item.count > 1 and item.count or "")
	end
	for i = #items + 1, #bankRows do ShowBankRow(bankRows[i], false) end

	if #items > 0 then
		bankWindow.empty:Hide()
	else
		bankWindow.empty:SetText(bankItems and "Your bank was empty." or "No bank visit remembered yet. Open your bank once.")
		bankWindow.empty:Show()
	end

	local width = math.max(BANK_MIN_WIDTH, columns * BANK_COLUMN_WIDTH + 2 * BANK_PADDING)
	bankWindow:SetSize(width, BANK_ROWS_TOP + math.max(rows, 1) * BANK_ROW_STEP + BANK_PADDING)
	bankWindow:SetScale(math.min(1, (UIParent:GetWidth() - BANK_SCREEN_MARGIN) / width))
	bankWindow.items, bankWindow.rowsPerColumn = items, rows
end

-- Tooltips, for the mouse. The row under the cursor is worked out from the
-- layout, because a frame per row is what the rows avoid. A position outside the
-- rows, on any side, comes out as no item.
local function BankItemAt(x, y)
	local left, top = bankWindow:GetLeft(), bankWindow:GetTop()
	if not left or not top then return nil end
	local scale = bankWindow:GetEffectiveScale()
	local across, down = x / scale - left - BANK_PADDING, top - y / scale - BANK_ROWS_TOP
	if across < 0 or down < 0 then return nil end
	local column, line = math.floor(across / BANK_COLUMN_WIDTH), math.floor(down / BANK_ROW_STEP)
	if line >= bankWindow.rowsPerColumn then return nil end
	return bankWindow.items[column * bankWindow.rowsPerColumn + line + 1]
end

local tooltipItemID -- the item whose tooltip is showing
local openedAtX, openedAtY, cursorMoved

local function ShowBankTooltip(id)
	if id == tooltipItemID then return end
	tooltipItemID = id
	if id then
		GameTooltip:SetOwner(bankWindow, "ANCHOR_CURSOR")
		GameTooltip:SetHyperlink("item:" .. id)
		GameTooltip:Show()
	else
		GameTooltip:Hide()
	end
end

-- On a gamepad the cursor is hidden but keeps a position, often mid-screen and so
-- over this window. No tooltip until it has moved since the window opened.
bankWindow:SetScript("OnShow", function()
	openedAtX, openedAtY = GetCursorPosition()
	cursorMoved = false
end)

bankWindow:SetScript("OnUpdate", function()
	local x, y = GetCursorPosition()
	cursorMoved = cursorMoved or x ~= openedAtX or y ~= openedAtY
	if not cursorMoved then return end
	local item = BankItemAt(x, y)
	ShowBankTooltip(item and item.id)
end)

bankWindow:SetScript("OnHide", function() ShowBankTooltip(nil) end)

SLASH_XANABANK1 = "/xbank"
SlashCmdList.XANABANK = function()
	bankWindow:SetShown(not bankWindow:IsShown())
	RedrawBankWindow()
end

---------------------------------------------------------------------------
-- Hooks and events
---------------------------------------------------------------------------
local function OnBagHidden()
	C_Timer.After(0, function()
		HideHiddenCells()
		if not AnyBagShown() then
			bagsOpen = nil
			picker:Hide()
		end
		UpdatePadBinding()
	end)
end

local function HookBagFrames()
	for _, frame in ipairs(BagFrames()) do
		if frame then
			frame:HookScript("OnShow", RequestRefresh)
			frame:HookScript("OnHide", OnBagHidden)
		end
	end
	for _, frame in ipairs({ BankFrame or false, BankPanel or false }) do
		if frame then frame:HookScript("OnShow", RequestRefresh) end
	end
	-- Re-lays out an open window, e.g. when a bag is collapsed with the gamepad.
	if ContainerFrame_GenerateFrame then hooksecurefunc("ContainerFrame_GenerateFrame", RequestRefresh) end
end

-- Called on every sign that the macros may have loaded. The first signal may
-- come before this character's own macros are there, so it keeps looking until
-- it has found some data.
local function OnMacrosReady()
	macrosReady = true
	if not dataLoaded then
		dataLoaded = LoadData()
		if dataLoaded then RequestRefresh() end
	end
	-- Unless the bank has already been read, which would be newer.
	if not bankItems then LoadBank() end
	if saveWanted then SaveData() end
	if bankSaveWanted then SaveBank() end
end

-- If anything still gets blocked, say which function it was.
local blockWatch = CreateFrame("Frame")
blockWatch:RegisterEvent("ADDON_ACTION_FORBIDDEN")
blockWatch:RegisterEvent("ADDON_ACTION_BLOCKED")
blockWatch:SetScript("OnEvent", function(_, event, addon, fn)
	if addon == ADDON then Print(("%s: the game blocked %s"):format(event, tostring(fn))) end
end)

SLASH_XANABAGS1 = "/xbags"
-- What the addon can see of the bank, for when it doesn't work there.
local function ReportBank()
	if not bankOpen then
		Print("Open your bank and try again.")
		return
	end
	local count, first = 0, nil
	ForEachBankButton(function(button)
		count = count + 1
		first = first or button
	end)
	Print("Bank buttons found: " .. count)
	if first then
		local bag, slot = ButtonBagSlot(first)
		Print(("First one: %s, bag %s, slot %s"):format(tostring(first:GetName()), tostring(bag), tostring(slot)))
	end
	for _, bag in ipairs(BANK_BAGS) do
		local size = BagSlotCount(bag) or 0
		if size > 0 then Print(("Bag %d has %d slots"):format(bag, size)) end
	end
	local focus = (GetMouseFoci and GetMouseFoci()[1]) or (GetMouseFocus and GetMouseFocus())
	local chain = {}
	while focus and #chain < 8 do
		chain[#chain + 1] = (focus.GetName and focus:GetName()) or "unnamed"
		focus = focus.GetParent and focus:GetParent()
	end
	Print("Under the cursor: " .. (#chain > 0 and table.concat(chain, " < ") or "nothing"))
end

SlashCmdList.XANABAGS = function(msg)
	if strlower(strtrim(msg or "")) == "bank" then
		ReportBank()
	else
		Print("Select an item in your bags or bank and press R3 on the gamepad, or Alt+click it with the mouse, to choose its border color.")
		Print("/xbank opens or closes the list of what was in your bank at your last visit. It works from anywhere, and in a macro.")
		Print("/xbags bank reports what the addon can see of an open bank.")
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		HookBagFrames()
		for _, e in ipairs({
			"BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD", "UPDATE_MACROS", "PLAYER_REGEN_ENABLED",
			"BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "PLAYER_REGEN_DISABLED",
			"GET_ITEM_INFO_RECEIVED",
		}) do
			pcall(self.RegisterEvent, self, e)
		end
		local accountMacros, characterMacros = GetNumMacros()
		if (accountMacros or 0) + (characterMacros or 0) > 0 then OnMacrosReady() end
		RequestRefresh()
	elseif event == "UPDATE_MACROS" then
		OnMacrosReady()
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		if bankWindow:IsShown() then RequestRefresh() end
	elseif event == "BANKFRAME_OPENED" then
		bankOpen = true
		RequestRefresh()
	elseif event == "BANKFRAME_CLOSED" then
		bankOpen, bankSorted = nil, nil
		RequestRefresh()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if saveWanted then SaveData() end
		if bankSaveWanted then SaveBank() end
		ReleaseNavKeys()
		UpdatePadBinding()
	elseif event == "PLAYER_REGEN_DISABLED" then
		if picker.padMode then picker:Hide() end
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- Fallback for a player with no macros at all, where no macro event may come.
		C_Timer.After(2, OnMacrosReady)
	else
		RequestRefresh()
	end
end)
