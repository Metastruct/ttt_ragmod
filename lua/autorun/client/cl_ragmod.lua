----------------------------------------------------------
-- Title: cl_ragmod
-- Author: n-gon
-- Description:
----- Ragmod client autorun
----------------------------------------------------------
require("ragmod")
require("ragmod_utils")
-- Affects the frequency at which eye angles are sent to server
local EyeSendDelay = 1.0 / 60.0 * 5.0
-- local ragdoll properties
local LocalEyeAngle = Angle(0, 0, 0)
local WorldEyeAngle = Angle(0, 0, 0)
local RagdollDetectedAt = nil
local RagdollLostAt = nil
local IsAnimatingUnPossess = false
local IsAnimatingPossess = false
local MostRecentOrigin = Vector(0, 0, 0)
local MostRecentAngles = Angle(0, 0, 0)
local FirstRagFrame = false
local ModifiedAngle = nil
local ModifiedPos = nil
local UnmodifiedAngle = nil
local UnmodifiedPos = nil

local MaxFPInput = {
    pitchpos = 30,
    pitchneg = -30,
    yawpos = 30,
    yawneg = -30
}

local function HideHead(ragdoll)
    if not ragdoll.Ragmod_Bones or not ragdoll.Ragmod_Bones.Head then return end
    ragdoll:ManipulateBoneScale(ragdoll.Ragmod_Bones.Head, Vector(0, 0, 0))
end

local function RevealHead(ragdoll)
    if not ragdoll.Ragmod_Bones or not ragdoll.Ragmod_Bones.Head then return end
    ragdoll:ManipulateBoneScale(ragdoll.Ragmod_Bones.Head, Vector(1, 1, 1))
end

-- Allows the player to turn their head relative to the first person view of the ragdoll.
-- Server won't automatically know the players actual aim if this is used, so it needs to be sent manually 
local function ProcessFirstPersonInput(inAngles)
    local delta = inAngles
    delta.pitch = math.Clamp(delta.pitch, MaxFPInput.pitchneg, MaxFPInput.pitchpos)
    delta.yaw = math.Clamp(delta.yaw, MaxFPInput.yawneg, MaxFPInput.yawpos)
    LocalEyeAngle.pitch = math.Clamp(math.NormalizeAngle(LocalEyeAngle.pitch + delta.pitch), -90, 90)
    LocalEyeAngle.yaw = math.NormalizeAngle(LocalEyeAngle.yaw + delta.yaw)
    local maxdiff = 30

    if LocalEyeAngle.yaw > 90 then
        local target = 90
        local diff = LocalEyeAngle.yaw - target
        local alpha = diff / maxdiff
        MaxFPInput.yawpos = Lerp(alpha, 30, 0)
        local correctionStrength = math.ease.OutCubic(alpha)
        LocalEyeAngle.yaw = math.Approach(LocalEyeAngle.yaw, target, correctionStrength * 2)
    else
        MaxFPInput.yawpos = 30
    end

    if LocalEyeAngle.yaw < -90 then
        local target = -90
        local diff = target - LocalEyeAngle.yaw
        local alpha = diff / maxdiff
        MaxFPInput.yawneg = Lerp(alpha, -30, 0)
        local correctionStrength = math.ease.OutCubic(alpha)
        LocalEyeAngle.yaw = math.Approach(LocalEyeAngle.yaw, target, correctionStrength * 2)
    else
        MaxFPInput.yawneg = -30
    end
end

-- Server might override our view type, so this returns the actual type
local function GetActualViewType()
    if RagModOptions.View.ForcedView() then return RagModOptions.View.ForcedViewType() end

    return RagModOptions.View.ViewType()
end


local function CalcThirdPerson(ragdoll, inAngles, inFov)
    RevealHead(ragdoll)
    inAngles.roll = 0 -- Remove roll (Ragging from fall will cause view to tilt)
    -- Custom third person trace
    local distance = 100
    local radius = 3
    local viewOrigin = ragdoll:GetPos() + Vector(0, 0, 20)

    local trace = {
        start = viewOrigin,
        endpos = viewOrigin - inAngles:Forward() * distance,
        filter = {ragdoll},
        maxs = Vector(radius, radius, radius),
        mins = Vector(-radius, -radius, -radius)
    }

    local res = util.TraceHull(trace)

    return {
        origin = res.HitPos,
        angles = inAngles,
        fov = inFov,
        drawviewer = false,
    }
end

local function CalcFirstPersonView(ragdoll, viewType, inAngles, inFov)
    local ragEyePos, ragEyeAngles = ragdoll:GetRagdollEyes()

    if RagModOptions.View.HideHead() then
        HideHead(ragdoll) -- TODO: dont do this every frame
    end

    local finalAngles = inAngles

    if viewType == "firstperson" then
        -- Matched camera angles mode
        if RagModOptions.View.FirstPersonLocked() then
            finalAngles = ragEyeAngles
        else
            finalAngles = ragEyeAngles
            ProcessFirstPersonInput(inAngles)
            local _, worldAngles = LocalToWorld(Vector(0), LocalEyeAngle, Vector(0), ragEyeAngles)
            finalAngles = worldAngles
            WorldEyeAngle = finalAngles -- Stored to send to server
            LocalPlayer():SetEyeAngles(Angle(0, 0, 0))
        end
    end

    local depthOffset = ragEyeAngles:Forward() * RagModOptions.View.Offset()
    local heightOffset = ragEyeAngles:Up() * RagModOptions.View.HeightOffset()
    local finalOrigin = ragEyePos + depthOffset + heightOffset
    local finalZNear = RagModOptions.View.ZNear()

    local view = {
        origin = finalOrigin,
        angles = finalAngles,
        fov = inFov,
        znear = finalZNear,
        drawviewer = false,
    }

    return view
end

local LastSentAngles = Angle(0, 0, 0)

local function SendEyeAnglesToServer()
    -- Don't send duplicates
    if WorldEyeAngle == LastSentAngles then return end
    local viewType, locked = ragmod:GetPlayerViewType(LocalPlayer())
    if locked then return end
    if not ragmod:IsRagdoll(LocalPlayer()) then return end
    if viewType ~= "firstperson" then return end
    net.Start("ragmod::cl::custom_view", true)
    net.WriteAngle(WorldEyeAngle)
    net.SendToServer()
    LastSentAngles = WorldEyeAngle
end

-- Animates view changing from player to ragdoll
-- Duration, how long the animation should take
-- View = ragdoll view.
-- inOrigin and inAngles = Camera angles without possessing
local function AnimatePossess(view, duration, inOrigin, inAngles, inFov)
    if duration <= 0 then
        IsAnimatingPossess = false
        ModifiedAngle = nil
        ModifiedPos = nil

        return view
    end

    UnmodifiedAngle = view.angles
    UnmodifiedPos = view.origin
    local now = RealTime()
    local elapsed = now - RagdollDetectedAt
    -- Normalize
    local alpha = math.Clamp(elapsed / duration, 0, 1)
    local eased = math.ease.OutExpo(alpha)
    view.angles = LerpAngle(eased, inAngles, view.angles)
    view.origin = LerpVector(eased, inOrigin, view.origin)
    ModifiedAngle = view.angles
    ModifiedPos = view.origin

    if alpha >= 1 then
        IsAnimatingPossess = false
        ModifiedAngle = nil
        ModifiedPos = nil
    end

    return view
end

-- Animates unpossessing from ragdoll
-- view = player view without possessing
local function AnimateUnPossess(view, duration)
    if duration <= 0 then
        IsAnimatingUnPossess = false
        ModifiedAngle = nil
        ModifiedPos = nil

        return view
    end

    UnmodifiedAngle = view.angles
    UnmodifiedPos = view.origin
    local now = RealTime()
    local elapsed = now - RagdollLostAt
    -- Normalize
    local alpha = math.Clamp(elapsed / duration, 0, 1)
    local eased = math.ease.OutExpo(alpha)
    view.angles = LerpAngle(eased, MostRecentAngles, view.angles)
    view.origin = LerpVector(eased, MostRecentOrigin, view.origin)
    ModifiedAngle = view.angles
    ModifiedPos = view.origin

    if alpha >= 1.0 then
        IsAnimatingUnPossess = false
        ModifiedAngle = nil
        ModifiedPos = nil
    end

    return view
end

local function CalcViewModelView(wep, vm, oldPos, oldAng, pos, ang)
    if not IsAnimatingUnPossess then return end
    if not (UnmodifiedPos and UnmodifiedAngle and ModifiedAngle and ModifiedPos) then return end
    local relPos, relAngle = WorldToLocal(pos, ang, UnmodifiedPos, UnmodifiedAngle)

    return LocalToWorld(relPos, relAngle, ModifiedPos, ModifiedAngle)
end

local function CalcView(ply, inOrigin, inAngles, inFov)
    if LocalPlayer():GetViewEntity() ~= LocalPlayer() then return end -- Gmod camera
    local ragdoll = ragmod:GetRagmodRagdoll(LocalPlayer())
    if hook.Run("RM_CanChangeCamera", LocalPlayer()) == false then return end

    if not IsValid(ragdoll) or not ragmod:IsRagdoll(LocalPlayer()) then
        if RagdollDetectedAt and not RagdollLostAt then
            -- Transition from ragdoll view to normal
            RagdollLostAt = RealTime()
            IsAnimatingUnPossess = true
        end
        -- Animation 
        IsAnimatingPossess = false
        RagdollDetectedAt = nil
        -- Don't animate respawn
        if not LocalPlayer():Alive() then
            IsAnimatingUnPossess = false
            RagdollLostAt = nil
        end
        if not RagdollLostAt or not IsAnimatingUnPossess then return end

        local view = {
            origin = inOrigin,
            angles = inAngles,
            fov = inFov,
            drawviewer = false,
        }

        view = AnimateUnPossess(view, RagModOptions.View.SmoothingOut())

        return view
    end

    if FirstRagFrame then
        IsAnimatingPossess = true
        local _, ragEyeAngles = ragdoll:GetRagdollEyes()
        local _, localIntialAngles = WorldToLocal(Vector(0, 0, 0), inAngles, Vector(0), ragEyeAngles)
        localIntialAngles.roll = 0 -- If player somehow has managed to roll their camera, remove the roll
        LocalEyeAngle = localIntialAngles
        FirstRagFrame = false
        
        RagdollLostAt = nil
        RagdollDetectedAt = RealTime()
        net.Start("ragmod::cl::possess_anim_ready",false)
        net.SendToServer()
    elseif not RagdollDetectedAt then
        -- Ragdoll is not ready yet
        return
    end

    local viewType = GetActualViewType()

    -- Custom third person trace
    if viewType == "thirdperson" then
        view = CalcThirdPerson(ragdoll, inAngles, inFov)
    end

    if viewType == "firstperson" or viewType == "firstperson_pos_only" then
        view = CalcFirstPersonView(ragdoll, viewType, inAngles, inFov)
    end

    if IsAnimatingPossess then
        -- Only animate the angles in firstperson modes
        local startPos = view.origin
        local startAngle = inAngles

        if viewType == "thirdperson" then
            startPos = inOrigin
        end

        view = AnimatePossess(view, RagModOptions.View.SmoothingIn(), startPos, startAngle, inFov)
    end

    MostRecentAngles = view.angles
    MostRecentOrigin = view.origin

    return view
end

local function OnLocalPlayerPossessed(ragdoll)
    if not IsValid(ragdoll) then return end
    -- Transition from normal to ragdoll view
    FirstRagFrame = true
end

local function OnLocalPlayerUnPossessed(ragdoll)
    if not IsValid(ragdoll) then return end
    local curRagdoll = ragmod:GetRagmodRagdoll(LocalPlayer())
    if curRagdoll == ragdoll then
        LocalPlayer():SetNWEntity("ragmod_Possessed", NULL)
    end
    RevealHead(ragdoll)
end

hook.Add("ragmod::local_possessed", "ragmod::local_player_possessed", OnLocalPlayerPossessed)

net.Receive("ragmod::sv::local_unpossessed",function(len,_)
    OnLocalPlayerUnPossessed(net.ReadEntity())
end)

timer.Create("ragmod_SendEyeAngles", EyeSendDelay, 0, SendEyeAnglesToServer)
hook.Add("CalcView", "ragmod_CalcView", CalcView)
hook.Add("CalcViewModelView", "ragmod_CalcViewModelView", CalcViewModelView)

-- Add callback to recenter view
-- NOTE: This doesn't work on singleplayer, because all convars are Serverside :(
local function OnPlayerChangedViewType(...)
    if not ragmod:IsRagdoll(LocalPlayer()) then return end
    local viewType, _ = ragmod:GetPlayerViewType(LocalPlayer())
    LocalEyeAngle:Zero()

    if hook.Run("RM_CanChangeCamera", LocalPlayer()) == false then return end
    if viewType == "firstperson_pos_only" then
        LocalPlayer():SetEyeAngles(LocalEyeAngle)
    end
end

RagModOptions.View.ViewType:AddChangeCallback(OnPlayerChangedViewType)

hook.Add("InitPostEntity", "ragmod_InitPostEntity", function()
    if not RagModOptions.Tips() then return end
    local foundKey = nil

    for _, v in ipairs(RagmodInputTable) do
        if v.Name == "open_menu" then
            foundKey = v
            break
        end
    end

    local version = RagModOptions.Version()

    if foundKey then
        notification.AddLegacy(string.format(rmutil:GetPhrase("hint.openmenu"), foundKey:GetButtonName()), NOTIFY_HINT, 5)
    end

    notification.AddLegacy(string.format(rmutil:GetPhrase("hint.welcomeversion"), version), NOTIFY_GENERIC, 5)
end)

---------------
-- Hud stuff --
---------------
local function CreateFonts()
    surface.CreateFont("ragmod::HealthFont", {
        font = "HudNumbers",
        size = ScreenScale(25),
    })
end

CreateFonts()
hook.Add("OnScreenSizeChanged", "ragmod_OnScreenSizeChanged", CreateFonts)

local function DrawInputHelp()
    local x = 20
    local y = 20
    local padding = 10
    local totalHeight = 0
    local totalWidth = 0
    surface.SetFont("ChatFont")

    local lines = {"Controls:"}

    local tw, th = surface.GetTextSize(lines[1])
    totalWidth = tw
    totalHeight = totalHeight + th

    local function AddLine(text)
        table.insert(lines, text)
        tw, th = surface.GetTextSize(text)
        totalHeight = totalHeight + th
        totalWidth = math.max(totalWidth, tw)
    end

    for i, action in ipairs(RagmodInputTable) do
        local text = rmutil:GetPhrase("label.input." .. action.Name) .. ":  " .. action:GetButtonName()
        AddLine(text)
    end

    AddLine("Roll: Movement keys")
    surface.SetDrawColor(0, 0, 0, 80)
    surface.DrawRect(x, y, totalWidth + padding * 4, totalHeight + padding * 2)
    surface.SetTextColor(230, 230, 230)

    for i, line in ipairs(lines) do
        surface.SetTextPos(x + padding + (i == 1 and 0 or 10), y + padding + (i - 1) * th)
        surface.DrawText(line)
    end
end

local function DrawProgressBar()
    local elapsed = ragmod:GetTimeSincePossess(LocalPlayer())
    local total = RagModOptions.Ragdolling.GetUpDelay()
    local remaining = total - elapsed
    if remaining <= 0 then return end
    local remainingFrac = remaining / total
    local w = 500
    local h = 20
    local x = ScrW() / 2 - w / 2
    local y = ScrH() - h / 2
    surface.SetDrawColor(0, 0, 0, 117)
    surface.DrawRect(x, y, w, h)
    w = w * remainingFrac
    local col = LocalPlayer():GetPlayerColor() * 255
    surface.SetDrawColor(Color(col.x, col.y, col.z, 255))
    surface.DrawRect(x, y, w, h)
end

local function DrawHealth()
    local HealthText = tostring(math.max(LocalPlayer():Health(), 0))
    surface.SetFont("ragmod::HealthFont")
    surface.SetTextColor(255, 236, 12)
    surface.SetTextPos(ScrW() * 0.08, ScrH() * 0.9)
    surface.DrawText(HealthText)
end

local function HudPaint()
    local ply = LocalPlayer()
    if not ply:Alive() or not ragmod:IsRagdoll(ply) then return end

    if RagModOptions.Ragdolling.ShowControls() then
        DrawInputHelp()
    end

    if RagModOptions.Ragdolling.ShowHealth() then
        DrawHealth()
    end

    if RagModOptions.Ragdolling.ShowDelay() then
        DrawProgressBar()
    end
end

hook.Add("HUDPaint", "ragmod_HudPaint", HudPaint)
local PLAYER = FindMetaTable("Player")

function PLAYER:RM_OpenMenu()
    if IsValid(self.Ragmod_Menu) then
        self.Ragmod_Menu:MakePopup()

        return
    end

    local frame = vgui.Create("DFrame", nil, "RagmodPopUpWindow")
    local menu = vgui.Create("RagmodMenu", frame, "RagmodWindowMenu")
    frame:SetTitle(rmutil:GetPhrase("label.tab.ragmod"))
    frame:SetSizable(true)
    frame:SetSize(450, 600)
    frame:Center()
    frame:SetDraggable(true)
    frame:MakePopup()
    frame:SetDeleteOnClose(true)
    frame:SetScreenLock(true)
    menu:Dock(FILL)
    self.Ragmod_Menu = frame
end

function PLAYER:RM_CloseMenu()
    if not self.Ragmod_Menu or not self.Ragmod_Menu:IsValid() then return end
    self.Ragmod_Menu:Close()
end

function PLAYER:RM_ToggleMenu()
    local focus = vgui.GetKeyboardFocus()

    if not self.Ragmod_Menu or not self.Ragmod_Menu:IsValid() or not self.Ragmod_Menu:IsVisible() then
        self:RM_OpenMenu()
    elseif not IsValid(focus) or focus == self.Ragmod_Menu then
        self:RM_CloseMenu()
    end
end

concommand.Add("rm_menu", function(ply, cmd, args, argStr)
    LocalPlayer():RM_ToggleMenu()
end, nil, rmutil:GetPhrase("convar.help.rm_menu"))

local function AddMenuTab(tab, cat, func)
    spawnmenu.AddToolMenuOption(rmutil:GetPhrase("label.tab.ragmod"), rmutil:GetPhrase(tab), "Ragmod_" .. tab .. "_" .. cat, rmutil:GetPhrase(cat), "", "", func)
end

ragmenu = include("vgui/ragmod_menu_utils.lua")

hook.Add("PopulateToolMenu", "RagMod_PopulateMenu", function()
    AddMenuTab("label.tab.config_editor", "label.subtab.config_editor", function(form)
        local menu = vgui.Create("RagmodMenu", form, "")
        form:AddItem(menu)
        menu:SetTall(600)
        local b = input.LookupBinding("+menu_context", true)

        if b ~= nil then
            local help = form:Help("Press " .. tostring(b) .. " to view this menu in game")
            help:SetFont("DermaDefaultBold")
        end

        form:Button("Open as a window", "rm_menu")
    end)

    AddMenuTab("label.tab.server", "label.subtab.general", function(form)
        local list = vgui.Create("DCategoryList", form)
        list:Dock(FILL)
        list:SetTall(700)
        ragmenu:ServerGeneralTab(list)
        form:AddItem(list)
        form:InvalidateLayout(true)
    end)

    AddMenuTab("label.tab.server", "label.subtab.triggers", function(form)
        local list = vgui.Create("DCategoryList", form)
        list:Dock(FILL)
        list:SetTall(700)
        ragmenu:ServerTriggersTab(list)
        form:AddItem(list)
    end)

    AddMenuTab("label.tab.server", "label.subtab.movement", function(form)
        local list = vgui.Create("DCategoryList", form)
        list:Dock(FILL)
        list:SetTall(700)
        ragmenu:ServerMovementTab(list)
        form:AddItem(list)
    end)

    AddMenuTab("label.tab.server", "label.subtab.damage", function(form)
        local list = vgui.Create("DCategoryList", form)
        list:Dock(FILL)
        list:SetTall(700)
        ragmenu:ServerDamageTab(list)
        form:AddItem(list)
    end)

    AddMenuTab("label.tab.server", "label.subtab.ragdolling", function(form)
        local list = vgui.Create("DCategoryList", form)
        list:Dock(FILL)
        list:SetTall(700)
        ragmenu:ServerRagdollingTab(list)
        form:AddItem(list)
    end)

    AddMenuTab("label.tab.server", "label.subtab.compatibility", function(form)
        local list = vgui.Create("DCategoryList", form)
        list:Dock(FILL)
        list:SetTall(700)
        ragmenu:ServerCompatibilityTab(list)
        form:AddItem(list)
    end)

    AddMenuTab("label.tab.player", "label.subtab.ragdolling", function(form)
        local list = vgui.Create("DCategoryList", form)
        list:Dock(FILL)
        list:SetTall(700)
        ragmenu:ClientRagdollingTab(list)
        form:AddItem(list)
    end)

    AddMenuTab("label.tab.player", "label.category.bindings", function(form)
        local list = vgui.Create("DCategoryList", form)
        list:Dock(FILL)
        list:SetTall(700)
        ragmenu:InputTab(list)
        form:AddItem(list)
    end)
end)
--form:AddItem(ragmenu:CreateResetButton("General"))