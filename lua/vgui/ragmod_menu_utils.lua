require("ragmod_utils")
require("ragmod_options")


local LIB = {}
local AllOptions = {} -- Keeps track of all options we have a menu for
local OptionCache = {} -- Used to automatically create a reset button by keeping track of added controls

local function GetOptionLabel(option)
    if not option then return "" end

    return rmutil:GetPhrase("label.option." .. option.ConVar:GetName())
end

local function GetOptionHelpText(option)
    if not option then return "" end

    return rmutil:GetPhrase("convar.help." .. option.ConVar:GetName())
end

local function GetOptionControlHelp(option)
    if not option then return "" end

    return rmutil:GetPhrase("label.option.extra." .. option.ConVar:GetName())
end

local function GetChoiceHelp(option)
    if not option then return {} end
    local helps = {}

    for idx, choiceID in ipairs(option.Choices) do
        local help = rmutil:GetPhrase(string.format("choice.option.extra.%s.%s", option.Name, choiceID))
        local name = rmutil:GetPhrase(string.format("choice.option.%s.%s", option.Name, choiceID))
        table.insert(helps, string.format("%s: %s", name, help))
    end

    return helps
end

local function GetNewForm(title)
    local form = vgui.Create("DForm", nil)
    form:SetLabel(title)

    return form
end

function LIB:ResetOptions(options)
    for _, option in ipairs(options) do
        if not option then
            if RagModOptions.Debug() then
                ErrorNoHalt("Invalid option", option)
            end

            continue
        end

        -- ConVar:Revert doesn't work on clients
        RunConsoleCommand(option.ConVar:GetName(), tostring(option.ConVar:GetDefault()))
    end
end

function LIB:CreateResetButton(localeName)
    local reset = vgui.Create("DButton", nil)
    reset:SetText(rmutil:GetPhrase("label.button.reset." .. localeName))
    local options = table.Copy(OptionCache)

    reset.DoClick = function()
        if RagModOptions.Tips() then
            notification.AddLegacy(rmutil:GetPhrase("hint.reset.success." .. localeName), NOTIFY_GENERIC, 2)
        end

        surface.PlaySound("buttons/button15.wav")
        LIB:ResetOptions(options)
    end

    table.Empty(OptionCache)

    return reset
end

local function CreateOptionSlider(form, option, decimals)
    if not option then
        if RagModOptions.Debug() then
            ErrorNoHalt("Invalid option", option)
        end

        return form:NumSlider("", 0, 0, decimals)
    end

    local cv = option.ConVar
    local help = GetOptionHelpText(option)
    local min = option.GUIMin or cv:GetMin() or 0
    local max = option.GUIMax or cv:GetMax() or 1000
    local slider = form:NumSlider(GetOptionLabel(option), cv:GetName(), min, max, decimals)
    slider:SetDefaultValue(tonumber(cv:GetDefault()))

    if help and help ~= "" then
        slider:SetTooltip(help)
    end

    table.insert(OptionCache, option)
    table.insert(AllOptions, option)

    return slider
end

local function CreateOptionCheckbox(form, option)
    if not option then
        if RagModOptions.Debug() then
            ErrorNoHalt("Invalid option", option)
        end

        return form:CheckBox("", "")
    end

    local cv = option.ConVar
    local help = GetOptionHelpText(option)
    local checkbox = form:CheckBox(GetOptionLabel(option), cv:GetName())

    if help and help ~= "" then
        checkbox:SetTooltip(help)
    end

    table.insert(OptionCache, option)
    table.insert(AllOptions, option)

    return checkbox
end

function LIB:CreateOptionCheckbox(...)
    return CreateOptionCheckbox(...)
end

local function CreateOptionComboBox(form, option)
    if not option then
        if RagModOptions.Debug() then
            ErrorNoHalt("Invalid option", option)
        end

        return form:ComboBox("", "")
    end

    local cv = option.ConVar
    local combobox, label = form:ComboBox(GetOptionLabel(option), cv:GetName())

    for idx, choiceID in ipairs(option.Choices) do
        local name = rmutil:GetPhrase(string.format("choice.option.%s.%s", option.Name, choiceID))
        combobox:AddChoice(name, idx - 1)
    end

    local help = GetOptionHelpText(option)

    if help and help ~= "" then
        label:SetTooltip(help)
        combobox:SetTooltip(help)
    end

    table.insert(OptionCache, option)
    table.insert(AllOptions, option)

    return combobox, label
end

function LIB:ServerGeneralTabGeneral(form)
    CreateOptionCheckbox(form, RagModOptions.Enabled)
    CreateOptionCheckbox(form, RagModOptions.ManualRagdolling)
    form:ControlHelp(GetOptionControlHelp(RagModOptions.ManualRagdolling))
    CreateOptionSlider(form, RagModOptions.RagdollLimit, 0)
    CreateOptionCheckbox(form, RagModOptions.DropWeapons)
end

function LIB:ServerGeneralTabDoors(form)
    CreateOptionCheckbox(form, RagModOptions.DoorBreaching.Enable)
    CreateOptionSlider(form, RagModOptions.DoorBreaching.Resistance, 0)
    CreateOptionSlider(form, RagModOptions.DoorBreaching.LaunchPower, 0)
end

function LIB:ServerGeneralTabMisc(form)
    CreateOptionCheckbox(form, RagModOptions.Misc.AllowSpawnmenu)
    form:ControlHelp(GetOptionControlHelp(RagModOptions.Misc.AllowSpawnmenu))
    CreateOptionCheckbox(form, RagModOptions.Misc.AdjustSpawn)
    CreateOptionCheckbox(form, RagModOptions.Misc.NormalDeathRagdolls)
    form:Help(rmutil:GetPhrase("label.info.serveronlysettings"))
end

function LIB:ServerGeneralTab(list)
    local form = GetNewForm(rmutil:GetPhrase("label.category.general"))
    self:ServerGeneralTabGeneral(form)
    form:Help("")
    list:AddItem(form)
    local form = GetNewForm(rmutil:GetPhrase("label.category.doors"))
    self:ServerGeneralTabDoors(form)
    form:Help("")
    list:AddItem(form)
    local form = GetNewForm(rmutil:GetPhrase("label.category.misc"))
    self:ServerGeneralTabMisc(form)
    form:Help("")
    list:AddItem(form)
    list:AddItem(self:CreateResetButton("general"))
end

function LIB:ServerTriggersTab(list)
    local form = GetNewForm(rmutil:GetPhrase("label.category.speed"))
    CreateOptionCheckbox(form, RagModOptions.Trigger.Speed)
    CreateOptionCheckbox(form, RagModOptions.Trigger.SpeedNoclip)
    CreateOptionSlider(form, RagModOptions.Trigger.SpeedThreshold, 0)
    form:ControlHelp(GetOptionControlHelp(RagModOptions.Trigger.SpeedThreshold))
    CreateOptionCheckbox(form, RagModOptions.Trigger.OnlyFall)
    form:Help("")
    list:AddItem(form)
    local form = GetNewForm(rmutil:GetPhrase("label.category.damage"))
    CreateOptionCheckbox(form, RagModOptions.Trigger.Damage)
    CreateOptionSlider(form, RagModOptions.Trigger.DamageThreshold, 0)
    CreateOptionCheckbox(form, RagModOptions.Trigger.FallImpact)
    form:ControlHelp(string.format(rmutil:GetPhrase("label.option.info.triggerexceptionoff"), GetOptionLabel(RagModOptions.Trigger.Damage)))
    CreateOptionCheckbox(form, RagModOptions.Trigger.Explosion)
    form:ControlHelp(string.format(rmutil:GetPhrase("label.option.info.triggerexceptionoff"), GetOptionLabel(RagModOptions.Trigger.Damage)))
    CreateOptionCheckbox(form, RagModOptions.Trigger.RocketJump)
    form:ControlHelp(string.format(rmutil:GetPhrase("label.option.info.triggerexceptionoff"), GetOptionLabel(RagModOptions.Trigger.Damage)))
    form:ControlHelp(rmutil:GetPhrase("label.option.extra.rocketjump1") .. "\n" .. rmutil:GetPhrase("label.option.extra.rocketjump2"))
    CreateOptionCheckbox(form, RagModOptions.Trigger.DamageInVehicle)
    form:Help("")
    list:AddItem(form)
    local form = GetNewForm(rmutil:GetPhrase("label.category.vehicle"))
    CreateOptionCheckbox(form, RagModOptions.Trigger.VehicleImpact)
    CreateOptionSlider(form, RagModOptions.Trigger.VehicleImpactThreshold, 0)
    list:AddItem(form)
    list:AddItem(self:CreateResetButton("triggers"))
end

function LIB:ServerMovementTab(list)
    -- Rolling
    local form = GetNewForm(rmutil:GetPhrase("label.category.rolling"))
    CreateOptionCheckbox(form, RagModOptions.Rolling.Enabled)
    CreateOptionSlider(form, RagModOptions.Rolling.Force, 0)
    -- Flying
    list:AddItem(form)
    local form = GetNewForm(rmutil:GetPhrase("label.category.flying"))
    CreateOptionCheckbox(form, RagModOptions.Flying.Enabled)
    CreateOptionCheckbox(form, RagModOptions.Flying.AdminOverride)
    CreateOptionSlider(form, RagModOptions.Flying.Force, 0)
    -- Arms
    list:AddItem(form)
    local form = GetNewForm(rmutil:GetPhrase("label.category.arms"))
    CreateOptionCheckbox(form, RagModOptions.Limbs.Enabled)
    CreateOptionCheckbox(form, RagModOptions.Limbs.Grabbing)
    CreateOptionSlider(form, RagModOptions.Limbs.Force, 0)
    CreateOptionSlider(form, RagModOptions.Limbs.ForceLimit, 0)
    form:ControlHelp(GetOptionControlHelp(RagModOptions.Limbs.ForceLimit))
    CreateOptionCheckbox(form, RagModOptions.Limbs.ReleaseOnDeath)
    form:Help("")
    list:AddItem(form)
    list:AddItem(self:CreateResetButton("movement"))
end

function LIB:ServerDamageTab(list)
    local form = GetNewForm(rmutil:GetPhrase("label.category.damage"))
    CreateOptionCheckbox(form, RagModOptions.Damage.GodMode)
    CreateOptionCheckbox(form, RagModOptions.Damage.Bodypart)
    CreateOptionCheckbox(form, RagModOptions.Damage.PvP)
    CreateOptionCheckbox(form, RagModOptions.Damage.Physics)
    CreateOptionSlider(form, RagModOptions.Damage.ForceMultiplier, 2)
    form:ControlHelp(GetOptionControlHelp(RagModOptions.Damage.ForceMultiplier))
    CreateOptionSlider(form, RagModOptions.Damage.PhysicsMultiplier, 2)
    form:ControlHelp(GetOptionControlHelp(RagModOptions.Damage.PhysicsMultiplier))
    CreateOptionSlider(form, RagModOptions.Damage.Multiplier, 2)
    CreateOptionSlider(form, RagModOptions.Damage.MinPhysicsDamage, 1)
    form:ControlHelp(GetOptionControlHelp(RagModOptions.Damage.MinPhysicsDamage))
    form:Help("")
    list:AddItem(form)
    list:AddItem(self:CreateResetButton("damage"))
end

function LIB:ServerRagdollingTab(list)
    local form = GetNewForm(rmutil:GetPhrase("label.category.ragdolling"))
    CreateOptionSlider(form, RagModOptions.Ragdolling.GetUpDelay, 1)
    list:AddItem(form)
    local form = GetNewForm(rmutil:GetPhrase("label.category.view"))
    CreateOptionCheckbox(form, RagModOptions.View.ForcedView)
    CreateOptionComboBox(form, RagModOptions.View.ForcedViewType)
    form:Help("")
    list:AddItem(form)
    local form = GetNewForm(rmutil:GetPhrase("label.category.effects"))
    CreateOptionCheckbox(form, RagModOptions.Effects.Sounds)
    CreateOptionCheckbox(form, RagModOptions.Effects.GrabSounds)
    CreateOptionCheckbox(form, RagModOptions.Effects.RagSounds)
    CreateOptionCheckbox(form, RagModOptions.Effects.PainSounds)
    CreateOptionCheckbox(form, RagModOptions.Effects.PainOnlyDamage)
    CreateOptionCheckbox(form, RagModOptions.Effects.Blood)
    CreateOptionSlider(form, RagModOptions.Effects.BloodThreshold, 1)
    form:ControlHelp(GetOptionControlHelp(RagModOptions.Effects.BloodThreshold))
    list:AddItem(form)
    list:AddItem(self:CreateResetButton("ragdolling"))
end

function LIB:ServerCompatibilityTab(list)
    local form = GetNewForm(rmutil:GetPhrase("label.category.general"))
    local option = RagModOptions.Compatibility.RestoreInventoryStage
    CreateOptionComboBox(form, option)
    form:ControlHelp(GetOptionControlHelp(option))

    for i, help in ipairs(GetChoiceHelp(option)) do
        form:Help(help)
    end
    form:Help("")
    list:AddItem(form)
    list:AddItem(self:CreateResetButton("compatibility"))
end

function LIB:ClientRagdollingTab(list)
    local form = GetNewForm(rmutil:GetPhrase("label.category.view"))

    CreateOptionComboBox(form, RagModOptions.View.ViewType)
    form:Help("")
    list:AddItem(form)
    local form = GetNewForm(rmutil:GetPhrase("label.category.firstperson"))
    CreateOptionSlider(form, RagModOptions.View.SmoothingIn, 2)
    CreateOptionSlider(form, RagModOptions.View.SmoothingOut, 2)
    CreateOptionSlider(form, RagModOptions.View.ZNear, 2)
    form:ControlHelp(GetOptionControlHelp(RagModOptions.View.ZNear))
    CreateOptionSlider(form, RagModOptions.View.Offset, 2)
    form:ControlHelp(GetOptionControlHelp(RagModOptions.View.Offset))
    CreateOptionSlider(form, RagModOptions.View.HeightOffset, 2)
    form:ControlHelp(GetOptionControlHelp(RagModOptions.View.HeightOffset))
    CreateOptionCheckbox(form, RagModOptions.View.FirstPersonLocked)
    CreateOptionCheckbox(form, RagModOptions.View.HideHead)
    CreateOptionCheckbox(form, RagModOptions.View.SpectateImmediately, 2)
    form:ControlHelp(GetOptionControlHelp(RagModOptions.View.SpectateImmediately))
    list:AddItem(form)
    local form = GetNewForm(rmutil:GetPhrase("label.category.effects"))
    CreateOptionComboBox(form, RagModOptions.Effects.VoiceType)
    CreateOptionCheckbox(form, RagModOptions.Ragdolling.ShowDelay)
    CreateOptionCheckbox(form, RagModOptions.Ragdolling.ShowHealth)
    form:Help("")
    list:AddItem(form)
    list:AddItem(self:CreateResetButton("ragdolling"))
end

function LIB:OtherTab(list)
    local form = GetNewForm(rmutil:GetPhrase("label.category.reset"))
    local reset = vgui.Create("DButton", nil)
    reset.FirstPress = true
    local resetText = rmutil:GetPhrase("label.button.reset.all")
    local confirmText = rmutil:GetPhrase("label.button.reset.all.confirm")
    reset:SetText(resetText)

    reset.DoClick = function()
        if not reset.FirstPress then
            LIB:ResetOptions(AllOptions)

            if RagModOptions.Tips() then
                notification.AddLegacy(rmutil:GetPhrase("hint.reset.success.all"), NOTIFY_GENERIC, 2)
            end

            surface.PlaySound("buttons/button15.wav")
            reset:SetText(resetText)
        else
            reset:SetText(confirmText)
        end

        reset.FirstPress = not reset.FirstPress
    end

    form:AddItem(reset)

    if LocalPlayer():IsAdmin() or game.SinglePlayer() then
        local removeAll = vgui.Create("DButton", nil)
        removeAll:SetText(rmutil:GetPhrase("label.button.removeragdolls"))

        removeAll.DoClick = function()
            net.Start("ragmod::cl::clear_all", false)
            net.SendToServer()
            surface.PlaySound("buttons/button15.wav")

            if RagModOptions.Tips() then
                notification.AddLegacy(rmutil:GetPhrase("label.button.success.removeragdolls"), NOTIFY_GENERIC, 2)
            end
        end

        form:AddItem(removeAll)
    end

    list:AddItem(form)
end

function KeyBinder(panel, label1, convar1, label2, convar2)
    local binder = vgui.Create("RagmodCtrlNumPad", panel)
    binder:SetLabel1(label1)
    binder:SetConVar1(convar1)

    if label2 ~= nil and convar2 ~= nil then
        binder:SetLabel2(label2)
        binder:SetConVar2(convar2)
    end

    panel:AddItem(binder)

    return binder
end

local function CreateInputBinder(action, panel)
    local binder = KeyBinder(panel, rmutil:GetPhrase("label.input." .. action.Name), action.ConVarName)
    binder.Label1:SetFont("DermaDefaultBold")
end

function LIB:InputTab(list)
    local ControlPanel = vgui.Create("DForm", nil)
    ControlPanel:SetLabel(rmutil:GetPhrase("label.category.bindings"))
    ragmenu:CreateOptionCheckbox(ControlPanel, RagModOptions.Ragdolling.ShowControls)

    for id, action in ipairs(RagmodInputTable) do
        CreateInputBinder(action, ControlPanel)
    end

    local reset = vgui.Create("DButton", nil)
    reset:SetText(rmutil:GetPhrase("label.button.reset.bindings"))
    reset:Dock(BOTTOM)

    reset.DoClick = function()
        if RagModOptions.Tips() then
            notification.AddLegacy(rmutil:GetPhrase("hint.reset.success.bindings"), NOTIFY_GENERIC, 2)
        end

        surface.PlaySound("buttons/button15.wav")

        ragmenu:ResetOptions({RagModOptions.Ragdolling.ShowControls})

        ragmenu:ResetOptions(RagmodInputTable)
    end
    ControlPanel:Help("")
    list:AddItem(ControlPanel)
    list:AddItem(reset)
end

return LIB