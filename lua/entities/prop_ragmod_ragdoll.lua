----------------------------------------------------------
-- Title: prop_ragmod_ragdoll
-- Author: n-gon
-- Description:
----- Ragmod ragdoll fake scripted entity class
-- Notes:
----- Defines a custom entity class for ragmod ragdolls
----- Class is only recognized by the server, clients see the entity
----- as a prop_ragdoll
-----
----- Fake SENT docs:
----- https://wiki.facepunch.com/gmod/Fake_Scripted_Entity_Creation
----------------------------------------------------------
---------------------
-- Fake SENT Setup --
---------------------
ENT.Type = "anim"
local ENT = {}
local BaseClass = FindMetaTable("Entity")
local BaseClassName = "prop_ragdoll"
local ClassName = "prop_ragmod_ragdoll"

if CLIENT then
    killicon.AddAlias(ClassName, BaseClassName)
end

if SERVER then
    util.AddNetworkString("ragmod::cl::request_ragdoll_type")
    util.AddNetworkString("ragmod::cl::request_ragdoll_owner")
    util.AddNetworkString("ragmod::cl::request_ragdoll_possessor")
    util.AddNetworkString("ragmod::sv::confirm_ragdoll_type")
    util.AddNetworkString("ragmod::sv::confirm_ragdoll_owner")
    util.AddNetworkString("ragmod::sv::confirm_ragdoll_possessor")
end

AddCSLuaFile()
------------------
-- File locals  --
------------------
-- true if the lua environment is shutting down
local LuaShuttingDown = false

-- Model names to determine sound type
local FemaleModelStrings = {"alyx", "mossman", "female", "chell"}

local CombineModelStrings = {"combine", "police", "stripped"}

-- Default sounds for different sound types
local Sounds = {
    ["male"] = {
        Pain = {"vo/npc/male01/pain01.wav", "vo/npc/male01/pain02.wav", "vo/npc/male01/pain03.wav", "vo/npc/male01/pain04.wav", "vo/npc/male01/pain05.wav", "vo/npc/male01/pain06.wav", "vo/npc/male01/pain07.wav", "vo/npc/male01/pain08.wav", "vo/npc/male01/pain09.wav",},
        Fall = {"vo/npc/male01/help01.wav", "vo/npc/male01/watchout.wav", "vo/npc/male01/uhoh.wav",}
    },
    ["female"] = {
        Pain = {"vo/npc/female01/pain01.wav", "vo/npc/female01/pain02.wav", "vo/npc/female01/pain03.wav", "vo/npc/female01/pain04.wav", "vo/npc/female01/pain05.wav", "vo/npc/female01/pain06.wav", "vo/npc/female01/pain07.wav", "vo/npc/female01/pain08.wav", "vo/npc/female01/pain09.wav",},
        Fall = {"vo/npc/female01/help01.wav", "vo/npc/female01/watchout.wav", "vo/npc/female01/uhoh.wav",},
    },
    ["combine"] = {
        Pain = {"npc/combine_soldier/pain1.wav", "npc/combine_soldier/pain2.wav", "npc/combine_soldier/pain3.wav",},
        Fall = {"npc/combine_soldier/vo/inbound.wav", "npc/combine_soldier/vo/coverhurt.wav",}
    }
}

local BoneHitGroups = {
    ["ValveBiped.Bip01_Pelvis"] = HITGROUP_STOMACH,
    ["ValveBiped.Bip01_Spine"] = HITGROUP_STOMACH,
    ["ValveBiped.Bip01_Spine1"] = HITGROUP_CHEST,
    ["ValveBiped.Bip01_Spine2"] = HITGROUP_CHEST,
    ["ValveBiped.Bip01_Spine3"] = HITGROUP_CHEST,
    ["ValveBiped.Bip01_Spine4"] = HITGROUP_CHEST,
    ["ValveBiped.Bip01_L_Clavicle"] = HITGROUP_CHEST,
    ["ValveBiped.Bip01_L_UpperArm"] = HITGROUP_LEFTARM,
    ["ValveBiped.Bip01_L_Forearm"] = HITGROUP_LEFTARM,
    ["ValveBiped.Bip01_L_Hand"] = HITGROUP_LEFTARM,
    ["ValveBiped.Bip01_R_Clavicle"] = HITGROUP_CHEST,
    ["ValveBiped.Bip01_R_UpperArm"] = HITGROUP_RIGHTARM,
    ["ValveBiped.Bip01_R_Forearm"] = HITGROUP_RIGHTARM,
    ["ValveBiped.Bip01_R_Hand"] = HITGROUP_RIGHTARM,
    ["ValveBiped.Bip01_Neck1"] = HITGROUP_HEAD,
    ["ValveBiped.Bip01_Head1"] = HITGROUP_HEAD,
    ["ValveBiped.Bip01_L_Thigh"] = HITGROUP_LEFTLEG,
    ["ValveBiped.Bip01_L_Calf"] = HITGROUP_LEFTLEG,
    ["ValveBiped.Bip01_L_Foot"] = HITGROUP_LEFTLEG,
    ["ValveBiped.Bip01_L_Toe0"] = HITGROUP_LEFTLEG,
    ["ValveBiped.Bip01_R_Thigh"] = HITGROUP_RIGHTLEG,
    ["ValveBiped.Bip01_R_Calf"] = HITGROUP_RIGHTLEG,
    ["ValveBiped.Bip01_R_Foot"] = HITGROUP_RIGHTLEG,
    ["ValveBiped.Bip01_R_Toe0"] = HITGROUP_RIGHTLEG
}

local HitGroupDamage = {
    [HITGROUP_STOMACH] = 1.0,
    [HITGROUP_CHEST] = 1.0,
    [HITGROUP_RIGHTARM] = 0.8,
    [HITGROUP_LEFTARM] = 0.8,
    [HITGROUP_RIGHTLEG] = 0.8,
    [HITGROUP_LEFTLEG] = 0.8,
    [HITGROUP_HEAD] = 2,
}

-- Gets the current possessing player.
function ENT:GetPossessor()
    return self:GetNWEntity("ragmod_Possessor", NULL)
end

-- Gets the owner (origin) player of this ragdoll.
function ENT:GetOwningPlayer()
    return self:GetNWEntity("ragmod_Owner", NULL)
end

-- Plays a fall sound if allowed according to voice type
function ENT:PlayRagSound()
    local PlaySound = RagModOptions.Effects.Sounds()
    local RagSounds = RagModOptions.Effects.RagSounds()
    if not PlaySound or not RagSounds then return end
    if not self.Ragmod_VoiceType or not Sounds[self.Ragmod_VoiceType] then return end
    local soundTable = Sounds[self.Ragmod_VoiceType].Fall
    if not soundTable then return end
    if hook.Run("RM_CanPlaySound", self, "ragdoll") == false then return end
    local randSound = soundTable[math.random(1, #soundTable)]
    self:EmitSound(randSound)
end

-- Plays a pain sound if allowed according to voice type
function ENT:PlayPainSound()
    local PlaySound = RagModOptions.Effects.Sounds()
    local PainSounds = RagModOptions.Effects.PainSounds()
    if not PlaySound or not PainSounds then return end
    if (CurTime() - self.Ragmod_LastPainSound) < 0.5 then return end
    if not self.Ragmod_VoiceType or not Sounds[self.Ragmod_VoiceType] then return end
    local soundTable = Sounds[self.Ragmod_VoiceType].Pain
    if not soundTable then return end
    if hook.Run("RM_CanPlaySound", self, "pain") == false then return end
    self:EmitSound(soundTable[math.random(1, #soundTable)])
    self.Ragmod_LastPainSound = CurTime()
end

-- Assigns a voice type according to the player model
function ENT:AssignVoice(owner)
    local prefVoiceType = RagModOptions.Effects.VoiceType:GetPlayerValue(owner)

    if prefVoiceType ~= "auto" then
        self.Ragmod_VoiceType = prefVoiceType

        return
    end

    -- Automatic voice type:
    local mdlName = self:GetModel()

    for k, v in ipairs(FemaleModelStrings) do
        if string.find(mdlName, v) then
            self.Ragmod_VoiceType = "female"

            return
        end
    end

    for k, v in ipairs(CombineModelStrings) do
        if string.find(mdlName, v) then
            self.Ragmod_VoiceType = "combine"

            return
        end
    end

    self.Ragmod_VoiceType = "male"
end

-- If both the owner and the possessor are ready, run a hook to notify other addons
local function TryRunFullInitHook(ragdoll)
    local owner = ragdoll:GetOwningPlayer()
    local possessor = ragdoll:GetPossessor()

    if not ragdoll.RM_Ready and IsValid(owner) and IsValid(possessor) then
        rmutil:DebugPrint(string.format("Ragdoll %d: Running full init hook", ragdoll:EntIndex()))
        hook.Run("RM_RagdollReady", ragdoll, owner, possessor)
        ragdoll.RM_Ready = true
    end
end

--  Called on the server after the ragdoll owner is assigned
--  Called on all clients after the owner is received
--  Sets the color, skin and bodygroups of this ragdoll to match the owner
function ENT:InitializeWithOwner()
    local owner = self:GetOwningPlayer()

    -- Could happend if owner immediately changes
    if not IsValid(owner) then
        self.Ragmod_OwnerInitialized = true
        hook.Run("RM_OwnerInitialized", self, NULL)

        return
    end

    -- Set color function used by the ragdoll's material
    -- The color is cached so that the owner changing their color doesn't change the ragdoll
    local color = owner:GetPlayerColor()
    self.GetPlayerColor = function() return color end
    -- Copy skin
    self:SetSkin(owner:GetSkin())

    -- Copy bodygroups from the owner
    for k, v in pairs(owner:GetBodyGroups()) do
        self:SetBodygroup(v.id, owner:GetBodygroup(v.id))
    end

    self:AssignVoice(owner)
    self.Ragmod_OwnerInitialized = true
    hook.Run("RM_OwnerInitialized", self, owner)
end

-- Called on the server when the ragdoll is created but not yet spawned.
-- Owner is not valid on the server
-- Called on the client when it receives the networked entity.
-- Owner might already be valid on the client if the server has
-- spawned the ragdoll and assigned an owner
function ENT:Initialize()
    self.Ragmod_OwnerInitialized = false
    rmutil:DebugPrint(string.format("Ragdoll %d: Initializing...", self:EntIndex()))

    if CLIENT then
        self:SetupRagdollBones()
        hook.Run("RM_RagdollSpawned", self)
        local owner = self:GetOwningPlayer()

        if IsValid(owner) then
            self:InitializeWithOwner()
            TryRunFullInitHook(self)
        else
            rmutil:DebugPrint(string.format("Ragdoll %d: Owner was not valid, waiting to receive...", self:EntIndex()))
            net.Start("ragmod::cl::request_ragdoll_owner", false)
            net.WriteEntity(self)
            net.SendToServer()
        end

        local possessor = self:GetPossessor()

        if IsValid(possessor) then
            hook.Run("RM_RagdollPossessed", self, possessor)
            possessor:SetNWEntity("ragmod_Possessed", self)

            if possessor == LocalPlayer() then
                hook.Run("ragmod::local_possessed", self)
            end

            TryRunFullInitHook(self)
        else
            rmutil:DebugPrint(string.format("Ragdoll %d: Possessor was not valid, waiting to receive...", self:EntIndex()))
            net.Start("ragmod::cl::request_ragdoll_possessor")
            net.WriteEntity(self)
            net.SendToServer()
        end
    end

    self.Ragmod_Initialized = true
end

-- Disable context menu driving
function ENT:CanProperty(ply, prop)
    return prop ~= "drive"
end

function ENT:FindClosestHitGroup(pos)
    local physObjId, _ = self:FindClosestPhysBone(pos)
    if not physObjId then return HITGROUP_GENERIC end
    local bone = self:TranslatePhysBoneToBone(physObjId)
    local hitgroup = BoneHitGroups[self:GetBoneName(bone)]
    if not hitgroup then return HITGROUP_GENERIC end -- Unknown bone

    return hitgroup, bone
end

function ENT:ProcessDamage(dmginfo)
    local TakePhysDmg = RagModOptions.Damage.Physics()
    local TakePvpDmg = RagModOptions.Damage.PvP()
    local DamageMultiplier = RagModOptions.Damage.Multiplier()
    local PhysicsDamageMultiplier = RagModOptions.Damage.PhysicsMultiplier()
    local MinPhysicsDamage = RagModOptions.Damage.MinPhysicsDamage()
    local ScaleDamageBodypart = RagModOptions.Damage.Bodypart()
    local PainOnlyDamage = RagModOptions.Effects.PainOnlyDamage()
    local DamageForceMultipler = RagModOptions.Damage.ForceMultiplier()
    local GodMode = RagModOptions.Damage.GodMode()
    local RocketJump = RagModOptions.Trigger.RocketJump()
    local ply = self:GetPossessor()
    local isPlyValid = IsValid(ply)
    local extraDmginfo = {}
    -- Physics force scaling, used later in this function
    dmginfo:SetDamageForce(DamageForceMultipler * dmginfo:GetDamageForce() / 100)

    -- Play pain sounds on any damage if the option is set
    if not PainOnlyDamage and isPlyValid and ply:Alive() then
        self:PlayPainSound()
    end

    -- Find hitgroup and bone info
    local hitgroup, bone = self:FindClosestHitGroup(dmginfo:GetDamagePosition())
    extraDmginfo.GetHitGroup = function() return hitgroup end
    extraDmginfo.GetHitBone = function() return bone end

    if isPlyValid then
        ply:SetLastHitGroup(hitgroup)
    end

    -- Pvp damage scaling
    local attacker = dmginfo:GetAttacker()

    if IsValid(attacker) and (attacker:IsPlayer() or attacker:IsNPC()) then
        if not TakePvpDmg then
            dmginfo:ScaleDamage(0)
        elseif isPlyValid and dmginfo:IsBulletDamage() then
            -- Only called for bullet damage
            if hook.Run("ScalePlayerDamage", ply, hitgroup, dmginfo) == true then
                -- Returning true should stop all damage
                dmginfo:ScaleDamage(0)
            end
        end
    end

    -- Do bodypart scaling
    if ScaleDamageBodypart then
        local dmgScale = HitGroupDamage[hitgroup]

        if dmgScale then
            dmginfo:ScaleDamage(dmgScale)
        end
    end

    -- Launch the ragdoll if the damage wasn't from physics collisions
    if not dmginfo:IsDamageType(DMG_CRUSH) then
        self:AddVelocity(dmginfo:GetDamageForce())
        -- Add blood particles
        if RagModOptions.Effects.Blood() then
            local effectdata = EffectData()
            effectdata:SetOrigin(dmginfo:GetDamagePosition())
            effectdata:SetNormal(dmginfo:GetDamageForce():GetNormalized())
            util.Effect("BloodImpact", effectdata)
        end
    end

    if GodMode then
        dmginfo:ScaleDamage(0)
    end

    if dmginfo:IsExplosionDamage() and RocketJump then
        dmginfo:ScaleDamage(0)
    end

    -- Crush damage needs to be reduced
    if dmginfo:IsDamageType(DMG_CRUSH) then
        if not TakePhysDmg then
            dmginfo:ScaleDamage(0)
        elseif dmginfo:GetDamage() < MinPhysicsDamage then
            dmginfo:ScaleDamage(0)
        else
            dmginfo:ScaleDamage(PhysicsDamageMultiplier * 0.1)
        end
    end

    dmginfo:ScaleDamage(DamageMultiplier)
    -- Notify other addons of the damage we took
    hook.Run("RM_RagdollTakeDamage", self, dmginfo, extraDmginfo)
    if not isPlyValid then return end

    -- Allow other addons to give immunity to tamage
    if hook.Run("PlayerShouldTakeDamage", ply, dmginfo:GetAttacker()) == false then
        dmginfo:ScaleDamage(0)

        return
    end

    if ply:Alive() then
        -- Play pain sounds when the setting is set to damage only
        if PainOnlyDamage and dmginfo:GetDamage() > 0 then
            self:PlayPainSound()
        end

        -- Have the player take the damage
        ragmod:PropagateDamage(ply, dmginfo)
    end
end

local function PlayGrabSound(ent, grabbed)
    if not RagModOptions.Effects.Sounds() then return end
    if not RagModOptions.Effects.GrabSounds() then return end
    if not IsValid(ent) then return end
    local pitch = grabbed and math.Rand(110, 120) or math.Rand(90, 100)
    ent:EmitSound("garrysmod/balloon_pop_cute.wav", 75, pitch, 1, CHAN_ITEM, 0, 0)
end

local function FindClosestPhysObj(ent, pos)
    local shortest = nil
    local closestPhysObj = nil
    local closestPhysObjId = nil

    for i = 0, ent:GetPhysicsObjectCount() - 1 do
        local physObj = ent:GetPhysicsObjectNum(i)
        local physPos = physObj:GetPos()
        local dist = (pos - physPos):LengthSqr()

        if not shortest or dist < shortest then
            shortest = dist
            closestPhysObj = physObj
            closestPhysObjId = i
        end
    end

    return closestPhysObjId, closestPhysObj
end

-- Finds the closest entity matching the filter
-- Direction bias is used to filter out objects in the opposite direction
-- returns: entity, physicsObjectId, physicsObject
-- or nothing if nothing was found
local function FindClosestEntity(pos, filter, allowWorld, directionBias)
    local radius = 5

    -- TODO Adjustable radius
    local trace = {
        start = pos + directionBias * radius / 2,
        endpos = pos + directionBias * radius / 2,
        mins = Vector(-radius / 2, -radius / 2, -radius / 2),
        maxs = Vector(radius / 2, radius / 2, radius / 2),
        filter = filter,
        ignoreworld = not allowWorld
    }

    local res = util.TraceHull(trace)
    if not res or not res.Hit or not res.Entity then return end -- Couldn't find anything

    return res.Entity, res.PhysicsBone, res.Entity:GetPhysicsObjectNum(res.PhysicsBone)
end

function ENT:GetRagdollEyes()
    -- Prefer the eye attachment in the model
    if self.Ragmod_EyeAttachment and self.Ragmod_EyeAttachment > 0 then
        local eyes = self:GetAttachment(self.Ragmod_EyeAttachment)

        return eyes.Pos, eyes.Ang
    end

    -- Head bone is the second best option
    if self.Ragmod_Bones and self.Ragmod_Bones.Head then
        local boneMatrix = self:GetBoneMatrix(self.Ragmod_Bones.Head)
        -- boneMatrix:GetAngles() would be better, but it's currently bugged
        -- eyeangles are not set on ragdolls

        return boneMatrix:GetTranslation(), self:EyeAngles()
    end
    -- Worst case scenario: can't find proper eye angles, the view will end up the ragdolls torso

    return self:EyePos(), self:EyeAngles()
end

function ENT:GetPossessorView()
    local ply = self:GetPossessor()
    if not IsValid(ply) then return Vector(0, 0, 0), Angle(0, 0, 0) end

    -- Allow addons to block our camera
    if hook.Run("RM_CanChangeCamera", ply) == false then
        -- Allow addons to provide their own camera
        local hookPos, hookAngle = hook.Run("RM_CustomRagdollCamera", self, ply)
        if hookPos and hookAngle then return hookPos, hookAngle end

        return ply:EyePos(), ply:EyeAngles()
    end

    local viewType, lockedCam = ragmod:GetPlayerViewType(ply)

    -- Firstperson
    if viewType == "firstperson" or viewType == "firstperson_pos_only" then
        -- this almost exactly what the client does in GetRagEyes() in cl_ragmod.lua
        -- Todo: share the code
        local eyePos, eyeAngle = self:GetRagdollEyes()

        if viewType == "firstperson" then
            if lockedCam then return eyePos, eyeAngle end
            -- Semi-free camera

            return eyePos, ply.RagmodInputState.EyeAngles
        else
            --pos-only firstperson
            return eyePos, ply:EyeAngles()
        end
    end

    -- Thirdperson, and fallback
    -- Custom third person trace
    local distance = 100
    local radius = 3
    local viewOrigin = self:GetPos() + Vector(0, 0, 20)

    local trace = {
        start = viewOrigin,
        endpos = viewOrigin - ply:GetAimVector() * distance,
        filter = {self},
        maxs = Vector(radius, radius, radius),
        mins = Vector(-radius, -radius, -radius)
    }

    local res = util.TraceHull(trace)

    return res.HitPos, ply:EyeAngles()
end

function ENT:SetVelocity(velocity)
    local bones = self:GetPhysicsObjectCount()

    for i = 0, bones - 1 do
        local bone = self:GetPhysicsObjectNum(i)

        if bone:IsValid() then
            bone:SetVelocity(velocity)
        end
    end
end

function ENT:AddVelocity(velocity)
    local bones = self:GetPhysicsObjectCount()

    for i = 0, bones - 1 do
        local bone = self:GetPhysicsObjectNum(i)

        if bone:IsValid() then
            bone:AddVelocity(velocity)
        end
    end
end

-- Returns the first exact name match in the given name or table of names (ValveBiped only)
local function FindFirstPhysBone(ent, names)
    if not istable(names) then
        names = {names}
    end

    local bone = nil
    local physBoneId = -1
    local physObj = NULL

    for _, name in ipairs(names) do
        bone = ent:LookupBone("ValveBiped.Bip01_" .. name)

        if bone then
            physBoneId = ent:TranslateBoneToPhysBone(bone)

            if physBoneId ~= -1 then
                physObj = ent:GetPhysicsObjectNum(physBoneId)
                if physObj and physObj:IsValid() then break end
            end
        end
    end

    if not bone or physBoneId == -1 or not physObj or not physObj:IsValid() then return -1 end

    return physBoneId
end

-- Used in the ragdoll initialization.
-- Stores info about the ragdolls bone setup to save performance in tick()
-- Copies owners bone velocites to the ragdoll
function ENT:SetupRagdollBones()
    -- Contains physObj indices for used physics objects
    self.Ragmod_PhysBones = {
        Head1 = FindFirstPhysBone(self, "Head1"),
        -- Some models are missing the head bone, so the neck or the spine is used as a fallback
        FlyBone = FindFirstPhysBone(self, {"Head1", "Neck1", "Spine4", "Spine3", "Spine2"}),
        Spine1 = FindFirstPhysBone(self, "Spine1"),
        Spine2 = FindFirstPhysBone(self, "Spine1"),
        Spine = FindFirstPhysBone(self, "Spine"),
        Pelvis = FindFirstPhysBone(self, "Pelvis"),
        R_Hand = FindFirstPhysBone(self, "R_Hand"),
        L_Hand = FindFirstPhysBone(self, "L_Hand"),
    }

    -- Contains bone indices for used bones
    self.Ragmod_Bones = {
        Head = rmutil:SearchBone(self, "Head")
    }

    local FlyBone = self:GetPhysicsObjectNum(self.Ragmod_PhysBones.FlyBone)
    local Spine1 = self:GetPhysicsObjectNum(self.Ragmod_PhysBones.Spine1)
    local Spine = self:GetPhysicsObjectNum(self.Ragmod_PhysBones.Spine)
    local Pelvis = self:GetPhysicsObjectNum(self.Ragmod_PhysBones.Pelvis)
    local R_Hand = self:GetPhysicsObjectNum(self.Ragmod_PhysBones.R_Hand)
    local L_Hand = self:GetPhysicsObjectNum(self.Ragmod_PhysBones.L_Hand)
    -- Rolling requires a valid torso bone setup
    self.Ragmod_CanRoll = IsValid(Pelvis) and IsValid(Spine1) and IsValid(Spine)
    self.Ragmod_CanFly = IsValid(FlyBone)
    -- TODO: Let player choose which attachment to use.
    -- Also, save properties per model
    self.Ragmod_EyeAttachment = self:LookupAttachment("eyes")

    self.Ragmod_Limbs = {
        ArmRight = nil,
        ArmLeft = nil
    }

    if IsValid(R_Hand) then
        self.Ragmod_Limbs.ArmRight = {
            PhysObjId = self.Ragmod_PhysBones.R_Hand,
            Grab = nil,
            HookName = "arm_right"
        }
    end

    if IsValid(L_Hand) then
        self.Ragmod_Limbs.ArmLeft = {
            PhysObjId = self.Ragmod_PhysBones.L_Hand,
            Grab = nil,
            HookName = "arm_left"
        }
    end
end

-- Copies angles and velocities from owner bones to the ragdoll
function ENT:CopyOwnerPhysics()
    local owner = self:GetOwningPlayer()
    if not IsValid(owner) then return end

    for i = 0, self:GetPhysicsObjectCount() - 1 do
        local bone = self:GetPhysicsObjectNum(i)

        if bone:IsValid() then
            -- This gets the position and angles of the entity bone corresponding to the above physics bone
            local bonepos = owner:GetBonePosition(self:TranslatePhysBoneToBone(i))
            local bonematrix = owner:GetBoneMatrix(self:TranslatePhysBoneToBone(i))
            local boneang = bonematrix:GetAngles()
            -- All we need to do is set the bones position and angle
            bone:SetPos(bonepos)
            bone:SetAngles(boneang)
        end
    end

    local velocity = owner:GetVelocity()

    if owner:InVehicle() then
        local vehicle = owner:GetVehicle()

        if IsValid(vehicle) then
            velocity = vehicle:GetVelocity()
            local physObj = vehicle:GetPhysicsObject()

            if IsValid(physObj) and physObj:IsValid() then
                velocity = physObj:GetVelocityAtPoint(owner:GetPos())
            end
        end
    end

    self:SetVelocity(velocity)
end

function ENT:FindClosestPhysBone(pos)
    return FindClosestPhysObj(self, pos)
end

local function OnShutDown()
    LuaShuttingDown = true
end

hook.Add("ShutDown", "ragmod_ragdoll_ShutDown", OnShutDown)

--------------------
-- Server methods --
--------------------
if SERVER then
    --[[
        This is called on the ragdoll a player has just possessed
    ]]
    function ENT:Possess(ply)
        self:SetNWEntity("ragmod_Possessor", ply)
        hook.Run("RM_RagdollPossessed", self, ply)
        TryRunFullInitHook(self)
    end

    --[[
        This is called on the ragdoll a player has just unpossessed
        Handles removing the ref to the player from this ragdoll.
        Removes the ragdoll if the player got up from ragdolling
    ]]
    function ENT:UnPossess()
        local ply = self:GetPossessor()
        if not IsValid(ply) then return end
        local playerRagdoll = ply:GetNWEntity("ragmod_Possessed", NULL)
        net.Start("ragmod::sv::local_unpossessed", false)
        net.WriteEntity(self)
        net.Send(ply)

        if IsValid(playerRagdoll) and playerRagdoll ~= self then
            -- Our possessor's ragdoll somehow isn't us
            self:SetNWEntity("ragmod_Possessor", NULL)

            return
        end

        if RagModOptions.Limbs.ReleaseOnDeath() then
            self:ReleaseAllGrabbed()
        end

        self:SetNWEntity("ragmod_Possessor", NULL) -- Remove ref to possessor from the ragdoll
    end

    function ENT:ReleaseAllGrabbed()
        for _, limb in pairs(self.Ragmod_Limbs) do
            if limb.Grab and IsValid(limb.Grab.Weld) then
                limb.Grab.Weld:Remove()
                limb.Grab = nil
            end
        end
    end

    -- Tries to grab anything near the given limb. Updates the limb table with the constraint info.
    -- Returns true if successfully grabbed something
    function ENT:GrabWithLimb(limb)
        local limbBone = self:GetPhysicsObjectNum(limb.PhysObjId)
        local pos = limbBone:GetPos()
        local prop, physObjId, physObj = FindClosestEntity(pos, self, true, limbBone:GetVelocity():GetNormalized())
        if not prop or ((not IsValid(prop) or not IsValid(physObj)) and not prop:IsWorld()) then return false end
        if hook.Run("RM_CanGrab", self, limb.HookName, prop, physObjId) == false then return false end
        local forcelimit = RagModOptions.Limbs.ForceLimit()
        local weld = constraint.Weld(self, prop, limb.PhysObjId, physObjId, forcelimit, false, false)
        if not IsValid(weld) then return false end

        -- Success, update Grab table
        limb.Grab = {
            Weld = weld,
            Entity = prop,
            EntityPhysObjId = physObjId,
        }

        -- ent:EmitSound doesn't work on constraint entities
        PlayGrabSound(self, true)
        rmutil:DebugPrint(string.format("Ragdoll %d: grabbed %s with limb %d", self:EntIndex(), tostring(prop), limb.PhysObjId))

        if RagModOptions.Debug() then
            weld:CallOnRemove("ragmod_OnWeldRemoved", function(ent)
                rmutil:DebugPrint(string.format("Ragdoll %d: released with limb %d", self:EntIndex(), limb.PhysObjId))
                PlayGrabSound(self, false)
            end)
        else
            weld:CallOnRemove("ragmod_OnWeldRemoved", function(ent)
                PlayGrabSound(self, false)
            end)
        end

        return true
    end

    -- Should be called every tick on any limb that needs to be able to grab.
    -- Set input to whether ragdoll should try to grab with the limb
    function ENT:TickGrab(limb, input)
        local isGrabbingAllowed = RagModOptions.Limbs.Grabbing() and hook.Run("RM_CanMove", self, "grab") ~= false
        -- Check for the constraint, the entity, and also if the entity is the world
        -- (the world is not a valid entity for some reason)
        local isGrabValid = limb.Grab and IsValid(limb.Grab.Weld) and limb.Grab.Entity and (IsValid(limb.Grab.Entity) or limb.Grab.Entity:IsWorld())

        if input and isGrabbingAllowed then
            -- Reaching
            if isGrabValid then return end -- Is holding an entity, don't do anything
            -- No entity grabbed, try to grab
            self:GrabWithLimb(limb)
        else
            -- Not reaching
            if not limb.Grab or not IsValid(limb.Grab.Weld) then return end
            limb.Grab.Weld:Remove()
            limb.Grab = nil
        end
    end

    -- Called from the ragmod module. Used to process input and grabbing
    function ENT:Tick()
        local ply = self:GetPossessor()
        if not IsValid(ply) or not ply:Alive() then return end
        local inputState = ply.RagmodInputState

        if not inputState then
            -- Player hasn't initialized properly
            if RagModOptions.Debug() then
                ErrorNoHalt("Ragmod: Can't read input form player ", ply, " ")
            end

            return
        end

        -- Get movement permissions from convars
        local isFlightAllowed = (RagModOptions.Flying.Enabled() or RagModOptions.Flying.AdminOverride() and ply:IsAdmin()) and hook.Run("RM_CanMove", self, "fly") ~= false
        local isRollAllowed = RagModOptions.Rolling.Enabled() and hook.Run("RM_CanMove", self, "roll") ~= false
        local isLimbsAllowed = RagModOptions.Limbs.Enabled() and hook.Run("RM_CanMove", self, "limbs") ~= false
        -- Get input vectors used by multiple movement types
        local viewOrigin, viewAngles = self:GetPossessorView()
        local viewForward = viewAngles:Forward()
        local viewRight = viewAngles:Right()
        local viewUp = viewAngles:Up()
        local viewRightFlat = viewForward:Cross(Vector(0, 0, 1)) -- Ignores camera roll
        local viewForwardYawOnly = (viewForward * Vector(1, 1, 0)):GetNormalized()
        -- "cast" boolean inputs to number values and combine them into a vector
        -- Strafe is x, Forward acceleration is y
        local hasMoveInput = inputState[IN_FORWARD] or inputState[IN_BACK] or inputState[IN_MOVERIGHT] or inputState[IN_MOVELEFT]
        local moveValues = Vector((inputState[IN_MOVERIGHT] and 1 or 0) - (inputState[IN_MOVELEFT] and 1 or 0), (inputState[IN_FORWARD] and 1 or 0) - (inputState[IN_BACK] and 1 or 0), 0)
        local moveInput2d = ((moveValues.y * viewForwardYawOnly) + (moveValues.x * viewRightFlat)):GetNormalized()

        --------------
        -- Movement --
        --------------
        -- Flight --
        if isFlightAllowed and self.Ragmod_CanFly and inputState.Fly then
            local FlyBone = self:GetPhysicsObjectNum(self.Ragmod_PhysBones.FlyBone)
            local force = viewForward * RagModOptions.Flying.Force()
            FlyBone:ApplyForceCenter(force)
        end

        -- Roll --
        if isRollAllowed and self.Ragmod_CanRoll and hasMoveInput then
            local pelvis = self:GetPhysicsObjectNum(self.Ragmod_PhysBones.Pelvis)
            local spine = self:GetPhysicsObjectNum(self.Ragmod_PhysBones.Spine)
            local spine1 = self:GetPhysicsObjectNum(self.Ragmod_PhysBones.Spine1)
            local forcemul = RagModOptions.Rolling.Force()
            local torque = Vector(-moveInput2d.y, moveInput2d.x, 0) * (forcemul / 3)
            pelvis:ApplyTorqueCenter(torque)
            spine1:ApplyTorqueCenter(torque)
            spine:ApplyTorqueCenter(torque)
        end

        -- Limbs --
        if isLimbsAllowed and self.Ragmod_Limbs then
            -- Get a point to reach towards
            local endPos = viewOrigin + viewForward * 200

            local res = util.TraceLine({
                start = viewOrigin,
                endpos = endPos,
                filter = self,
            })

            local reachPoint = res.HitPos
            local limbForce = RagModOptions.Limbs.Force()

            for limbName, isReaching in pairs(inputState.Reach) do
                local limb = self.Ragmod_Limbs[limbName]
                if not limb then continue end
                if hook.Run("RM_CanReach", self, limb.HookName) == false then continue end
                local limbPhys = self:GetPhysicsObjectNum(limb.PhysObjId)
                if not IsValid(limbPhys) or not limbPhys:IsValid() then continue end
                local diff = reachPoint - limbPhys:GetPos()
                local reachDir = diff:GetNormalized()

                if isReaching then
                    limbPhys:ApplyForceCenter(reachDir * limbForce)
                end

                self:TickGrab(limb, isReaching)
            end
        end
    end

    function ENT:AddCollisionBlood(colData)
        if colData.HitSpeed:Length() < RagModOptions.Effects.BloodThreshold() then return end
        local pos = colData.HitPos
        local bloodCol = self:GetBloodColor()
        local decal = "Blood"

        if bloodCol == BLOOD_COLOR_RED then
            decal = "Antlion.Splat"
        elseif bloodCol == BLOOD_COLOR_YELLOW then
            decal = "YellowBlood"
        elseif bloodCol == BLOOD_COLOR_GREEN then
            decal = "Blood"
        elseif bloodCol == BLOOD_COLOR_MECH then
            decal = "Dark"
        elseif bloodCol == BLOOD_COLOR_ANTLION then
            decal = "YellowBlood"
        elseif bloodCol == BLOOD_COLOR_ZOMBIE then
            decal = "Blood"
        elseif bloodCol == BLOOD_COLOR_ANTLION_WORKER then
            decal = "YellowBlood"
        end

        util.Decal(decal, pos, pos + colData.HitNormal * 5, self)
        util.Decal(decal, pos + colData.HitNormal * 2, colData.PhysObject:GetPos(), colData.HitEntity)
    end

    local function LaunchDoor(doorPhys, colData)
        local launchMul = RagModOptions.DoorBreaching.LaunchPower()
        doorPhys:ApplyForceOffset(colData.OurOldVelocity:GetNormalized() * launchMul * doorPhys:GetMass(), colData.HitPos)
    end

    local function BreachDoor(door, colData)
        local model = door:GetModel()
        local position = door:GetPos()
        local angle = door:GetAngles()
        local material = door:GetMaterial()
        local skin = door:GetSkin()

        if not (model and position and angle) then
            -- Might be a brush door
            door:Fire("open", "", 0)

            return
        end

        local replacement = ents.Create("prop_physics")
        replacement:SetModel(model)
        replacement:SetPos(position)
        replacement:SetAngles(angle)

        if material then
            replacement:SetMaterial(material)
        end

        if skin then
            replacement:SetSkin(skin)
        end

        replacement:Spawn()
        replacement:Activate()
        local physObj = replacement:GetPhysicsObject()

        if not physObj then
            -- this was a mistake D:
            replacement:Remove()
            -- Just open the door i guess
            door:Fire("open", "", 0)

            return
        end

        sound.Play("Wood_Crate.Break", colData.HitPos, 60, 100)
        sound.Play("Wood_Furniture.Break", colData.HitPos, 60, 100)
        door:Remove()
        door.Ragmod_AlreadyBreached = true
        replacement.Ragmod_BreachedDoorReplacement = true
        LaunchDoor(physObj, colData)
    end

    -- Physics collision callback for this ragdoll
    -- Used for blood and door breaching
    function ENT:PhysicsCollide(colData)
        if RagModOptions.Effects.Blood() then
            self:AddCollisionBlood(colData)
        end

        local ent = colData.HitEntity
        if not IsValid(ent) then return end

        if ent:GetClass() == "prop_physics" and ent.Ragmod_BreachedDoorReplacement then
            LaunchDoor(ent:GetPhysicsObject(), colData)
        elseif ent:GetClass() == "func_door_rotating" or ent:GetClass() == "func_door" then
            if ent.Ragmod_AlreadyBreached then return end
            local physObj = ent:GetPhysicsObject()
            if not physObj then return end
            local volume = physObj:GetVolume()
            local requiredSpeed = volume * 0.01 + RagModOptions.DoorBreaching.Resistance()
            if colData.HitSpeed:Length() < requiredSpeed then return end
            BreachDoor(colData.HitEntity, colData)
        end
    end

    -- Required to be called before spawning the ragdoll
    function ENT:AssignOwner(owner)
        if not IsValid(owner) then
            if RagModOptions.Debug() then
                ErrorNoHaltWithStack("Ragdoll initialized with invalid owner!", owner)
            end

            return false
        end

        self:SetName("Ragdoll of " .. owner:GetName())
        self:SetPos(owner:GetPos())
        self:SetModel(owner:GetModel())
        self:SetAngles(owner:GetAngles())
        self:SetNWEntity("ragmod_Owner", owner)
        self:InitializeWithOwner()
        TryRunFullInitHook(self)

        return true
    end
end

--[[
    Footer section, required for fake SENTs
]]
--[[
    Spawn override, required to call Initialize hook
]]
local super_Spawn = BaseClass.Spawn

function ENT:Spawn(...)
    super_Spawn(self, ...)
    self.Ragmod_LastPainSound = 0
    self:SetupRagdollBones()
    self:CopyOwnerPhysics()
    self:AddCallback("PhysicsCollide", self.PhysicsCollide)
    hook.Run("RM_RagdollSpawned", self)
end

-- Remove callback
local function OnRemove(ragdoll)
    if LuaShuttingDown then return end -- Detect and skip if the level is unloading
    hook.Run("ragmod_RagdollRemoved", ragdoll, ragdoll:GetPossessor())
    ragdoll:UnPossess()
end

--[[
    String override
]]
local super_tostring = BaseClass.__tostring

function BaseClass:__tostring(...)
    if IsValid(self) and ragmod:IsRagmodRagdoll(self) then
        return string.format("Entity [%d][%s]", self:EntIndex(), string.format("%s (RagMod)", self:GetClass()))
    else
        return super_tostring(self, ...)
    end
end

--[[
    This loops through all the properties of this SENT table
]]
local SENT_values = {}

for k, v in pairs(ENT) do
    -- Functions
    if isfunction(v) then
        local super_Func = BaseClass[k]

        if isfunction(super_Func) then
            -- The function is re-defined in the base class, override it with out ENT function.
            BaseClass[k] = function(self, ...)
                -- We don't want to override the function for the actual base class
                if ragmod:IsRagmodRagdoll(self) then
                    return v(self, ...)
                else
                    return super_Func(self, ...)
                end
            end
        else -- The function was not defined in the base class, the function only exists for our SENT
            SENT_values[k] = v
        end
        -- Values
    else
        SENT_values[k] = v
    end
end

local function CopySENTValues(ent)
    for k, v in pairs(SENT_values) do
        ent[k] = v
    end
end

--[[
    Override ents.Create, SENT_values contains all hooks defined in this file
]]
local super_Create = ents.Create

function ents.Create(class, ...)
    if class == ClassName then
        local ent = super_Create(BaseClassName, ...)

        -- ent should now contain all the values and methods the base class contains
        if IsValid(ent) then
            -- Mark this as the custom version
            ent:SetNWBool("RM_Ragmod", true)
            ent:CallOnRemove("Ragmod_CallOnRemove", OnRemove)
            -- Insert our custom values and methods
            CopySENTValues(ent)
            ent:Initialize()
            hook.Run("RM_RagdollCreated", ent)
        end
        -- Use regular functionality for all other classes

        return ent
    else
        -- Default functionality
        return super_Create(class, ...)
    end
end

if SERVER then
    net.Receive("ragmod::cl::request_ragdoll_type", function(len, ply)
        if len == 0 then return end
        if not IsValid(ply) then return end
        local ragdoll = net.ReadEntity()
        if not IsValid(ragdoll) then return end
        if not ragmod:IsRagmodRagdoll(ragdoll) then return end
        -- Respond to the client
        rmutil:DebugPrint(string.format("Ragdoll %d: Confirming type to client %s", ragdoll:EntIndex(), ply:Nick()))
        local owner = ragdoll:GetOwningPlayer()
        net.Start("ragmod::sv::confirm_ragdoll_type", false)
        net.WriteEntity(ragdoll)

        if IsValid(owner) then
            -- Also write the owner
            net.WriteEntity(owner)
        end

        net.Send(ply)
    end)

    net.Receive("ragmod::cl::request_ragdoll_owner", function(len, ply)
        if len == 0 then return end
        if not IsValid(ply) then return end
        local ragdoll = net.ReadEntity()
        if not IsValid(ragdoll) then return end
        -- Respond to the client
        if not ragmod:IsRagmodRagdoll(ragdoll) then return end
        local owner = ragdoll:GetOwningPlayer()
        if not IsValid(owner) then return end
        rmutil:DebugPrint(string.format("Ragdoll %d: Confirming owner to client %s", ragdoll:EntIndex(), ply:Nick()))
        net.Start("ragmod::sv::confirm_ragdoll_owner", false)
        net.WriteEntity(ragdoll)
        net.WriteEntity(owner)
        net.Send(ply)
    end)

    net.Receive("ragmod::cl::request_ragdoll_possessor", function(len, ply)
        if len == 0 then return end
        if not IsValid(ply) then return end
        local ragdoll = net.ReadEntity()
        if not IsValid(ragdoll) then return end
        -- Respond to the client
        if not ragmod:IsRagmodRagdoll(ragdoll) then return end
        local possessor = ragdoll:GetPossessor()
        if not IsValid(possessor) then return end
        rmutil:DebugPrint(string.format("Ragdoll %d: Confirming possessor to client %s", ragdoll:EntIndex(), ply:Nick()))
        net.Start("ragmod::sv::confirm_ragdoll_possessor", false)
        net.WriteEntity(ragdoll)
        net.WriteEntity(possessor)
        net.Send(ply)
    end)
end

if CLIENT then
    -- Receive ragdoll type confirmation messages
    net.Receive("ragmod::sv::confirm_ragdoll_type", function(len, _)
        if len == 0 then return end
        local ragdoll = net.ReadEntity()
        if not IsValid(ragdoll) then return end
        rmutil:DebugPrint(string.format("Ragdoll %d: Received type confirmation", ragdoll:EntIndex()))
        local owner = net.ReadEntity()
        ragdoll:SetNWEntity("ragmod_Owner", owner)
        ragdoll:SetNWBool("RM_Ragmod", true)
        CopySENTValues(ragdoll)
        ragdoll:Initialize()
    end)

    -- Receive ragdoll owner confirmation messages
    net.Receive("ragmod::sv::confirm_ragdoll_owner", function(len, _)
        if len == 0 then return end
        local ragdoll = net.ReadEntity()
        local owner = net.ReadEntity()
        if not IsValid(ragdoll) or not IsValid(owner) then return end
        rmutil:DebugPrint(string.format("Ragdoll %d: Received owner confirmation: %s", ragdoll:EntIndex(), owner:Nick()))
        ragdoll:SetNWEntity("ragmod_Owner", owner)
        ragdoll:InitializeWithOwner()
        TryRunFullInitHook(ragdoll)
    end)

    -- Receive ragdoll possessor confirmation messages
    net.Receive("ragmod::sv::confirm_ragdoll_possessor", function(len, _)
        if len == 0 then return end
        local ragdoll = net.ReadEntity()
        local possessor = net.ReadEntity()
        if not IsValid(ragdoll) or not IsValid(possessor) then return end
        rmutil:DebugPrint(string.format("Ragdoll %d: Received possessor confirmation: %s", ragdoll:EntIndex(), possessor:Nick()))
        ragdoll:SetNWEntity("ragmod_Possessor", possessor)

        if possessor == LocalPlayer() then
            LocalPlayer():SetNWEntity("ragmod_Possessed", ragdoll)
            hook.Run("ragmod::local_possessed", ragdoll)
        end

        hook.Run("RM_RagdollPossessed", ragdoll, possessor)
        TryRunFullInitHook(ragdoll)
    end)

    local function NetworkEntityCreated(ent)
        -- Check if ragdoll
        if ent:GetClass() ~= BaseClassName then return end

        -- Check if ragmod ragdoll
        if ragmod:IsRagmodRagdoll(ent) then
            rmutil:DebugPrint(string.format("Ragdoll %d: Newly spawned ragdoll was from RagMod", ent:EntIndex()))
            CopySENTValues(ent)
            ent:Initialize()
        else
            -- If not ragmod ragdoll, add a callback
            rmutil:DebugPrint(string.format("Ragdoll %d: Newly spawned ragdoll could be from RagMod, requesting server to confim...", ent:EntIndex()))
            net.Start("ragmod::cl::request_ragdoll_type", false)
            net.WriteEntity(ent)
            net.SendToServer()
        end
    end

    hook.Add("NetworkEntityCreated", "ragmod_Client_CustomRagdollInitialization", NetworkEntityCreated)
end