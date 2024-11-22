----------------------------------------------------------
-- Title: ragmod module
-- Author: n-gon
-- Description:
----- Ragmod module containing useful methods for interacting with ragmod ragdolls
----------------------------------------------------------
require("ragmod_utils")
require("ragmod_options")
ragmod = {}
-- Contains all ragdolls created from this module
ragmod.Ragdolls = {}

----------------
-- Public API --
----------------
--[[
    Getters
]]
function ragmod:IsRagmodRagdoll(ragdoll)
    return ragdoll:GetNWBool("RM_Ragmod", false)
end

-- Returns the current ragdoll a player is possessing
function ragmod:GetRagmodRagdoll(ply)
    return ply:GetNWEntity("ragmod_Possessed", NULL)
end

-- Returns true if the player is currently a ragdoll
function ragmod:IsRagdoll(ply)
    return IsValid(self:GetRagmodRagdoll(ply))
end

-- Returns the time in seconds the player became a ragdoll (since the game started)
function ragmod:GetPossessTime(ply)
    return ply:GetNWFloat("ragmod_PossessTime")
end

-- Returns the time in seconds the player has been possessing a ragdoll
function ragmod:GetTimeSincePossess(ply)
    return CurTime() - self:GetPossessTime(ply)
end

-- Returns the real view type used by the player
function ragmod:GetPlayerViewType(ply)
    local locked = RagModOptions.View.FirstPersonLocked:GetPlayerValue(ply)
    if RagModOptions.View.ForcedView() then return RagModOptions.View.ForcedViewType(), locked end

    return RagModOptions.View.ViewType:GetPlayerValue(ply), locked
end

-- Client only has the getter functions.
-- Everything else is Serverside only
if CLIENT then return ragmod end

--[[
    Methods
]]
-- All-in-one function that tries to ragdoll the given player.
-- Creates, spawns and possesses the ragdoll automatically
-- Returns the ragdoll or NULL if not possible
function ragmod:TryToRagdoll(ply)
    if self:IsRagdoll(ply) then return end -- Already possessing a ragdoll
    if not ply:IsInWorld() then return end
    local hookPrevent = hook.Run("RM_CanRagdoll", ply)
    if hookPrevent == false then return end
    local ragdoll = self:SpawnRagdoll(ply)
    if not IsValid(ragdoll) then return end

    -- Drop items
    -- Loop through all player weapons and drop them.
    if RagModOptions.DropWeapons() then
        for _, wep in ipairs(ply:GetWeapons()) do
            ply:DropWeapon(wep)
        end
    end

    -- If sandbox
    if ply.AddCleanup then
        ply:AddCleanup("Ragdolls", ragdoll)
    end

    self:PossessRagdoll(ply, ragdoll)

    return ragdoll
end

-- Creates, spawns, and returns a ragmod ragdoll based on a player
-- Setups the position and other properties based on the player
-- Returns NULL if couldn't create entity
function ragmod:SpawnRagdoll(ply)
    local ragdoll = ents.Create("prop_ragmod_ragdoll")
    if not IsValid(ragdoll) then return NULL end
    ragdoll:AssignOwner(ply)
    ragdoll:Spawn()
    table.insert(ragmod.Ragdolls, ragdoll)

    return ragdoll
end

-- This is called after the player has animated into the ragdoll
-- It changes the player spectate mode to allow other addons to use the camera
local function FinalizeTransition(ply)
    if not IsValid(ply) then return end
    local ragdoll = ragmod:GetRagmodRagdoll(ply)
    if not IsValid(ragdoll) then return end
    ply:Spectate(OBS_MODE_CHASE)
    ply:SpectateEntity(ragdoll)
end

net.Receive("ragmod::cl::possess_anim_ready", function(len, ply)
    FinalizeTransition(ply)
end)

-- Possesses the given ragmod ragdoll (Created with ragmod:SpawnRagdoll)
-- Saves the player inventory
-- Note: Use TryToRagdoll to both spawn and possess.
-- Otherwise calling this manually will bypass RM_CanRagdoll hook
function ragmod:PossessRagdoll(ply, ragdoll)
    self:SavePlayerInventory(ply)
    local aim = ply:GetAimVector()
    ply:SetEyeAngles(rmutil:AimToAngle(aim))
    local delay = RagModOptions.View.SmoothingIn:GetPlayerValue(ply)
    local spectateImmediately = RagModOptions.View.SpectateImmediately:GetPlayerValue(ply)
    local viewType = self:GetPlayerViewType(ply)

    -- Change view mode after player has finished animating into view
    if delay <= 0 or hook.Run("RM_CanChangeCamera", ply) == false then
        ply:Spectate(OBS_MODE_CHASE)
        ply:SpectateEntity(ragdoll)
    else
        if viewType == "thirdperson" or spectateImmediately then
            ply:Spectate(OBS_MODE_CHASE)
            ply:SpectateEntity(ragdoll)
        else
            ply:Spectate(OBS_MODE_IN_EYE)
        end
    end

    if ply:FlashlightIsOn() then
        ply:Flashlight(false)
    end

    ply:SetSuppressPickupNotices(false)
    ply:StripWeapons()
    ply:StripAmmo()
    ply:SetActiveWeapon(nil)
    ply:DropObject()
    ply:SetNWFloat("ragmod_PossessTime", CurTime())
    ply:SetNWEntity("ragmod_Possessed", ragdoll)
    ragdoll:Possess(ply)

    if ply:InVehicle() then
        ply:ExitVehicle()
    end

    timer.Simple(0.1, function()
        if IsValid(ply) and self:IsRagdoll(ply) then
            ply:CrosshairDisable()
        end
    end)
end

-- un-possesses a player from a ragmod ragdoll.
-- restoreState:
--      Optionally restores their inventory, health
--      Also sets the position and velocity of the player to match the ragdoll
--      Normally set to true when getting up,
--      false when player died as a ragdoll and is spawning
-- checkForSpace:
--      Set to true to adjust player spawn position to prevent getting stuck
--      Does nothing if restoreState is false.
function ragmod:UnPossessRagdoll(ply, restoreState, checkForSpace)
    if not self:IsRagdoll(ply) then return end
    local ragdoll = self:GetRagmodRagdoll(ply)
    local spawnPos = ply:GetPos()
    local spawnAngles = ply:EyeAngles()
    local spawnVelocity = ply:GetVelocity()
    local playerHealth = ply:Health()
    local playerArmor = ply:Armor()
    local hasSuit = ply:IsSuitEquipped()

    if IsValid(ragdoll) then
        local _, viewAngles = ragdoll:GetPossessorView()

        if viewAngles then
            spawnAngles = viewAngles
            spawnAngles.roll = 0
        end

        spawnPos = ragdoll:GetPos()
        spawnVelocity = ragdoll:GetVelocity()
        ragdoll:UnPossess()

        if ply == ragdoll:GetOwningPlayer() and restoreState then
            ragdoll:Remove()
        end
    end

    ply:UnSpectate()

    if checkForSpace then
        spawnPos = self:AdjustSpawnPosition(ply, spawnPos)
    end

    ply:SetNWEntity("ragmod_Possessed", NULL)
    ply:CrosshairEnable()
    if not ply:Alive() or not restoreState then return end
    -- Restoring player
    ply.Ragmod_RestoreInventory = true
    ply:Spawn()
    ply:SetHealth(playerHealth)
    ply:SetArmor(playerArmor)
    ply:SetPos(spawnPos)
    ply:SetEyeAngles(spawnAngles)

    if hasSuit then
        ply:EquipSuit()
    else
        ply:RemoveSuit()
    end

    -- Angles can't be realiably set instantly
    timer.Simple(0, function()
        if not IsValid(ply) then return end
        ply:SetEyeAngles(spawnAngles)
    end)

    ply:SetVelocity(spawnVelocity)
    ply:GetPhysicsObject():SetVelocity(spawnVelocity)
    local stage = RagModOptions.Compatibility.RestoreInventoryStage()

    if stage == "after_delay" then
        -- Timer
        timer.Simple(0.1, function()
            if not IsValid(ply) then return end
            self:RestorePlayerInventory(ply)
            ply.Ragmod_ShouldRestoreInventory = false
        end)
    end
end

-- Restores a player inventory saved with ragmod:SavePlayerInventory
function ragmod:RestorePlayerInventory(ply)
    ply:SetSuppressPickupNotices(true)
    ply:StripWeapons()
    ply:StripAmmo()
    local inventory = ply.Ragmod_SavedInventory
    if not inventory or not istable(inventory) then return end -- No saved inventory!

    if inventory.Weapons then
        for k, v in ipairs(inventory.Weapons) do
            local weapon = ply:Give(v.Class, true)
            if not IsValid(weapon) then continue end
            weapon:SetClip1(v.Clip1)
            weapon:SetClip2(v.Clip2)
        end
    end

    if inventory.Ammo then
        for ammoId, amount in pairs(inventory.Ammo) do
            ply:SetAmmo(amount, ammoId)
        end
    end

    if inventory.ActiveWeapon then
        ply:SelectWeapon(inventory.ActiveWeapon)
    end

    ply:SetSuppressPickupNotices(false)
end

-- Saves the current state of the players inventory
-- and stores it into the player table
function ragmod:SavePlayerInventory(ply)
    local inventory = {
        ActiveWeapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or nil,
        Weapons = {},
        Ammo = {}
    }

    for k, v in pairs(game.GetAmmoTypes()) do
        local amount = ply:GetAmmoCount(k)
        if amount == 0 then continue end
        inventory.Ammo[k] = amount
    end

    for k, v in pairs(ply:GetWeapons()) do
        local weapon = {
            Class = v:GetClass(),
            Clip1 = v:Clip1(),
            Clip2 = v:Clip2(),
        }

        table.insert(inventory.Weapons, weapon)
    end

    ply.Ragmod_SavedInventory = inventory
end

-- Destroys any ragmod ragdolls over the maxRagdolls limit for this player 
function ragmod:LimitPlayerRagdolls(ply, maxRagdolls)
    local playerRagdolls = {}
    local idx = 1

    while idx <= #ragmod.Ragdolls do
        local ragdoll = ragmod.Ragdolls[idx]

        if not IsValid(ragdoll) then
            -- This should not happen, but make sure all ragdolls in the table are valid
            rmutil:ArrayRemove(ragmod.Ragdolls, function(t, i, j) return i ~= idx end)
            -- Do not increment idx, array size has reduced
            continue
        end

        local owner = ragdoll:GetOwningPlayer()
        local possessor = ragdoll:GetPossessor()

        if owner == ply and not IsValid(possessor) then
            table.insert(playerRagdolls, ragdoll)
        end

        idx = idx + 1
    end

    local excess = #playerRagdolls - maxRagdolls
    if excess <= 0 then return end

    for i = 1, excess do
        local ragdoll = playerRagdolls[1] -- Should all be valid
        ragdoll:Remove()
    end
end

-- Destroys all ragmod ragdolls
function ragmod:RemoveAllRagdolls()
    for k, ent in ipairs(ents.FindByClass("prop_ragdoll")) do
        if not self:IsRagmodRagdoll(ent) then continue end
        ent:Remove()
    end
end

-------------
-- Utility --
-------------
-- Checks if an entity can fit in the position.
-- Set scale to 1 to check exact bounds, more to scale the bounds up
function ragmod:HasSpaceToSpawn(ent, pos, scale)
    local trace = {
        start = pos,
        endpos = pos,
        mins = ent:OBBMins() * scale,
        maxs = ent:OBBMaxs() * scale,
        filter = ent
    }

    return not util.TraceHull(trace).Hit
end

-- 8 directions forming a circle
local SpawnAdjustDirs = {Vector(1, 0, 0), Vector(0.71, 0.71, 0), Vector(0, 1, 0), Vector(-0.71, 0.71, 0), Vector(-1, 0, 0), Vector(-0.71, -0.71, 0), Vector(0, -1, 0), Vector(0.71, -0.71, 0),}

-- Tries to nudge the given position somewhere the entity can spawn
function ragmod:AdjustSpawnPosition(ent, pos)
    local curPos = pos

    if self:HasSpaceToSpawn(ent, curPos, 1.1) then
        return curPos
    else
        local tries = 0

        while tries < #SpawnAdjustDirs * 8 do
            tries = tries + 1
            -- Does a weird growing spiral thing around the position until space is found
            curPos = pos + SpawnAdjustDirs[(tries % #SpawnAdjustDirs) + 1] * math.floor((tries + 1) / #SpawnAdjustDirs) * 4
            curPos = curPos + Vector(0, 0, 1) * math.floor((tries + 1) / #SpawnAdjustDirs * 4)
            if self:HasSpaceToSpawn(ent, curPos, 1.1) then return curPos end
        end

        return pos
    end
end

-- Used when the player can't receive damage directly
-- Applies the damage in the given damageinfo. Kills the player if health <= 0
function ragmod:PropagateDamage(ply, dmginfo)
    ply:SetHealth(ply:Health() - dmginfo:GetDamage())

    -- Make sure to not kill the player multiple times
    if ply:Health() <= 0 and ply:Alive() then
        -- ragmod:UnPossessRagdoll(ply, true, false)
        -- Dmginfo will be destroyed, cache the values for the timer
        local amount = dmginfo:GetDamage()
        local base = dmginfo:GetBaseDamage()
        local att = dmginfo:GetAttacker()
        local inf = dmginfo:GetInflictor()
        local type = dmginfo:GetDamageType()
        local spawnPos = ply:GetPos()
        local spawnAngles = ply:EyeAngles()
        local ragdoll = ragmod:GetRagmodRagdoll(ply)

        if IsValid(ragdoll) then
            local _, viewAngles = ragdoll:GetPossessorView()
            spawnPos = ragdoll:GetPos()

            if viewAngles then
                spawnAngles = viewAngles
                spawnAngles.roll = 0
            end
        end

        -- Set flag to skip the usual spawn logic
        ply.Ragmod_PropagateDeath = true
        ply:UnSpectate()
        ply:Spawn()
        ply:SetPos(spawnPos)
        ply:SetEyeAngles(spawnAngles)
        local dmg = DamageInfo()
        ply:SetHealth(0)
        dmg:SetAttacker(IsValid(att) and att or game.GetWorld())
        dmg:SetInflictor(IsValid(inf) and inf or game.GetWorld())
        dmg:SetBaseDamage(base)
        dmg:SetDamage(amount)
        dmg:SetDamageType(type)
        ply:TakeDamageInfo(dmg)

        -- If the player still didn't die somehow, fallback to kill()
        if ply:Alive() then
            ply:Kill()
        end
    end
end

-- Keeps track of removed ragdolls
local function OnRagdollRemoved(ragdoll, possessor)
    if IsValid(possessor) then
        ragmod:UnPossessRagdoll(possessor, possessor:Alive())
    end

    table.RemoveByValue(ragmod.Ragdolls, ragdoll)
end

hook.Add("ragmod_RagdollRemoved", "ragmod_OnRagdollRemoved", OnRagdollRemoved)

local function PlayerLoadout(ply)
    local stage = RagModOptions.Compatibility.RestoreInventoryStage()

    -- On Loadout
    if ply.Ragmod_RestoreInventory and stage == "on_loadout" then
        ragmod:RestorePlayerInventory(ply)

        return true
    end
end

-- Sets the initial networked variable states
local function OnPlayerInitialSpawn(ply, transition)
    if transition then return end
    ply:SetNWEntity("ragmod_Possessed", NULL)
    ply.Ragmod_RestoreInventory = false
end

local function PlayerSpawn(ply, transition)
    if transition then return end
    local stage = RagModOptions.Compatibility.RestoreInventoryStage()

    if ply.Ragmod_PropagateDeath then
        ply.Ragmod_PropagateDeath = nil

        return true
    end

    -- Usually happens when player died 
    if ragmod:IsRagdoll(ply) then
        ragmod:UnPossessRagdoll(ply, ply.Ragmod_RestoreInventory, false)
    end

    if ply.Ragmod_RestoreInventory and stage == "on_spawn" then
        ragmod:RestorePlayerInventory(ply)

        return true
    end
end

local function PostPlayerDeath(ply)
    local normalDeath = RagModOptions.Misc.NormalDeathRagdolls()

    if not normalDeath then
        if IsValid(ply:GetRagdollEntity()) then
            ply:GetRagdollEntity():Remove()
        end
    end

    ply.Ragmod_RestoreInventory = false

    -- Player already possessing a ragdoll
    if ragmod:IsRagdoll(ply) then
        -- Remove possession
        local ragdoll = ragmod:GetRagmodRagdoll(ply)

        if RagModOptions.DropWeapons() then
            ragmod:RestorePlayerInventory(ply)

            for _, wep in ipairs(ply:GetWeapons()) do
                ply:DropWeapon(wep)
            end
        end

        if IsValid(ragdoll) then
            if normalDeath and IsValid(ply:GetRagdollEntity()) then
                ply:GetRagdollEntity():Remove()
            end
        end

        return
    end

    if normalDeath then return end
    -- Player wasn't possessing a ragdoll when dying
    local ragdoll = ragmod:TryToRagdoll(ply)
end

hook.Add("PostPlayerDeath", "ragmod_PostPlayerDeath", PostPlayerDeath)
hook.Add("PlayerLoadout", "ragmod_PlayerLoadout", PlayerLoadout)
hook.Add("PlayerSpawn", "ragmod_PlayerSpawnLoadout", PlayerSpawn)
hook.Add("PlayerInitialSpawn", "ragmod_PlayerInitialSpawn", OnPlayerInitialSpawn)

return ragmod