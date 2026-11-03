local savedStats = PersistentDB:GetStructuredData("stats") or {}
local statsWindow, btn

local stats = {
	abilities = {"Abilities used", 0},
	bank_opened = {"Bank opened", 0},
	bank_presets = {"Bank presets loaded", 0},
	benchsitting = {"Benches sat on", 0},
	broadcasts = {"Broadcasts triggered", 0},
	cabbages_picked = {"Cabbages picked", 0},
	cant_reach = {"Can't reach something", 0},
	clue_value = {"Total clue value", 0},
	cooking = {"Food cooked", 0},
	crystal_chests = {"Crystal chests opened", 0},
	deaths = {"Deaths", 0},
	death_costs = {"Total death costs", 0},
	disassemble = {"Items disassembled", 0},
	dg_dungeons = {"Dungeons finished", 0},
	examine = {"Things examined", 0},
	excalibur = {"Excalibur used", 0},
	elven_shard = {"Elven ritual shard used", 0},
	fishing = {"Fish fished", 0},
	food_eaten = {"Food eaten", 0},
	implings = {"Implings caught", 0},
	items_dropped = {"Items dropped", 0},
	logs_burned = {"Logs burned", 0},
	logs_cut = {"Logs cut", 0},
	nothing_interesting = {"Nothing interesting happens", 0},
	pickpockets = {"Pickpockets", 0},
	potions_drunk = {"Potions drunk", 0},
	potions_made = {"Potions made", 0},
	prayers = {"Prayers activated", 0},
	pvm_hub = {"War's Retreat teleports", 0},
	rested = {"Times rested", 0},
	seren_spirits = {"Seren spirits summoned", 0},
	sheep_sheared = {"Sheep sheared", 0},
	summons = {"Familiars/pets summoned", 0},
	surged = {"Times Surged", 0},
	surge_one_tile = {"Surged one tile", 0},
	missed_brooch = {"Missed Brooch blessings", 0},
	missed_seren = {"Missed Seren spirits", 0},
	missed_catalyst = {"Missed Bik catalysts", 0},
	bones_buried = {"Bones buried", 0},
	ashes_scattered = {"Ashes scattered", 0},
}

-- Futureproofing, in case I add new things to track
for key, saved in pairs(savedStats) do
	if stats[key] then
		stats[key][2] = saved[2]
	end
end

local whitelistedChatTypes = {
	[0] = true, -- GENERAL
	[4] = true, -- ENGINE
	[27] = true, -- OBJ_EXAMINE
	[28] = true, -- NPC_EXAMINE
	[29] = true, -- LOC_EXAMINE
	[100] = true, -- TRADE_REQUEST
	[101] = true, -- CHALLENGE
	[102] = true, -- ASSIST_REQUEST
	[103] = true, -- TRADE_NOTIFICATION
	[104] = true, -- ASSIST_NOTIFICATION
	[107] = true, -- CLAN_CHALLENGE
	[108] = true, -- ALLY_REQUEST
	[109] = true, -- SPAM
	[111] = true, -- DUNGEON_INVITE
	[125] = true, -- BROADCAST
	[126] = true, -- WORLD_EVENT
	[127] = true, -- MISC_BROADCAST
	[132] = true, -- DUEL_ANY_REQUEST
	[137] = true, -- BROADCAST_GLOBAL
	[138] = true, -- BROADCAST_WORLD
	[139] = true, -- BROADCAST_FRIENDS
	[142] = true, -- TIMED_EVENT
}

function increaseStat(stat, amount)
	local amt = amount or 1
	stats[stat][2] = stats[stat][2] + amt
	if statsWindow then	showStatsWindow() end
end

function resetStats()
	for key, value in pairs(stats) do
		stats[key][2] = 0
	end
	showStatsWindow()
end

-- Convert a formatted number ("1,234,567") to an actual number
function textValToNumber(text)
	return tonumber((text:gsub(",", "")))
end

-- Add the delimiters in larger numbers
local function formatNumber(n)
	local formatted = tostring(n)
	local count

	repeat
		formatted, count = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	until count == 0

	return formatted
end

-- Keep track of a player's position when surging
local pendingSurge = nil
function onSurge()
	local player = Player.GetEntity()
	if not player then return end

	pendingSurge = {
		x = player.coordGrid.x,
		z = player.coordGrid.z,
		ticks = 0
	}
end

-- Get the GE value (avg of high & low price) for each item a player earns in a clue casket
local lastVal = 0
function getClueValue()
	local clueInv = Inventory.Find(config.Inv.TRAIL_REWARDINV):GetSlots()
	local totalVal = 0
	for i, slot in ipairs(clueInv) do
		local itemID = slot.obj.id
		if slot.obj.isStockmarket then
			local itemName = slot.obj.configName
			if string.find(itemName, "CERT_") then itemID = itemID - 1 end
			local itemVal = gepl.getLatest(itemID)
			local averageVal = (itemVal.high + itemVal.low) / 2 * slot.count
			totalVal = totalVal + averageVal
		end
	end
	totalVal = math.floor(totalVal + 0.5)
	if totalVal == lastVal then return 0 end -- Rerolls can trigger an update, this prevents that
	lastVal = totalVal
	return lastVal
end

local hasDied -- Don't re-add the cost if the player opens the UI multiple times for the same reclaim
function getDeathCost()
	deathScreen = ui.Interfaces:GetComponent(id.Component.DEATH__RECLAIM_COST)
	if not deathScreen or not hasDied then return end
	if deathScreen and deathScreen.content ~= "1234567" then -- The UI briefly loads "1234567" as PH value
		local reclaimCost = textValToNumber(deathScreen.content)
		if hasDied then
			increaseStat("death_costs", reclaimCost)
			hasDied = false
		end
	end
end

function varTrigger(varEvent)
	local eventName = varEvent.var.configName
	local oldValue, newValue = varEvent.oldValue, varEvent.newValue

	if eventName == "BANK_TEMP" and newValue == 64 then
		increaseStat("bank_opened")
	elseif eventName == "REST_VARP" then
		increaseStat("rested")
	elseif eventName == "LIFEPOINTS" and newValue == 0 then
		increaseStat("deaths")
		hasDied = true
	elseif eventName == "PLAYER_COORD" and newValue == 53979023 then
		increaseStat("pvm_hub")
	elseif eventName:find("COOLDOWN_MAGIC_SURGE") and eventName:find("START") and newValue > oldValue then
		onSurge()
		increaseStat("surged")
	elseif eventName == "LORE_NPC_HEAD" and varEvent.newValue > -1 then
		increaseStat("summons")
	elseif eventName == "TT17_VARIABLE" or eventName == "TT14_VARIABLE" then
		local clueValue = getClueValue()
		increaseStat("clue_value", clueValue)
	elseif eventName == "PLAYER_KIT_TORSO_CLIENT" and newValue == 4551 then
		increaseStat("benchsitting")
	elseif eventName == "NATURE_BOSS_VARP" and oldValue == 0 and newValue > 0 then
		increaseStat("elven_shard")
	elseif eventName == "DRAGONRESIST" and oldValue == 0 then
		increaseStat("excalibur")
	elseif eventName == "RAND_PARTY_FLOOR_TIME" and newValue == -1 then
		increaseStat("dg_dungeons")
	elseif eventName:find("PRAYER_BASE") or eventName:find("CURSE_BASE") then
		if (newValue & ~oldValue) ~= 0 then increaseStat("prayers") end
	elseif eventName == "TOPLEVEL_V2_SKINS_VARP" then -- Player swaps between UI modes
		if statsWindow then
			statsWindow:Destroy()
			statsWindow = nil
		end
		btn = nil
	elseif eventName:find("COMBATV2_COOLDOWN_") and eventName:find("START") and newValue > oldValue then
		increaseStat("abilities")
	end
end

local lastClickAction = ""
function miniMenuSelection(event)
	lastClickAction = event.entry.verbText
	if event.entry.actionVerbType == MiniMenuActionVerbType.EXAMINE then increaseStat("examine") end
end

function chatTrigger(event)
	if not whitelistedChatTypes[event.chatType] then return end

	local msg = event.chatMessage
	if msg == "You get some wool." then
		increaseStat("sheep_sheared")
	elseif msg == "You pick a cabbage." then
		increaseStat("cabbages_picked")
	elseif msg:match("^You get some (%a*)%s?[Ll]ogs%.$") or msg:match("^You transport to your bank: (%d+) x (%a*)%s?[Ll]ogs%.$") then
		increaseStat("logs_cut")
	elseif msg:find("You manage to catch the impling") then
		increaseStat("implings")
	elseif msg:find("You eat the ") then
		increaseStat("food_eaten")
	elseif msg:find("You drink some of your ") then
		increaseStat("potions_drunk")
	elseif msg:find("You successfully cook a ") then
		increaseStat("cooking")
	elseif msg == "The fire catches and the logs begin to burn." or msg == "You add a log to the fire." or msg:find("the log is incinerated") then
		increaseStat("logs_burned")
	elseif msg == "You pick the target's pocket." then
		increaseStat("pickpockets")
	elseif msg:find("You mix the ") then
		increaseStat("potions_made")
	elseif msg:find("Materials gained: ") then
		increaseStat("disassemble")
	elseif msg == "Nothing interesting happens." then
		increaseStat("nothing_interesting")
	elseif msg:find("News") and string.find(msg, Player.GetEntity().displayName) then
		increaseStat("broadcasts")
	elseif msg:find("Your preset is being withdrawn.") then
		increaseStat("bank_presets")
	elseif msg == "You unlock the chest with your key. You find some treasure in the chest!" then
		increaseStat("crystal_chests")
	elseif msg:find("A Seren spirit appears") then
		increaseStat("seren_spirits")
	elseif msg == "You can't reach that." then
		increaseStat("cant_reach")
	elseif msg:find("A blessing from the gods disappears") then
		increaseStat("missed_brooch")
	elseif msg:find("The Seren spirit disappears") then
		increaseStat("missed_seren")
	elseif msg:find("A catalyst of alteration disappears") then
		increaseStat("missed_catalyst")
	elseif msg:find("you bury the bones") then
		increaseStat("bones_buried")
	elseif msg:find("You scatter the ashes") or msg:find("from the ashes into you") then
		increaseStat("ashes_scattered")
	end
end


function oneTileSurge(event)
	if not pendingSurge then return end

	local player = Player.GetEntity()
	if not player then return end
	
	-- Give the Surge a couple of ticks to finish
	pendingSurge.ticks = pendingSurge.ticks + 1
	if pendingSurge.ticks < 2 then return end

	local dx = math.abs(player.coordGrid.x - pendingSurge.x)
	local dz = math.abs(player.coordGrid.z - pendingSurge.z)

	if math.max(dx, dz) == 1 then
		increaseStat("surge_one_tile")
	end

	pendingSurge = nil
end

function onInventoryUpdated(event)
	if lastClickAction == "Drop" then
		increaseStat("items_dropped")
		lastClickAction = ""
	end
end

Event.ServerLogic.Subscribe("oneTileSurgeDetector", oneTileSurge)
Event.ServerLogic.Subscribe("deathCostDetector", getDeathCost)
Event.VarTransmit.Subscribe("varTransmit", varTrigger)
Event.MiniMenuEntrySelected.Subscribe("miniMenuSelectionEvent", miniMenuSelection)
Event.ChatMessage.Subscribe("examineTrigger", chatTrigger)
Event.InventoryUpdated.Subscribe("inventoryRemovedDetector", onInventoryUpdated)

--[[
============
STATS SCREEN
============
]]--
local originalWidth, ribbonParent
local windowXLoc, windowYLoc
function setupButton()
	local ribbon = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2_RIBBON__WINDOW_BUILD)
	ribbonParent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__BUTTONS_WINDOW)
	if not ribbon or not ribbonParent then return end
	if var.VarPlayer.TOPLEVEL_V2_LEGACY_INTERFACE.value == 0 then return end -- Make sure we're using Legacy UI

	btn = ui.Button.new(ribbon)
	btn.stylesheetID = id.StyleSheet.BUTTON_DEFAULT_LEGACY
	btn.associatedObjectID = config.Obj.CCF_MAGNIFY_GLASS.id
	btn.showAssociatedObjectSprite = true
	btn:SetSize(32, 32)

	originalWidth = ribbonParent.width
	ribbonParent:SetWidth(originalWidth + 32)
	local offset = (ribbon.width / 32 - 1) * -1
	btn:SetX(0, 0, offset)
	btn:Subscribe(ui.Hook.ONBUTTONPRESSED, statsWindowOpen)
end

function statsWindowOpen()
	if statsWindow then
		if var.VarPlayer.TOPLEVEL_V2_LEGACY_INTERFACE.value == 0 then
			windowXLoc, windowYLoc = statsWindow.root.x, statsWindow.root.y
		end
		statsWindow:Destroy()
		statsWindow = nil
	else
		showStatsWindow()
	end
end

function heroInterfaceDetector()
	local parentUI = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2_PARENT__SUBOVERLAY_LAYER_2)
	local examineBtn = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2_PARENT_SUBOVERLAY_ADVENTURERS_LOG__PLAYER_INSPECT_BUTTON_LAYER)
	if not parentUI or not examineBtn then return end
	if var.VarPlayer.TOPLEVEL_V2_LEGACY_INTERFACE.value ~= 0 then return end

	local btn = ui.Button.new(parentUI)
	btn.stylesheetID = id.StyleSheet.BUTTON_ACTION_NEUTRAL
	btn.label = "Useless Stats"
	btn:SetSize(examineBtn.width, examineBtn.height)
	btn:SetPos(examineBtn.x, examineBtn.y + examineBtn.height)
	btn:Subscribe(ui.Hook.ONBUTTONPRESSED, statsWindowOpen)
end

function ribbonDector()
	if btn then return end
	if var.VarPlayer.TOPLEVEL_V2_LEGACY_INTERFACE.value ~= 0 then setupButton() end
end

Event.ServerLogic.Subscribe("heroInterfaceWatcher", heroInterfaceDetector)
Event.ServerLogic.Subscribe("ribbonWatcher", ribbonDector)

local sortDescending = false
local sortMode = "alphabetical"
function showStatsWindow()
	local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
	local xSize, ySize = 370, 315
	local legacy = var.VarPlayer.TOPLEVEL_V2_LEGACY_INTERFACE.value ~= 0
	local rowColours = {0x2e2825ff, 0x24211eff}

	-- Modern UI: save position the user dragged the window to
	if statsWindow then
		if not legacy then
			windowXLoc, windowYLoc = statsWindow.root.x, statsWindow.root.y
		end
		statsWindow:Destroy()
		statsWindow = nil
	end

	if not legacy then
		statsWindow = prettyui.Window.new(parent, {
			x = windowXLoc,
			y = windowYLoc,
			width = xSize,
			height = ySize,
			rowBackgroundColours = rowColours,
			rowBackgroundEdgeToEdge = true,
			resizable = true,
			title = "USELESS STATS",
			onClose = function(window)
				windowXLoc = window.root.x
				windowYLoc = window.root.y
				statsWindow = nil
			end
		})
	else
		-- Count how many ribbon tabs are open to know where to position the stats window
		local inventory = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__INVENTORY_WINDOW)
		local openWindows = 0
		local ribbonBar = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2_RIBBON__WINDOW_BUILD)
		ribbonBar:IterateDynamicComponents(function(child)
			if child.spriteID == 24913 or child.spriteID == 25735 then openWindows = openWindows + 1 end
		end)

		local xPos, yPos -- Determine where to put the window
		if openWindows == 2 then
			xPos = inventory.x
			yPos = inventory.y - ySize
		elseif openWindows == 1 then
			xPos = inventory.x - xSize
			yPos = inventory.y
		else
			xPos = inventory.x
			yPos = inventory.y
		end

		statsWindow = prettyui.Panel.new(parent, {
			x = xPos,
			y = yPos,
			width = xSize,
			height = ySize,
			rowBackgroundColours = rowColours,
			rowBackgroundEdgeToEdge = true
		})
		statsWindow:AddTitle({
			text = "Useless Stats",
			rowBackground = false,
			inline = true,
			width = xSize - 155
		})
	end

	-- Reset Stats button
	statsWindow:AddSpriteButton("ERASER", function()
		local confirm = prettyui.Confirm.new(parent, {
			title = "RESET USELESS STATS",
			body = "This will reset all your Useless Stats to 0. Are you sure?",
			confirmLabel = "Reset stats",
			confirmVariant = "negative",
			onConfirm = resetStats,
		})
	end, {
		inline = true,
		rowBackground = false,
		tooltip = "RESET ALL STATS"
	})

	-- Alphabetical Sort button
	statsWindow:AddSpriteButton("GRAPH", function()
		if sortMode == "alphabetical" then
			sortDescending = not sortDescending
		else
			sortMode = "alphabetical"
			sortDescending = false
		end
		showStatsWindow()
	end, {
		inline = true,
		rowBackground = false,
		tooltip = "Sort by name"
	})

	-- Numerical Sort button
	local sprite = "LADDER_UP"
	if sortMode == "numerical" and sortDescending then sprite = "LADDER_DOWN" end
	statsWindow:AddSpriteButton(sprite, function()
		if sortMode == "numerical" then
			sortDescending = not sortDescending
		else
			sortMode = "numerical"
			sortDescending = true
		end
		showStatsWindow()
	end, {
		inline = true,
		rowBackground = false,
		tooltip = "Sort by amount"
	})

	-- Sort the data according to the user's preference
	local sortedStats = {}
	for _, stat in pairs(stats) do
		table.insert(sortedStats, stat)
	end
	table.sort(sortedStats, function(a, b)
		if sortMode == "alphabetical" then
			if sortDescending then
				return a[1]:lower() > b[1]:lower()
			else
				return a[1]:lower() < b[1]:lower()
			end
		end
		if a[2] ~= b[2] then
			if sortDescending then
				return a[2] > b[2]
			else
				return a[2] < b[2]
			end
		end
		return a[1]:lower() < b[1]:lower()
	end)

	-- Display sorted stats
	for _, stat in ipairs(sortedStats) do
		local name = stat[1]
		local value = formatNumber(stat[2])
		statsWindow:AddText({
			text = name,
			width = 230
		})

		local valueLabel = statsWindow:AddText({
			text = value,
			inline = true,
			xAnchor = 1,
			x = -125,
			width = 100
		})
		valueLabel.alignHorizontal = ui.AlignMode.BOTTOMRIGHT
	end

	statsWindow:RefreshRowBackgrounds()
end

function PluginShutdown()
	PersistentDB:SetStructuredData("stats", stats)
	if ribbonParent and originalWidth then
		ribbonParent:SetWidth(originalWidth)
	end

	if statsWindow then
		statsWindow:Destroy()
		statsWindow = nil
	end
end
