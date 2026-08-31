require "NPCs/BodyLocations"

-- Keep the original containers, contents, sounds, size limits and acceptance
-- rules. Only add a wearing location; wallets are not key rings or backpacks.
local Wallets = {}
_G.KnoxWallets = Wallets
local TYPES = { "Base.Wallet", "Base.Wallet_Female", "Base.Wallet_Male", "Base.Wallet_Hide" }

function Wallets.install()
    if KnoxWalletLocation == nil then
        print("[KnoxSurvivors][Wallet] registry unavailable; native wallets unchanged")
        return false
    end
    BodyLocations.getGroup("Human"):getOrCreateLocation(KnoxWalletLocation)
    for _, fullType in ipairs(TYPES) do
        local script = ScriptManager.instance:getItem(fullType)
        if script ~= nil and script:getItemType() == ItemType.CONTAINER then
            script:DoParam("CanBeEquipped = knoxsurvivors:wallet")
        end
    end
    return true
end

-- Shared Lua loads after script definitions, before world inventory creation or
-- restoration. Native load reconstructs CanBeEquipped from the item script.
Wallets.install()
return Wallets
