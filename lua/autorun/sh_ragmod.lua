----------------------------------------------------------
-- Title: sh_ragmod
-- Author: n-gon
-- Description:
----- Ragmod shared autorun
----------------------------------------------------------
AddCSLuaFile("includes/modules/ragmod_utils.lua")
AddCSLuaFile("includes/modules/ragmod_options.lua")
AddCSLuaFile("includes/modules/ragmod.lua")
AddCSLuaFile("ragmod/ragmod_input.lua")
require("ragmod")
require("ragmod_utils")
require("ragmod_options")
include("ragmod/ragmod_input.lua")