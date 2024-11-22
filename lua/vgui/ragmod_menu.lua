----------------------------------------------------------
-- Title: ragmod_menu
-- Author: n-gon
-- Description:
----- Contains RagmodMenu vgui panel, which is used in the spawnmenu, but can be added to any frame
----------------------------------------------------------

local ragmenu = include("ragmod_menu_utils.lua")

local function GetNewPage()
    local ScrollPanel = vgui.Create("DScrollPanel", nil)
    ScrollPanel:Dock(FILL)
    local CategoryList = vgui.Create("DCategoryList", ScrollPanel)
    CategoryList:Dock(FILL)
    CategoryList:SetTall(500)

    return ScrollPanel, CategoryList
end

local function BuildServerPanel()
    local ServerPanel = vgui.Create("DPanel", nil)

    ServerPanel.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Color(0, 0, 0, 0))
    end

    -- Tabs
    local Sheet = vgui.Create("DPropertySheet", ServerPanel)
    Sheet:Dock(FILL)
    ------------------
    -- General Tab  --
    ------------------
    local scroll, list = GetNewPage()
    ragmenu:ServerGeneralTab(list)
    Sheet:AddSheet(rmutil:GetPhrase("label.subtab.general"), scroll, "icon16/cog.png")
    ------------------
    -- Triggers Tab  --
    ------------------
    local scroll, list = GetNewPage()
    ragmenu:ServerTriggersTab(list)
    Sheet:AddSheet(rmutil:GetPhrase("label.subtab.triggers"), scroll, "icon16/resultset_next.png")
    ------------------
    -- Movement tab --
    ------------------
    local scroll, list = GetNewPage()
    ragmenu:ServerMovementTab(list)
    Sheet:AddSheet(rmutil:GetPhrase("label.subtab.movement"), scroll, "icon16/car.png")
    ------------------
    -- Damage Tab  --
    ------------------
    local scroll, list = GetNewPage()
    ragmenu:ServerDamageTab(list)
    Sheet:AddSheet(rmutil:GetPhrase("label.subtab.damage"), scroll, "icon16/lightning.png")
    --------------------
    -- Ragdolling tab --
    --------------------
    local scroll, list = GetNewPage()
    ragmenu:ServerRagdollingTab(list)
    Sheet:AddSheet(rmutil:GetPhrase("label.subtab.ragdolling"), scroll, "icon16/joystick.png")
    --------------------
    -- Compatibility tab --
    --------------------
    local scroll, list = GetNewPage()
    ragmenu:ServerCompatibilityTab(list)
    Sheet:AddSheet(rmutil:GetPhrase("label.subtab.compatibility"), scroll,"icon16/cog.png")

    return ServerPanel
end

local function BuildPlayerPanel()
    local PlayerPanel = vgui.Create("DPanel", nil)

    PlayerPanel.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Color(0, 0, 0, 0))
    end

    -- Tabs
    local Sheet = vgui.Create("DPropertySheet", PlayerPanel)
    Sheet:Dock(FILL)
    local scroll, list = GetNewPage()
    ragmenu:ClientRagdollingTab(list)
    Sheet:AddSheet(rmutil:GetPhrase("label.subtab.ragdolling"), scroll, "icon16/joystick.png")

    return PlayerPanel
end

local function BuildInputPanel()
    local scroll, list = GetNewPage()
    list:SetTall(800)
    ragmenu:InputTab(list)

    return scroll
end

local function BuildOtherPanel()
    local Panel = vgui.Create("DPanel", nil)

    Panel.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Color(0, 0, 0, 0))
    end

    -- Tabs
    local Sheet = vgui.Create("DPropertySheet", Panel)
    Sheet:Dock(FILL)
    local scroll, list = GetNewPage()
    ragmenu:OtherTab(list)
    Sheet:AddSheet(rmutil:GetPhrase("label.tab.other"), scroll, "icon16/cog.png")

    return Panel
end

--- The main panel
local PANEL = {}

function PANEL:Init()
    -- Settings tab
    if not LocalPlayer() or LocalPlayer():IsAdmin() then
        self:AddSheet(rmutil:GetPhrase("label.tab.server"), BuildServerPanel(), "icon16/shield.png")
    end

    self:AddSheet(rmutil:GetPhrase("label.tab.player"), BuildPlayerPanel(), "icon16/user.png")
    -- Input tab
    self:AddSheet(rmutil:GetPhrase("label.tab.input"), BuildInputPanel(), "icon16/controller.png")
    
    self:AddSheet(rmutil:GetPhrase("label.tab.other"), BuildOtherPanel(), "icon16/cog.png")

end

vgui.Register("RagmodMenu", PANEL, "DPropertySheet")