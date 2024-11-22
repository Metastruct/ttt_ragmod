----------------------------------------------------------
-- Title: sv_ragmod
-- Author: n-gon
-- Description:
----- Ragmod server autorun
----------------------------------------------------------
-- Network Strings
util.AddNetworkString("ragmod::cl::input") -- Used for all input from client to server
util.AddNetworkString("ragmod::cl::custom_view") -- Used for free camera
util.AddNetworkString("ragmod::cl::clear_all") -- Used to remove all ragdolls
util.AddNetworkString("ragmod::cl::possess_anim_ready") -- Used to notify server when possess animation is complete
util.AddNetworkString("ragmod::sv::local_unpossessed") -- Used to notify server when possess animation is complete
-- Make translations work on servers
resource.AddSingleFile("2817879135")

-------------------------------------------------------------
--              CVARS AND FILE SCOPE VARIABLES             -- 
-------------------------------------------------------------
-- Contains the initial input state for players
local InitialInputState = {
    Fly = false,
    Reach = {
        ArmRight = false,
        ArmLeft = false,
    },
    IN_FORWARD = false,
    IN_BACK = false,
    IN_MOVERIGHT = false,
    IN_MOVELEFT = false,
    EyeAngles = Angle(0, 0, 0),
}

-----------------------------------
--              MAIN             -- 
-----------------------------------
-- Returns true if the given velocity is over the SpeedThreshold setting
local function IsVelocityOverSpeedThreshold(velocity)
    return velocity:Length() >= RagModOptions.Trigger.SpeedThreshold()
end

-- Returns true if the given entity is exceeding the speed triggers
-- Doesn't take noclip settings or being in a vehicle into account. 
-- For that see ShouldPlayerSpeedRag
local function ShouldSpeedRag(ent)
    if not RagModOptions.Trigger.Speed() then return false end
    local onlyFall = RagModOptions.Trigger.OnlyFall()
    local velocity = ent:GetVelocity()

    -- Only leave negative z
    if onlyFall then
        velocity.z = math.Min(velocity.z, 0)
    end

    return IsVelocityOverSpeedThreshold(velocity)
end

-- Used in tick to check if a player should ragdoll from speed
local function ShouldPlayerSpeedRag(ply)
    local noclipRagging = RagModOptions.Trigger.SpeedNoclip()
    local isNoclipping = ply:GetMoveType() == MOVETYPE_NOCLIP
    if isNoclipping and not noclipRagging then return false end
    if ply:InVehicle() then return false end

    return ShouldSpeedRag(ply)
end

------------------------
-- Main functionality --
------------------------
---------------------
-- Client commands --
---------------------
local function ResetAllConVars()
    local function ResetRecursive(tab)
        for k, v in pairs(tab) do
            if istable(v) then
                ResetRecursive(v)
            elseif type(v) == "ConVar" then
                v:Revert()
            end
        end
    end

    ResetRecursive(RagModOptions)
    print("All server ConVars have been reset")
end

concommand.Add("rm_reset", function(ply, _, _, _)
    if IsValid(ply) and not ply:IsAdmin() then return end -- Allow only from admin and server
    ResetAllConVars()
end, nil, "Reset all server settings", FCVAR_NONE)

local function ClientRequestRagdoll(ply)
    if not RagModOptions.ManualRagdolling() then return end
    if ragmod:IsRagdoll(ply) or not ply:Alive() then return end -- Already a ragdoll 
    local inVehicle = ply:InVehicle()
    local veh = ply:GetVehicle()
    local ragdoll = ragmod:TryToRagdoll(ply)
    if not IsValid(ragdoll) then return end
    ragdoll:PlayRagSound()

    if inVehicle and IsValid(veh) then
        ragdoll:SetCollisionGroup(COLLISION_GROUP_WEAPON)

        timer.Simple(0.2, function()
            if not IsValid(ragdoll) or ragdoll:GetCollisionGroup() ~= COLLISION_GROUP_WEAPON then return end
            ragdoll:SetCollisionGroup(COLLISION_GROUP_NONE)
        end)
    end
end

local function ClientRequestUnPossess(ply)
    if not ply:Alive() or not ragmod:IsRagdoll(ply) then return end -- This would mean the clients version is outdated
    local ragdoll = ragmod:GetRagmodRagdoll(ply)
    -- Force player to be a ragdoll for set amount of time
    local hasRaggedEnough = ragmod:GetTimeSincePossess(ply) >= RagModOptions.Ragdolling.GetUpDelay()

    -- Always allow unpossess if ragdoll somehow doesnt exist
    if not IsValid(ragdoll) then
        ragmod:UnPossessRagdoll(ply, true, RagModOptions.Misc.AdjustSpawn())

        return
    end

    if ShouldSpeedRag(ragdoll) or not hasRaggedEnough then return end
    ragmod:UnPossessRagdoll(ply, true, RagModOptions.Misc.AdjustSpawn())
end

-- Resets players ragmod input to the default values
local function ResetPlayerInputState(ply)
    ply.RagmodInputState = table.Copy(InitialInputState)
end

-- Input using the source engine input system (IN enums) is handled here
local function HandleBuiltInInput(ply, key, pressed)
    if not ply.RagmodInputState then
        ResetPlayerInputState(ply)
    end

    ply.RagmodInputState[key] = pressed
end

-- Receive custom camera angles from players in first person view
local function HandleCamInput(ply, angle)
    if not ply.RagmodInputState then
        ResetPlayerInputState(ply)
    end

    ply.RagmodInputState.EyeAngles = angle
end

-- Input using the custom ragmod input system is handled here
local function HandleInput(ply, id)
    if not Ragmod_Enabled or id == 0 then return end
    local actionId = math.abs(id)
    if #RagmodInputTable < actionId then return end
    local action = RagmodInputTable[actionId]
    if not action then return end
    local pressed = id > 0
    rmutil:DebugPrint(string.format("Input %s: %s %s", ply:Nick(), action.Name, pressed and "pressed" or "released"))

    -- Initial spawn should have done this unless someone blocked it
    if not ply.RagmodInputState then
        ResetPlayerInputState(ply)
    end

    if action.Name == "ragdolize" and pressed then
        if hook.Run("RM_CanAction", ply, action.Name) == false then return end
        ClientRequestRagdoll(ply)
    elseif action.Name == "unpossess" and not pressed then
        if hook.Run("RM_CanAction", ply, action.Name) == false then return end
        ClientRequestUnPossess(ply)
    elseif action.Name == "fly" then
        if hook.Run("RM_CanAction", ply, action.Name) == false then return end
        ply.RagmodInputState.Fly = pressed
    elseif action.Name == "reach_right" then
        if hook.Run("RM_CanAction", ply, action.Name) == false then return end
        ply.RagmodInputState.Reach.ArmRight = pressed
    elseif action.Name == "reach_left" then
        if hook.Run("RM_CanAction", ply, action.Name) == false then return end
        ply.RagmodInputState.Reach.ArmLeft = pressed
    end
end

hook.Add("PlayerInitialSpawn", "ragmod_PlayerInitialSpawnInput", function(ply, _)
    ResetPlayerInputState(ply)
end)

local function AddInputHooks()
    if game.SinglePlayer() then
        hook.Add("ragmod::sp_input", "ragmod_SinglePlayerInput", function(id)
            HandleInput(player.GetByID(1), id)
        end)
    else
        net.Receive("ragmod::cl::input", function(_, ply)
            local id = net.ReadInt(8)
            if id == 0 then return end
            HandleInput(ply, id)
        end)
    end

    net.Receive("ragmod::cl::custom_view", function(_, ply)
        local angle = net.ReadAngle()
        HandleCamInput(ply, angle)
    end)

    net.Receive("ragmod::cl::clear_all", function(_, ply)
        if not ply:IsAdmin() then return end
        ragmod:RemoveAllRagdolls()
    end)

    hook.Add("KeyPress", "ragmod_KeyPress", function(ply, key)
        HandleBuiltInInput(ply, key, true)
    end)

    hook.Add("KeyRelease", "ragmod_KeyRelease", function(ply, key)
        HandleBuiltInInput(ply, key, false)
    end)
end

-----------------
-- Hook events --
-----------------
local function OnPlayerSpawn(ply, transition)
    -- Workaround for the players current ragdoll existing when they get up
    -- One frame delay wasn't enough 
    timer.Simple(engine.TickInterval() * 2, function()
        if not IsValid(ply) then return end
        ragmod:LimitPlayerRagdolls(ply, RagModOptions.RagdollLimit())
    end)
end

local function PlayerDisconnected(ply)
    ragmod:LimitPlayerRagdolls(ply, RagModOptions.RagdollLimit())
end

local function OnVehicleCollision(veh, colData)
    if not RagModOptions.Trigger.VehicleImpact() then return end
    local impactThreshold = RagModOptions.Trigger.VehicleImpactThreshold()
    local oldVelocity = colData.OurOldVelocity
    local newVelocity = colData.OurNewVelocity
    local velocityDelta = oldVelocity - newVelocity
    if velocityDelta:Length() < impactThreshold then return end
    local ply = veh:GetDriver()
    if not IsValid(ply) then return end
    local ragdoll = ragmod:TryToRagdoll(ply)
    if not IsValid(ragdoll) then return end
    -- Apply our own velocity since the ragdoll will try to use the vehicles post-crash velocity
    ragdoll:SetVelocity(colData.OurOldVelocity)
end


local function OnEntityTakeDamage(ent, dmginfo)
    local inflictor = dmginfo:GetInflictor()

    if IsValid(inflictor) and ragmod:IsRagmodRagdoll(inflictor) then
        -- Something took damage from our custom ragdoll
        -- Replace attacker with the ragdoll possessor
        local ragdoll = dmginfo:GetInflictor()
        local possessor = ragdoll:GetPossessor()
        local attacker = dmginfo:GetAttacker()

        if IsValid(possessor) and IsValid(attacker) and attacker == ragdoll then
            dmginfo:SetAttacker(possessor)
        end
    end

    if not IsValid(ent) then return end -- Maybe this can happen?

    if ragmod:IsRagmodRagdoll(ent) then
        -- Take damage as a ragdoll
        ent:ProcessDamage(dmginfo)

        return
    end

    if not ent:IsPlayer() or not ent:Alive() then return end
    local ply = ent
    if ragmod:IsRagdoll(ply) then return end -- Player took damage as a ragdoll somehow
    -- Ent was a player, gather all the trigger and damage settings
    if ply:InVehicle() and not RagModOptions.Trigger.DamageInVehicle() then return end
    local TriggerExplosion = RagModOptions.Trigger.Explosion()
    local TriggerFall = RagModOptions.Trigger.FallImpact()
    local TriggerDamage = RagModOptions.Trigger.Damage()
    local TriggerDamageThreshold = RagModOptions.Trigger.DamageThreshold()
    local DamageForceMultipler = RagModOptions.Damage.ForceMultiplier()
    local GodMode = RagModOptions.Damage.GodMode()
    local RocketJump = RagModOptions.Trigger.RocketJump()
    -- Take damage as a player
    local explosionTrigger = (TriggerExplosion or RocketJump) and dmginfo:IsExplosionDamage()
    local fallTrigger = TriggerFall and dmginfo:IsFallDamage()
    local dmgTrigger = TriggerDamage and dmginfo:GetDamage() >= TriggerDamageThreshold

    if dmgTrigger or fallTrigger or explosionTrigger then
        -- A trigger condition was met
        local ragdoll = ragmod:TryToRagdoll(ply)

        if not (dmginfo:IsExplosionDamage() and RocketJump) then
            ragdoll:PlayPainSound()

            if not GodMode then
                ragmod:PropagateDamage(ply, dmginfo)
            end
        end

        if not IsValid(ragdoll) then return end
        ragdoll:AddVelocity(DamageForceMultipler * dmginfo:GetDamageForce() / 100)
    end
end

local function CanPlayerEnterVehicle(ply, veh, role)
    if ragmod:IsRagdoll(ply) then return false end
end

local function PlayerNoClip(ply, desiredState)
    if ragmod:IsRagdoll(ply) then return false end
end

local function TickPlayer(ply)
    if ragmod:IsRagdoll(ply) then return end
    if not ShouldPlayerSpeedRag(ply) then return end
    local ragdoll = ragmod:TryToRagdoll(ply)

    if IsValid(ragdoll) then
        ragdoll:PlayRagSound()
    end
end

local function Tick()
    for _, ragdoll in ipairs(ragmod.Ragdolls) do
        -- This shouldn't happen unless someone broke something
        if not IsValid(ragdoll) then
            table.RemoveByValue(ragmod.Ragdolls, ragdoll)
        end

        ragdoll:Tick()
    end

    for _, ply in ipairs(player.GetHumans()) do
        TickPlayer(ply)
    end
end

local function PlayerLeaveVehicle(ply, veh)
    if not RagModOptions.Trigger.Speed() then return end
    if not IsValid(ply) or not IsValid(veh) or ragmod:IsRagdoll(ply) or IsValid(ragmod:GetRagmodRagdoll(ply)) then return end
    if not IsVelocityOverSpeedThreshold(veh:GetVelocity()) then return end
    local _, angle, _ = veh:GetVehicleViewPosition(0) -- Todo: keep track of seat
    ply:SetAngles(angle) -- Match seat angles
    local ragdoll = ragmod:TryToRagdoll(ply)
    if not IsValid(ragdoll) then return end
    local launchVelocity = veh:GetVelocity()
    local physObj = veh:GetPhysicsObject()

    if IsValid(physObj) and physObj:IsValid() then
        launchVelocity = physObj:GetVelocityAtPoint(ply:GetPos())
    end

    ragdoll:SetVelocity(launchVelocity)
    ragdoll:PlayRagSound()
end

local function AddVehicleCollisionCallback(veh)
    veh.Ragmod_VehicleCollisionCallback = veh:AddCallback("PhysicsCollide", OnVehicleCollision)
end

local function RemoveVehicleCollisionCallback(veh)
    if not IsValid(veh) then return end

    if veh.Ragmod_VehicleCollisionCallback then
        veh:RemoveCallback("PhysicsCollide", veh.Ragmod_VehicleCollisionCallback)
    end
end

local function PlayerLeaveVehicleCleanup(_, veh)
    RemoveVehicleCollisionCallback(veh)
end

local function PlayerEnteredVehicle(_, veh, role)
    AddVehicleCollisionCallback(veh)
end

local function CanDrive(ply, _)
    if ragmod:IsRagdoll(ply) then return false end
end

-- Disallow flashlight when ragdolling
local function PlayerSwitchFlashlight(ply, enabled)
    if not enabled then return end
    if ragmod:IsRagdoll(ply) then return false end
end

local function AddSpawnmenuHooks()
    local function IsAllowedToSpawnItem(ply, ...)
        if ragmod:IsRagdoll(ply) and not RagModOptions.Misc.AllowSpawnmenu() then return false end
    end

    hook.Add("PlayerSpawnEffect", "ragmod_PlayerSpawnEffect", IsAllowedToSpawnItem)
    hook.Add("PlayerSpawnNPC", "ragmod_PlayerSpawnNPC", IsAllowedToSpawnItem)
    hook.Add("PlayerSpawnObject", "ragmod_PlayerSpawnObject", IsAllowedToSpawnItem)
    hook.Add("PlayerSpawnProp", "ragmod_PlayerSpawnProp", IsAllowedToSpawnItem)
    hook.Add("PlayerSpawnRagdoll", "ragmod_PlayerSpawnRagdoll", IsAllowedToSpawnItem)
    hook.Add("PlayerSpawnSENT", "ragmod_PlayerSpawnSENT", IsAllowedToSpawnItem)
    hook.Add("PlayerSpawnSWEP", "ragmod_PlayerSpawnSWEP", IsAllowedToSpawnItem)
    hook.Add("PlayerSpawnVehicle", "ragmod_PlayerSpawnVehicle", IsAllowedToSpawnItem)
    hook.Add("PlayerCanPickupWeapon", "ragmod_PlayerCanPickupWeapon", IsAllowedToSpawnItem)
end

concommand.Add("rm_cleanup_all", function(ply, cmd, args, argStr)
    ragmod:RemoveAllRagdolls()
end, nil, "", 0)

-----------------------
-- Addon setup stuff --
-----------------------
-- Add hooks that are always enabled
local function AddRequiredHooks()
    -- Player events hooks
    hook.Add("PlayerNoClip", "ragmod_PlayerNoClip", PlayerNoClip)
    hook.Add("CanPlayerEnterVehicle", "ragmod_CanPlayerEnterVehicle", CanPlayerEnterVehicle)
    hook.Add("PlayerLeaveVehicle", "ragmod_PlayerLeaveVehicleCleanup", PlayerLeaveVehicleCleanup) -- Remove callback, so required
    hook.Add("CanDrive", "ragmod_CanDrive", CanDrive)
    hook.Add("PlayerSwitchFlashlight", "ragmod_PlayerSwitchFlashlight", PlayerSwitchFlashlight)
    AddSpawnmenuHooks()
    AddInputHooks()
end

-- Add hooks that are removed when disabling the addon
local function AddHooks()
    hook.Add("PlayerSpawn", "ragmod_PlayerSpawn", OnPlayerSpawn)
    hook.Add("PlayerDisconnected", "ragmod_PlayerDisconnected", PlayerDisconnected)
    hook.Add("EntityTakeDamage", "ragmod_EntityTakeDamage", OnEntityTakeDamage)
    hook.Add("Tick", "ragmod_Tick", Tick)
    hook.Add("PlayerEnteredVehicle", "ragmod_PlayerEnteredVehicle", PlayerEnteredVehicle)
    hook.Add("PlayerLeaveVehicle", "ragmod_PlayerLeaveVehicle", PlayerLeaveVehicle) -- Checks for triggers

    for _, ply in ipairs(player.GetAll()) do
        if not ply:InVehicle() then continue end
        local veh = ply:GetVehicle()
        AddVehicleCollisionCallback(veh)
    end
end

local function RemoveHooks()
    hook.Remove("PlayerSpawn", "ragmod_PlayerSpawn")
    hook.Remove("EntityTakeDamage", "ragmod_EntityTakeDamage")
    hook.Remove("PostPlayerDeath", "ragmod_PostPlayerDeath")
    hook.Remove("Tick", "ragmod_Tick")
    hook.Remove("PlayerEnteredVehicle", "ragmod_PlayerEnteredVehicle")
    hook.Remove("PlayerLeaveVehicle", "ragmod_PlayerLeaveVehicle")

    for _, ply in ipairs(player.GetAll()) do
        if not ply:InVehicle() then continue end
        local veh = ply:GetVehicle()
        RemoveVehicleCollisionCallback(veh)
    end
end

local function EnableRagmod()
    if RagModOptions.Debug() then
        print("Ragmod Enabled")
    end

    AddHooks()
    Ragmod_Enabled = true
end

local function DisableRagmod()
    ragmod:RemoveAllRagdolls()
    RemoveHooks()
    Ragmod_Enabled = false
    rmutil:DebugPrint("Ragmod Disabled")
end

-- Runtime toggling
local function CvEnabledChanged(convar_name, was_enabled, is_enabled)
    if was_enabled == is_enabled then return end

    if is_enabled == "0" then
        if Ragmod_Enabled then
            DisableRagmod()
        end
    elseif not Ragmod_Enabled then
        EnableRagmod()
    end
end

local function CvRagdollLimitChanged(convar_name, old, new)
    for _, ply in ipairs(player.GetAll()) do
        ragmod:LimitPlayerRagdolls(ply, RagModOptions.RagdollLimit())
    end
end

local function Init()
    AddRequiredHooks()
    Ragmod_Enabled = RagModOptions.Enabled()

    -- Global list of all ragdolls
    if Ragmod_Enabled then
        EnableRagmod()
    end

    cvars.AddChangeCallback(RagModOptions.Enabled.ConVar:GetName(), CvEnabledChanged)
    cvars.AddChangeCallback(RagModOptions.RagdollLimit.ConVar:GetName(), CvRagdollLimitChanged)
    ------------------
    ----  RagMod  ----
    ------------------
    print("------------------\n----- RagMod -----\n------------------")
end

Init()