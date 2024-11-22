require("ragmod_utils")
require("ragmod_options")
require("ragmod")
local InputIdTable = {}
--[[
Input param structure
{
    name = <action_name>,
    key = <default_key>,
    client = nil or func(self, ply, pressed), 
        Nil if a normal action, function for client only actions
        input argument is the input table itself
    preBlock = func(self, ply, pressed)
        Function to call (clientside) before the action. Return true to block action
        Not used in singleplayer

}
]]
---------------------------
-- Input metatable setup --
---------------------------
local inputMeta = {}
local INPUT = CLIENT or game.SinglePlayer()

if INPUT then
    -- Send input to server or activate clientside inputs
    -- Id is the index of the action in the RagmodInputTable
    -- Id is negated before sending if the button was released
    -- Sent action is an 8 bit signed int, meaning 127 possible actions (0 is unused)
    -- On singleplayer these are ran serverside
    function inputMeta:__call(pressed)
        local id = InputIdTable[self.Name]
        if not id then return end
        local ply = CLIENT and LocalPlayer() or player.GetByID(1)

        if CLIENT then
            if self.PreBlock and self:PreBlock(ply, pressed) then return end
            -- On singleplayer we only run this later on the server
            if hook.Run("RM_CanAction", ply, self.Name) == false then return end
        end

        if self.Client then
            self:Client(ply, pressed)

            return
        end

        if not pressed then
            id = -id
        end

        if SERVER then
            -- Single player handles input on the server
            hook.Run("ragmod::sp_input", id)
        else
            net.Start("ragmod::cl::input", false)
            net.WriteInt(id, 8)
            net.SendToServer()
        end
    end
end

local inputIndex = {}

if INPUT then
    function inputIndex:GetButton()
        return self.ConVar:GetInt()
    end

    function inputIndex:GetButtonName()
        local btn = self:GetButton()
        if not btn then return "" end
        local btnName = input.GetKeyName(btn)
        if not btnName then return "" end

        return language.GetPhrase(btnName)
    end
end

inputMeta.__index = inputIndex
--------------------
-- Callback setup --
--------------------
local cvarInputMap = {}

---------------------
-- Input Creation --
---------------------
local function CreateInput(tbl)
    local inp = {}
    setmetatable(inp, inputMeta)
    inp.Name = tbl.name
    inp.ConVarName = "rm_key_" .. tbl.name

    if isfunction(tbl.preBlock) then
        inp.PreBlock = tbl.preBlock
    end

    inp.Client = tbl.client

    if INPUT then
        local helptext = CLIENT and rmutil:GetPhrase("convar.input.help." .. inp.Name) or "Binding: " .. inp.Name
        inp.ConVar = CreateClientConVar(inp.ConVarName, tbl.key, true, false, helptext, min, max)
        -- Also store ref to option in a lookup table
        cvarInputMap[inp.ConVarName] = inp
    end

    return inp
end

---------------------------
-- Custom input handling --
---------------------------
--
-- Input mapping table
--
RagmodInputTable = {
    CreateInput({
        name = "ragdolize",
        key = KEY_G,
        preBlock = function(self, ply, pressed)
            if not pressed then return true end

            if CLIENT and not RagModOptions.ManualRagdolling() and RagModOptions.Tips() then
                notification.AddLegacy(rmutil:GetPhrase("hint.manual_ragdoll_disabled"), NOTIFY_ERROR, 2)

                return true
            end

            if not ply:Alive() or ragmod:IsRagdoll(ply) then return true end
        end,
    }),
    CreateInput({
        name = "unpossess",
        key = KEY_SPACE,
        preBlock = function(self, ply, pressed)
            if pressed then return true end
            if not ply:Alive() or not ragmod:IsRagdoll(ply) then return true end
        end,
    }),
    CreateInput({
        name = "fly",
        key = KEY_LCONTROL,
    }),
    CreateInput({
        name = "reach_right",
        key = MOUSE_RIGHT,
    }),
    CreateInput({
        name = "reach_left",
        key = MOUSE_LEFT,
    }),
    CreateInput({
        name = "cam_cycle",
        key = KEY_F,
        client = function(self, ply, pressed)
            if not pressed then return end
            if not ragmod:IsRagdoll(ply) then return end
            local choices = RagModOptions.View.ViewType.Choices
            local current = RagModOptions.View.ViewType.ConVar:GetInt()
            local new = (current + 1) % (#choices)
            RagModOptions.View.ViewType(new)
        end
    }),
    CreateInput({
        name = "show_controls",
        key = KEY_H,
        client = function(self, ply, pressed)
            if not pressed then return end
            if not ragmod:IsRagdoll(ply) then return end
            local current = tobool(RagModOptions.Ragdolling.ShowControls.ConVar:GetInt())
            RagModOptions.Ragdolling.ShowControls(not current)
        end
    }),
    CreateInput({
        name = "open_menu",
        key = KEY_K,
        client = function(self, ply, pressed)
            if pressed then return end
            RunConsoleCommand("rm_menu")
        end
    }),
}

for id, inpt in ipairs(RagmodInputTable) do
    InputIdTable[inpt.Name] = id
end

if INPUT then
    -- Bridge the gmod inputs into the RagMod input system
    local function PlayerButtonDown(ply, button)
        if not IsFirstTimePredicted() then return end

        for id, action in ipairs(RagmodInputTable) do
            if button ~= action:GetButton() then continue end
            action(true)
        end
    end

    local function PlayerButtonUp(ply, button)
        if not IsFirstTimePredicted() then return end

        for id, action in ipairs(RagmodInputTable) do
            if button ~= action:GetButton() then continue end
            action(false)
        end
    end

    hook.Add("PlayerButtonDown", "ragmod_PlayerButtonDown", PlayerButtonDown)
    hook.Add("PlayerButtonUp", "ragmod_PlayerButtonUp", PlayerButtonUp)
    --[[
        Workaround for menu action not being received when in menu state
    ]]
    local debounce = 0

    local function CreateMove(cmd)
        local ply = LocalPlayer()
        local foundKey = nil

        for _, v in ipairs(RagmodInputTable) do
            if v.Name == "open_menu" then
                foundKey = v
                break
            end
        end

        if not foundKey then return end

        if input.WasKeyReleased(foundKey:GetButton()) then
            -- Debounce 
            local tick = SysTime()
            if (tick - debounce) < 0.1 then return end
            debounce = tick
            if gui.IsGameUIVisible() or gui.IsConsoleVisible() then return end
            local focus = vgui.GetKeyboardFocus()

            if not IsValid(focus) or focus == ply.Ragmod_Menu then
                ply:RM_CloseMenu()
            end
        end
    end

    hook.Add("CreateMove", "ragmod_CreateMove", CreateMove)
end