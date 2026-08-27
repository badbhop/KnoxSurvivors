-- Companion inventory deliberately uses the same player/loot pages that Project
-- Zomboid uses for nearby containers. That keeps drag/drop, transfer actions,
-- item context menus, and bag handling owned by the base game.
require "ISUI/ISInventoryPage"
require "ISUI/ISInventoryPane"
require "ISUI/ISInventoryPaneContextMenu"
require "KS_SurvivorRuntime"
require "KS_Persistence"

local CompanionInventory = rawget(_G, "KnoxCompanionInventory") or {}
_G.KnoxCompanionInventory = CompanionInventory

local MAX_DISTANCE_SQUARED = 16

-- Active survivor per playerNum whose inventory is currently exposed in the
-- vanilla loot window. Kept so OnRefreshInventoryWindowContainers can re-inject
-- the survivor's ItemContainer (and its equipped bags) after vanilla rebuilds the
-- button list. Without this the survivor container disappears on the next
-- dirtyUI / direction change because it is not a world container.
local active = CompanionInventory._active or {}
CompanionInventory._active = active

local function nearby(player, character)
    if player == nil or character == nil or player:getCurrentSquare() == nil
        or character:getCurrentSquare() == nil or player:getZ() ~= character:getZ() then
        return false
    end
    local dx, dy = player:getX() - character:getX(), player:getY() - character:getY()
    return dx * dx + dy * dy <= MAX_DISTANCE_SQUARED
end

local function displayName(survivorId)
    local identity = KnoxPersistence.getSurvivorIdentity(survivorId) or {}
    local name = tostring(identity.forename or "") .. " " .. tostring(identity.surname or "")
    name = string.gsub(name, "^%s*(.-)%s*$", "%1")
    return name ~= "" and name or "Survivor"
end

local function setVisiblePage(page, visible)
    if page == nil then return end
    page:setVisible(visible)
    page.collapseCounter = 0
    if visible and page.isCollapsed then
        page.isCollapsed = false
        if page.clearMaxDrawHeight then page:clearMaxDrawHeight() end
        page.collapseCounter = -40
    end
end

local function onRefreshContainers(page, state)
    if state ~= "buttonsAdded" then return end
    if page == nil or page.onCharacter then return end
    local playerNum = page.player
    local survivorId = active[playerNum]
    if type(survivorId) ~= "string" or survivorId == "" then return end
    local player = getSpecificPlayer(playerNum)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if not nearby(player, character) then
        active[playerNum] = nil
        return
    end
    local inventory = character ~= nil and character:getInventory() or nil
    if inventory == nil then return end
    -- Ensure the survivor's main inventory is offered as a loot container.
    local hasMain = false
    for _, btn in ipairs(page.backpacks or {}) do
        if btn.inventory == inventory then hasMain = true; break end
    end
    if not hasMain then
        local title = displayName(survivorId) .. " - Inventory"
        local ok = pcall(function()
            page:addContainerButton(inventory, page.invbasic, title, title)
        end)
        if not ok then
            -- Fallback without texture if invbasic unavailable in this layout.
            pcall(function() page:addContainerButton(inventory, nil, title, title) end)
        end
    end
    -- Expose equipped bags so the loot window can switch bags exactly as the
    -- player inventory does. Vanilla player inventory only shows equipped
    -- containers; follow the same rule for the survivor.
    local items = inventory:getItems()
    if items ~= nil then
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            local itemInv = item ~= nil and item.getInventory ~= nil and item:getInventory() or nil
            if itemInv ~= nil then
                local shouldShow = false
                local ok, equipped = pcall(function() return character:isEquipped(item) end)
                if ok and equipped then shouldShow = true end
                if not shouldShow then
                    -- Also show containers that are not necessarily equipped but
                    -- still have an inventory (e.g. bag in main inventory). This
                    -- keeps drag/drop discoverable while staying close to vanilla
                    -- player behaviour. Clamp to Category == "Container" to avoid
                    -- polluting the button strip with non-bag items.
                    local catOk, cat = pcall(function() return item:getCategory() end)
                    if catOk and cat == "Container" then shouldShow = true end
                end
                if shouldShow then
                    local exists = false
                    for _, btn in ipairs(page.backpacks) do
                        if btn.inventory == itemInv then exists = true; break end
                    end
                    if not exists then
                        local texOk, tex = pcall(function() return item:getTex() end)
                        local nameOk, name = pcall(function() return item:getName() end)
                        pcall(function()
                            page:addContainerButton(itemInv, texOk and tex or nil, nameOk and name or "Bag", nameOk and name or "Bag")
                        end)
                    end
                end
            end
        end
    end
end

if Events ~= nil and Events.OnRefreshInventoryWindowContainers ~= nil then
    pcall(function() Events.OnRefreshInventoryWindowContainers.Remove(onRefreshContainers) end)
    Events.OnRefreshInventoryWindowContainers.Add(onRefreshContainers)
end

-- Vaulted patches so reload does not stack wrappers.
local function isSurvivorContainer(playerNum, container)
    local survivorId = active[playerNum]
    if type(survivorId) ~= "string" or survivorId == "" or container == nil then return false, nil, nil end
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    local inv = character ~= nil and character:getInventory() or nil
    if inv == nil then return false, nil, nil end
    if container == inv then return true, character, inv end
    local items = inv:getItems()
    if items ~= nil then
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            local itemInv = item ~= nil and item.getInventory ~= nil and item:getInventory() or nil
            if itemInv ~= nil and itemInv == container then
                return true, character, inv
            end
        end
    end
    return false, nil, nil
end

-- Render the survivor's inventory with the same equipped/worn line + red dot
-- that vanilla player inventory uses. Loot panes are normally onCharacter=false
-- and never set isEquipped, so the divider and icons are skipped. Temporarily
-- masquerade the loot pane as a character pane and provide the survivor as the
-- player object for just that refresh.
if ISInventoryPane ~= nil and ISInventoryPane.refreshContainer ~= nil then
    if CompanionInventory._origRefreshContainer == nil then
        CompanionInventory._origRefreshContainer = ISInventoryPane.refreshContainer
    end
    local origRefresh = CompanionInventory._origRefreshContainer
    ISInventoryPane.refreshContainer = function(self)
        local playerNum = self.player
        local survivorId = active[playerNum]
        local character = type(survivorId) == "string" and KnoxSurvivorRuntime.getCharacter(survivorId) or nil
        local survInv = character ~= nil and character:getInventory() or nil
        local isSurvivorPane = survInv ~= nil and self.inventory == survInv
        -- Also handle bag sub-containers of the survivor.
        if not isSurvivorPane and survInv ~= nil and self.inventory ~= nil then
            local ok, flag = pcall(function() return isSurvivorContainer(playerNum, self.inventory) end)
            if ok and flag then isSurvivorPane = true end
        end
        if isSurvivorPane and self.parent ~= nil then
            local savedOnCharacter = self.parent.onCharacter
            local savedGetSpecificPlayer = rawget(_G, "getSpecificPlayer")
            local savedGetPlayerHotbar = rawget(_G, "getPlayerHotbar")
            self.parent.onCharacter = true
            _G.getSpecificPlayer = function(p)
                if p == playerNum then return character end
                if savedGetSpecificPlayer ~= nil then return savedGetSpecificPlayer(p) end
                return nil
            end
            -- Survivor hotbar is not player hotbar; suppress it so only
            -- equipped/worn icons are used (matches live player visual).
            _G.getPlayerHotbar = function(p)
                if p == playerNum then return nil end
                if savedGetPlayerHotbar ~= nil then return savedGetPlayerHotbar(p) end
                return nil
            end
            local ok, result = pcall(function() return origRefresh(self) end)
            self.parent.onCharacter = savedOnCharacter
            _G.getSpecificPlayer = savedGetSpecificPlayer
            _G.getPlayerHotbar = savedGetPlayerHotbar
            if ok then return result else error(result, 0) end
        end
        return origRefresh(self)
    end
end

-- getContainers crashes for survivor shells because it does
-- getPlayerInventory(survivor:getPlayerNum()).inventoryPane on a non-local
-- player (-1). Wrap it once so any createMenu (including our survivor-
-- redirected one) falls back to the survivor's own ItemContainer.
if ISInventoryPaneContextMenu ~= nil and ISInventoryPaneContextMenu.getContainers ~= nil then
    if CompanionInventory._origGetContainers == nil then
        CompanionInventory._origGetContainers = ISInventoryPaneContextMenu.getContainers
    end
    local origGetContainers = CompanionInventory._origGetContainers
    ISInventoryPaneContextMenu.getContainers = function(character)
        local ok, result = pcall(function() return origGetContainers(character) end)
        if ok and result ~= nil then return result end
        local fallback = ArrayList.new()
        local ok2, inv = pcall(function() return character:getInventory() end)
        if ok2 and inv ~= nil then fallback:add(inv) end
        -- Include equipped bag inventories so recipes/equip checks see them.
        if ok2 and inv ~= nil then
            local ok3, items = pcall(function() return inv:getItems() end)
            if ok3 and items ~= nil then
                for i = 0, items:size() - 1 do
                    local item = items:get(i)
                    local bInv = item ~= nil and item.getInventory ~= nil and item:getInventory() or nil
                    if bInv ~= nil then
                        local ok4, cat = pcall(function() return item:getCategory() end)
                        local show = false
                        local ok5, eq = pcall(function() return character:isEquipped(item) end)
                        if ok5 and eq then show = true end
                        if not show and ok4 and cat == "Container" then show = true end
                        if show then fallback:add(bInv) end
                    end
                end
            end
        end
        return fallback
    end
end

-- Context menu: actions on the survivor side must target the survivor IsoPlayer,
-- not the local player. Vanilla builds the menu with getSpecificPlayer(player)
-- and tests playerObj:isEquipped / container:isInCharacterInventory. Redirect
-- that lookup when the clicked item lives in the active survivor inventory so
-- Wear/Equip/Unequip operate on the survivor and require the item to be in the
-- survivor's inventory (player must transfer first, as requested).
if ISInventoryPaneContextMenu ~= nil and ISInventoryPaneContextMenu.createMenu ~= nil then
    if CompanionInventory._origCreateMenu == nil then
        CompanionInventory._origCreateMenu = ISInventoryPaneContextMenu.createMenu
    end
    local origCreate = CompanionInventory._origCreateMenu
    ISInventoryPaneContextMenu.createMenu = function(player, isInPlayerInventory, items, x, y, origin)
        local testItem = nil
        if type(items) == "table" and items[1] ~= nil then
            testItem = items[1]
            if testItem ~= nil and not instanceof(testItem, "InventoryItem") and testItem.items ~= nil then
                testItem = testItem.items[1]
            end
        end
        local container = testItem ~= nil and testItem.getContainer ~= nil and testItem:getContainer() or nil
        local isSurvivor = false
        local character = nil
        if container ~= nil then
            local ok, flag, ch = pcall(function() return isSurvivorContainer(player, container) end)
            if ok and flag then isSurvivor = true; character = ch end
        end
        if isSurvivor and character ~= nil then
            local savedGetSpecificPlayer = rawget(_G, "getSpecificPlayer")
            _G.getSpecificPlayer = function(p)
                if p == player then return character end
                if savedGetSpecificPlayer ~= nil then return savedGetSpecificPlayer(p) end
                return nil
            end
            -- Force isInPlayerInventory=true so clothing/wear branch is evaluated
            -- (loot panes are false and skip that branch).
            local ok, result = pcall(function() return origCreate(player, true, items, x, y, origin) end)
            _G.getSpecificPlayer = savedGetSpecificPlayer
            if ok then return result else error(result, 0) end
        end
        return origCreate(player, isInPlayerInventory, items, x, y, origin)
    end
end

function CompanionInventory.show(playerNum, survivorId)
    local player = getSpecificPlayer(playerNum)
    local character = KnoxSurvivorRuntime.getCharacter(survivorId)
    if not nearby(player, character) then
        return false, "too_far_away"
    end

    local loot = getPlayerLoot(playerNum)
    local playerInv = getPlayerInventory(playerNum)
    local inventory = character:getInventory()
    if loot == nil or playerInv == nil or inventory == nil then
        return false, "inventory_ui_unavailable"
    end

    active[playerNum] = survivorId

    -- Vanilla loot flow: the survivor ItemContainer is presented as the loot
    -- container so all vanilla transfer actions, drag/drop, context menus and
    -- the bag button strip operate exactly as they do on a corpse or world
    -- container. The hook above keeps the button available after refresh.
    loot:setNewContainer(inventory)
    loot.title = displayName(survivorId) .. " - Inventory"

    -- Side-by-side: player inventory (left) + survivor loot (right), same as
    -- looting a nearby container. This keeps normal bag switching on the player
    -- side and bag switching for the survivor's equipped bags on the loot side.
    setVisiblePage(playerInv, true)
    setVisiblePage(loot, true)

    -- Ensure loot is the selected container before the next refresh. The
    -- re-injection hook will preserve this selection because the button will
    -- exist when refreshBackpacks decides the selected inventory.
    ISInventoryPage.dirtyUI()
    return true, "vanilla_loot_window"
end

function CompanionInventory.clear(playerNum)
    if active ~= nil then active[playerNum] = nil end
end

return CompanionInventory
