-------------------------------------------------------------------
-- Title: ragmod_options
-- Author: n-gon
-- Description:
----- Module for RagMod options. Contains a global "RagModOptions"
----- Options are wrappers for ConVars but also contain
----- type info, and extra properties for creating menus.
-------------------------------------------------------------------
require("ragmod_utils")
RagModOptions = {}
local RAGMOD_VERSION = "1.30"

local FlagsSaveNotify = {FCVAR_NOTIFY, FCVAR_SERVER_CAN_EXECUTE, FCVAR_ARCHIVE}

local FlagsSave = {FCVAR_SERVER_CAN_EXECUTE, FCVAR_ARCHIVE}

local FlagsSaveSync = {FCVAR_SERVER_CAN_EXECUTE, FCVAR_ARCHIVE, FCVAR_REPLICATED}

----------------------------
-- Option metatable setup --
----------------------------
local optionMeta = {}

function optionMeta:__call(new)
    -- Set a new value
    if new ~= nil then

        if self.Type == TYPE_BOOL then
            new = new and 1 or 0
        end

        RunConsoleCommand(self.Name, new)
    end

    -- Return the current value
    if self.Type == TYPE_NUMBER then
        if self.Choices then return self.Choices[self.ConVar:GetInt() + 1] end

        return self.ConVar:GetFloat()
    elseif self.Type == TYPE_BOOL then
        return self.ConVar:GetBool()
    end

    return self.ConVar:GetString()
end

function optionMeta:__tostring()
    return string.format("Option [%s]: %s", self.Name, tostring(self()))
end

local optionIndex = {}

-- Gets the value a player has set an option
function optionIndex:GetPlayerValue(ply)
    if CLIENT and ply == LocalPlayer() then return self() end
    local numVal = ply:GetInfoNum(self.Name, 0)
    local val = ply:GetInfo(self.Name, nil)
    if self.Type == TYPE_BOOL then return tobool(numVal) end
    if self.Type == TYPE_STRING then return val end

    if self.Type == TYPE_NUMBER then
        if self.Choices then
            return self.Choices[math.floor(numVal) + 1]
        else
            return numVal
        end
    end
end

-- Add helpers for callbacks
function optionIndex:AddChangeCallback(func, id)
    cvars.AddChangeCallback(self.Name, func, id and "option_" .. id or nil)
end

function optionIndex:RemoveChangeCallback(id)
    cvars.RemoveChangeCallback(self.Name, "option_" .. id)
end

optionMeta.__index = optionIndex
--------------------
-- Callback setup --
--------------------
-- Needed to call callbacks properly
local cvarOptionMap = {}

local typeStrings = {
    [TYPE_BOOL] = "bool",
    [TYPE_STRING] = "string",
    [TYPE_NUMBER] = "float",
}

---------------------
-- Option Creation --
---------------------
--[[
Option input structure
{
    name = "rm_*",
    helptext = "", -- Serverside only helptext
    default = 0,
    min = nil,
    max = nil,
    GUIMin = nil,
    GUIMax = nil,
    flags = FCVAR_NONE,
    client = nil,
    shouldsave = false,
    userinfo = false,
    choices = {""},
}
]]
local function CreateOption(tbl)
    local option = {}
    setmetatable(option, optionMeta)
    option.Name = tbl.name
    option.Type = TypeID(tbl.default)
    option.GUIMax = tbl.GUIMax
    option.GUIMin = tbl.GUIMin
    option.Client = tobool(tbl.client)
    local helptext = SERVER and (tbl.helptext or "") or rmutil:GetPhrase("convar.help." .. option.Name)
    local flags = tbl.flags or FCVAR_NONE
    local min = tbl.min
    local max = tbl.max
    local default = tbl.default

    -- Booleans need some special treatment
    if option.Type == TYPE_BOOL then
        -- CreateConVar doesn't like boolean default values
        default = default and 1 or 0
        min = 0
        max = 1
    end

    local choices = {}

    if tbl.choices then
        for _, choice in ipairs(tbl.choices) do
            if not isstring(choice) then
                ErrorNoHaltWithStack("Invalid choice: ", option.Name, choice)
                continue
            end

            table.insert(choices, choice)
        end

        option.Choices = choices
        min = 0
        max = #choices - 1
    end

    if tbl.client then
        if CLIENT or game.SinglePlayer() then
            option.ConVar = CreateClientConVar(option.Name, default, tbl.shouldsave, tbl.userinfo, helptext, min, max)
        end
    else
        option.ConVar = CreateConVar(option.Name, default, flags, helptext, min, max)
    end

    -- Also store ref to option in a lookup table
    cvarOptionMap[option.Name] = option

    return option
end

------------------------
-- All of the options --
------------------------
RagModOptions = {
    Debug = CreateOption({
        name = "rm_debug",
        helptext = "Print potential errors and debug info",
        default = false,
        flags = FCVAR_REPLICATED,
    }),
    Version = CreateOption({
        name = "rm_version",
        helptext = "Current addon version. Changing this does nothing",
        default = RAGMOD_VERSION,
        flags = FCVAR_PRINTABLEONLY,
    }),
    Tips = CreateOption({
        name = "rm_show_tips",
        helptext = "Show notifications",
        default = true,
        shouldsave = true,
        userinfo = false,
        client = true,
    }),
    Enabled = CreateOption({
        name = "rm_enabled",
        helptext = "Disable to stop players from ragdolling",
        default = true,
        flags = FlagsSaveNotify,
    }),
    ManualRagdolling = CreateOption({
        name = "rm_enable_manual",
        helptext = "Disable to prevent players from ragdolling with a keybind",
        default = true,
        flags = FlagsSaveSync,
    }),
    RagdollLimit = CreateOption({
        name = "rm_ragdoll_limit",
        helptext = "Maximum dead ragdolls to leave per player. Too many active ragdolls may cause low performance",
        default = 1,
        flags = FlagsSave,
        min = 0,
        GUIMin = 0,
        GUIMax = 10,
    }),
    DropWeapons = CreateOption({
        name = "rm_drop_weapons",
        helptext = "Make players drop their weapons when ragging",
        default = false,
        flags = FlagsSave,
    }),
    DoorBreaching = {
        Enable = CreateOption({
            name = "rm_doorbreaching",
            helptext = "Allow ragdolls to destroy doors",
            default = true,
            flags = FlagsSave,
        }),
        Resistance = CreateOption({
            name = "rm_door_resistance",
            helptext = "How hard ragdolls have to hit doors to breach them",
            default = 500,
            flags = FlagsSave,
            min = 0,
            GUIMin = 0,
            GUIMax = 1000
        }),
        LaunchPower = CreateOption({
            name = "rm_door_launch_power",
            helptext = "How much force is used to launch breached doors",
            default = 1,
            flags = FlagsSave,
            GUIMin = 0,
            GUIMax = 5
        }),
    },
    Misc = {
        AdjustSpawn = CreateOption({
            name = "rm_spawn_unstuck",
            helptext = "Try to prevent player from getting up inside props",
            default = true,
            flags = FlagsSave,
        }),
        AllowSpawnmenu = CreateOption({
            name = "rm_allow_spawnmenu",
            helptext = "Whether ragdolled players should be able to spawn items from the spawnmenu",
            default = false,
            flags = FlagsSave,
        }),
        NormalDeathRagdolls = CreateOption({
            name = "rm_normal_death_ragdolls",
            helptext = "When set death ragdolls are regular clientside ragdolls",
            default = false,
            flags = FlagsSave,
        }),
    },
    Compatibility = {
        RestoreInventoryStage = CreateOption({
            name = "rm_inventory_stage",
            helptext = "When the inventory is restored. The correct setting depends on other installed addons",
            default = 0,
            flags = FlagsSave,
            choices = {"on_loadout", "on_spawn", "after_delay",},
        })
    },
    View = {
        ViewType = CreateOption({
            name = "rm_view_type",
            helptext = "Which view type to use when ragdolling",
            default = 0,
            shouldsave = true,
            userinfo = true,
            client = true,
            choices = {"thirdperson", "firstperson", "firstperson_pos_only",},
        }),
        SmoothingIn = CreateOption({
            name = "rm_view_smooth_in",
            helptext = "How long should the transition from player to ragdoll take",
            default = 0.4,
            shouldsave = true,
            userinfo = true,
            min = 0,
            GUIMax = 2.0,
            max = 10.0,
            client = true,
        }),
        SmoothingOut = CreateOption({
            name = "rm_view_smooth_out",
            helptext = "How long should the transition from ragdoll to player take",
            default = 0.4,
            shouldsave = true,
            userinfo = true,
            min = 0,
            GUIMax = 2.0,
            max = 10.0,
            client = true,
        }),
        SpectateImmediately = CreateOption({
            name = "rm_view_spectate_immediately",
            helptext = "Prevents the view from staying still when ragdolling in high ping servers",
            default = false,
            shouldsave = true,
            userinfo = true,
            client = true,
        }),
        ZNear = CreateOption({
            name = "rm_view_nearclip",
            helptext = "Nothing closer than this to the camera is rendered",
            default = 4.0,
            shouldsave = true,
            userinfo = false,
            min = 0.01,
            max = 6.0,
            client = true,
        }),
        Offset = CreateOption({
            name = "rm_view_offset_depth",
            helptext = "Offset the view depth in first-person modes",
            default = -1,
            shouldsave = true,
            userinfo = false,
            min = -5.0,
            max = 3.,
            client = true,
        }),
        HeightOffset = CreateOption({
            name = "rm_view_offset_height",
            helptext = "Offset the view height in first-person modes",
            default = 0,
            shouldsave = true,
            userinfo = false,
            min = -3.0,
            max = 3.,
            client = true,
        }),
        FirstPersonLocked = CreateOption({
            name = "rm_view_first_person_locked",
            helptext = "Lock your head exactly to the ragdolls eyes",
            default = false,
            shouldsave = true,
            userinfo = true,
            client = true,
        }),
        HideHead = CreateOption({
            name = "rm_view_first_person_hide_head",
            helptext = "Hide the players head in first person",
            default = true,
            shouldsave = true,
            userinfo = false,
            client = true,
        }),
        ForcedView = CreateOption({
            name = "rm_view_force",
            helptext = "Force all players to use the same perspective",
            default = false,
            flags = FlagsSaveSync,
        }),
        ForcedViewType = CreateOption({
            name = "rm_view_force_type",
            helptext = "Which view type is forced for everyone",
            default = 0,
            flags = FlagsSaveSync,
            choices = {"thirdperson", "firstperson", "firstperson_pos_only",},
        }),
    },
    Trigger = {
        Damage = CreateOption({
            name = "rm_trigger_damage",
            helptext = "Ragdoll when taking damage over the threshold",
            default = true,
            flags = FlagsSave,
        }),
        DamageThreshold = CreateOption({
            name = "rm_trigger_damage_threshold",
            helptext = "Cause ragdolling when taking more damage than this",
            default = 100,
            flags = FlagsSave,
            min = 0,
            GUIMax = 500
        }),
        Explosion = CreateOption({
            name = "rm_trigger_explosion",
            helptext = "Always ragdoll from explosions",
            default = false,
            flags = FlagsSave,
        }),
        Speed = CreateOption({
            name = "rm_trigger_speed",
            helptext = "Ragdoll when going over the speed threshold",
            default = true,
            flags = FlagsSave,
        }),
        OnlyFall = CreateOption({
            name = "rm_trigger_speed_only_fall",
            helptext = "Only falling speed is taken into consideration",
            default = false,
            flags = FlagsSave,
        }),
        VehicleImpact = CreateOption({
            name = "rm_trigger_vehicle_crash",
            helptext = "Ragdoll when crashing with a vehicle",
            default = true,
            flags = FlagsSave,
        }),
        VehicleImpactThreshold = CreateOption({
            name = "rm_trigger_vehicle_crash_threshold",
            helptext = "Ragdoll when crashing harder than this",
            default = 700,
            flags = FlagsSave,
            min = 0,
            GUIMax = 2000
        }),
        FallImpact = CreateOption({
            name = "rm_trigger_fall",
            helptext = "Ragdoll when falling",
            default = true,
            flags = FlagsSave,
        }),
        SpeedNoclip = CreateOption({
            name = "rm_trigger_speed_noclip",
            helptext = "Allow noclipping to cause ragdolling",
            default = false,
            flags = FlagsSave,
        }),
        SpeedThreshold = CreateOption({
            name = "rm_trigger_speed_threshold",
            helptext = "Ragdoll when going faster than this",
            default = 1000,
            flags = FlagsSave,
            min = 0,
            GUIMin = 300,
            GUIMax = 2000
        }),
        RocketJump = CreateOption({
            name = "rm_rocketjump",
            helptext = "Never take explosion damage, ragdoll from explosions",
            default = false,
            flags = FlagsSave,
        }),
        DamageInVehicle = CreateOption({
            name = "rm_trigger_damage_vehicle",
            helptext = "Apply damage triggers in vehicles",
            default = false,
            flags = FlagsSave,
        })
    },
    Damage = {
        GodMode = CreateOption({
            name = "rm_damage_godmode",
            helptext = "Make ragdolls invincible",
            default = false,
            flags = FlagsSave,
        }),
        Bodypart = CreateOption({
            name = "rm_damage_bodypart",
            helptext = "Scale damage depending on hit body part",
            default = true,
            flags = FlagsSave,
        }),
        PvP = CreateOption({
            name = "rm_damage_pvp",
            helptext = "Allow ragdolls to be damaged by weapons",
            default = true,
            flags = FlagsSave,
        }),
        Physics = CreateOption({
            name = "rm_damage_physics",
            helptext = "Enable physics damage to ragdolls",
            default = true,
            flags = FlagsSave,
        }),
        Multiplier = CreateOption({
            name = "rm_damage_multiplier",
            helptext = "Damage to ragdolls will be scaled by this value",
            default = 1,
            flags = FlagsSave,
            GUIMin = 0,
            GUIMax = 3,
        }),
        PhysicsMultiplier = CreateOption({
            name = "rm_damage_phys_multiplier",
            helptext = "Physics damage to ragdolls will be scaled by this value",
            default = 0.5,
            flags = FlagsSave,
            min = 0,
            GUIMax = 1,
        }),
        MinPhysicsDamage = CreateOption({
            name = "rm_damage_phys_min",
            helptext = "Ragdolls won't take damage if the amount is less than this",
            default = 70,
            flags = FlagsSave,
            min = 0,
            GUIMax = 200,
        }),
        ForceMultiplier = CreateOption({
            name = "rm_damage_force_multiplier",
            helptext = "Damage physics force to ragdolls will be scaled by this value",
            default = 1,
            flags = FlagsSave,
            GUIMin = 0,
            GUIMax = 10,
        }),
    },
    Effects = {
        Sounds = CreateOption({
            name = "rm_effect_sound",
            helptext = "Enable sounds from ragdolls",
            default = true,
            flags = FlagsSave,
        }),
        RagSounds = CreateOption({
            name = "rm_effect_sound_rag",
            helptext = "Enable sounds from ragging",
            default = true,
            flags = FlagsSave,
        }),
        PainSounds = CreateOption({
            name = "rm_effect_sound_pain",
            helptext = "Enable sounds from pain",
            default = true,
            flags = FlagsSave,
        }),
        GrabSounds = CreateOption({
            name = "rm_effect_sound_grab",
            helptext = "Enable sounds from grabbing",
            default = true,
            flags = FlagsSave,
        }),
        PainOnlyDamage = CreateOption({
            name = "rm_effect_sound_pain_damage",
            helptext = "Play sounds only when taking damage",
            default = true,
            flags = FlagsSave,
        }),
        VoiceType = CreateOption({
            name = "rm_effect_voice_type",
            helptext = "Ragdoll voice type",
            default = 0,
            choices = {"auto", "male", "female", "combine"},
            shouldsave = true,
            userinfo = true,
            client = true,
        }),
        Blood = CreateOption({
            name = "rm_effect_blood",
            helptext = "Enable blood decals on impact",
            default = true,
            flags = FlagsSave,
        }),
        BloodThreshold = CreateOption({
            name = "rm_effect_blood_threshold",
            helptext = "How hard ragdolls need to hit walls to add blood decals",
            default = 500,
            flags = FlagsSave,
            min = 0,
            GUIMin = 400,
            GUIMax = 2000
        }),
    },
    Ragdolling = {
        GetUpDelay = CreateOption({
            name = "rm_getup_delay",
            helptext = "How long should players wait before they can get up",
            default = 0.5,
            flags = FlagsSaveSync,
            min = 0,
            GUIMin = 0.2,
            GUIMax = 3
        }),
        ShowDelay = CreateOption({
            name = "rm_show_getup_delay",
            helptext = "Show wait timer when ragdolling",
            default = true,
            shouldsave = true,
            userinfo = false,
            client = true,
        }),
        ShowControls = CreateOption({
            name = "rm_show_controls",
            helptext = "Show control help when ragdolling",
            default = true,
            shouldsave = true,
            userinfo = false,
            client = true,
        }),
        ShowHealth = CreateOption({
            name = "rm_show_health",
            helptext = "Show player health when ragdolling",
            default = true,
            shouldsave = true,
            userinfo = false,
            client = true,
        }),
    },
    Rolling = {
        Enabled = CreateOption({
            name = "rm_movement_roll",
            helptext = "Allow rolling",
            default = true,
            flags = FlagsSave,
        }),
        Force = CreateOption({
            name = "rm_movement_roll_force",
            helptext = "How much torque is applied when rolling",
            default = 300,
            flags = FlagsSave,
            min = 0,
            GUIMax = 1000
        }),
    },
    Flying = {
        Enabled = CreateOption({
            name = "rm_movement_fly",
            helptext = "Allow flying",
            default = true,
            flags = FlagsSave,
        }),
        AdminOverride = CreateOption({
            name = "rm_movement_fly_admin",
            helptext = "Always allow admins to fly",
            default = false,
            flags = FlagsSave,
        }),
        Force = CreateOption({
            name = "rm_movement_fly_force",
            helptext = "How much force is applied when flying",
            default = 3000,
            flags = FlagsSave,
            GUIMin = 0,
            GUIMax = 5000
        }),
    },
    Limbs = {
        Enabled = CreateOption({
            name = "rm_limbs",
            helptext = "Allow limb control",
            default = true,
            flags = FlagsSave,
        }),
        Force = CreateOption({
            name = "rm_limbs_force",
            helptext = "How fast the ragdolls reach with their limbs",
            default = 110,
            flags = FlagsSave,
            min = 0,
            GUIMin = 50,
            GUIMax = 1000,
        }),
        ForceLimit = CreateOption({
            name = "rm_limbs_forcelimit",
            helptext = "How easily ragdolls will release their grabbed item",
            default = 10000,
            flags = FlagsSave,
            min = 0,
            GUIMax = 20000,
        }),
        Grabbing = CreateOption({
            name = "rm_grabbing",
            helptext = "Allow grabbing with limbs",
            default = true,
            flags = FlagsSave,
        }),
        ReleaseOnDeath = CreateOption({
            name = "rm_grabbing_release_on_death",
            helptext = "Release grabbed items on death",
            default = true,
            flags = FlagsSave,
        }),
    }
}