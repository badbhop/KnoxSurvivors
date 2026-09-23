local rootPath = arg[1] or "."
local path = rootPath .. "/mod/42/media/lua/client/KS_SurvivorCard.lua"
local file = assert(io.open(path, "r"))
local source = file:read("*a")
file:close()

assert(string.find(source, 'require "XpSystem/ISUI/ISCharacterScreen"', 1, true),
    "survivor card must use the vanilla Character Screen for the portrait")
assert(string.find(source, 'ISCharacterScreen:new', 1, true),
    "survivor card must create the vanilla Character Screen view")
assert(not string.find(source, 'ISUI3DModel:new', 1, true),
    "survivor card must not maintain a second custom portrait model")
assert(string.find(source, 'require "KS_CompanionInventory"', 1, true),
    "survivor card must reuse the companion inventory bridge")
assert(string.find(source, 'CompanionInventory.show', 1, true),
    "survivor card must expose the vanilla inventory shortcut")
assert(string.find(source, 'local CompanionInventory = require "KS_CompanionInventory"', 1, true),
    "survivor card must bind the inventory module returned by require")
assert(string.find(source, 'CompanionInventory == nil or CompanionInventory.show == nil', 1, true),
    "survivor card must fail safely when the inventory module is unavailable")
assert(string.find(source, 'view.doBodyPartContextMenu = function() end', 1, true),
    "survivor card health view must remain read-only for off-slot characters")
assert(string.find(source, 'view.listbox.onRightMouseUp = function() end', 1, true)
    and string.find(source, 'view.bodyPartPanel.onRightMouseUp = function() end', 1, true),
    "survivor card health child panels must not open local-player menus")
assert(string.find(source, 'context.medicalCheck', 1, true),
    "survivor card must expose the shared medical-check shortcut")
assert(string.find(source, 'progressBar.char = self.char', 1, true)
    and string.find(source, 'view.playerNum = window.playerNum', 1, true),
    "vanilla skill bars must use a valid local UI slot and read the selected survivor")
assert(not string.find(source, 'pcall(function() view:createChildren() end)', 1, true),
    "health children must be instantiated exactly once by the vanilla addView lifecycle")
assert(string.find(source, 'sectionHeader("Condition")', 1, true),
    "knox tab must show a condition section with needs detail")
for _, row in ipairs({ '"Health"', '"Food"', '"Water"', '"Sleep"', '"Endurance"' }) do
    assert(string.find(source, 'needBar(' .. row, 1, true),
        "knox tab must display " .. row .. " with a bar")
end
assert(string.find(source, 'snapshot.vitals', 1, true),
    "condition bars must read the live vitals snapshot, not static text")
assert(string.find(source, 'snapshot.latestMemory', 1, true)
    and string.find(source, 'snapshot.recentHistory', 1, true),
    "Knox history panel must expose the bounded persistent-memory summary")
assert(string.find(source, 'KnoxSurvivorViewModel.getSurvivor(survivorId, playerNum)', 1, true),
    "view card must fall back to the full survivor record for base residents outside the companion roster")
assert(string.find(source, 'hideAppearanceButtons(self)', 1, true),
    "appearance buttons must be forced off every render because vanilla recreates them after the first hide")
assert(string.find(source, 'view.beardButton:setVisible(false)', 1, true)
    and string.find(source, 'view.literatureButton:setVisible(false)', 1, true),
    "hair, beard and literature buttons must stay hidden on the read-only card")
assert(string.find(source, 'if survivor ~= nil and window.infoView == nil then', 1, true),
    "unloaded survivors must not create a vanilla character screen without a live shell")
assert(string.find(source, 'if survivor ~= nil and window.skillsView == nil then', 1, true),
    "unloaded survivors must not create vanilla skill views without a live shell")
assert(string.find(source, 'window.infoView ~= nil and window.infoView.char ~= survivor', 1, true),
    "live view rebinding must tolerate a card that was opened while unloaded")

print("Survivor card UI PASS vanilla_portrait=true inventory=true medical=true skills=true health_single=true resident_fallback=true appearance_hidden=true condition=true")
