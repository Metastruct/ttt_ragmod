----------------------------------------------------------
-- Title: ragmod utility module
-- Author: n-gon
-- Description:
----- Ragmod module containing extra functionality
----------------------------------------------------------
rmutil = {}

function rmutil:DebugPrint(...)
    local dbgCvar = GetConVar("rm_debug") -- ConVar might not have initialized yet
    if not dbgCvar or not dbgCvar:GetBool() then return end
    print("rm_debug: ", ...)
end

if CLIENT then
    function rmutil:GetPhrase(phrase)
        local localized = language.GetPhrase(phrase)

        if localized == phrase then
            rmutil:DebugPrint("Missing phrase: ", phrase)
        end

        return localized
    end
end

-- Returns the index of the first bone with the name containing the query string
function rmutil:SearchBone(ent, query)
    local boneidx = nil

    for i = 0, ent:GetBoneCount() - 1 do
        local name = ent:GetBoneName(i)
        if not name then continue end
        if name == "__INVALIDBONE__" then continue end

        if string.find(name:lower(), query:lower()) then
            boneidx = i
            break
        end
    end

    return boneidx
end



--[[
 Array removal algorithm from https://stackoverflow.com/a/53038524
 t is the array-table to remove from
 fnKeep is a function with the parameters (table, index, nextIndex)
    return true to keep, false to remove
]]
function rmutil:ArrayRemove(t, fnKeep)
    local j, n = 1, #t

    for i = 1, n do
        if fnKeep(t, i, j) then
            if i ~= j then
                t[j] = t[i]
                t[i] = nil
            end

            j = j + 1
        else
            t[i] = nil
        end
    end

    return t
end

-- Converts a forward vector to an angle with a roll of 0
function rmutil:AimToAngle(aim)
    return Angle(math.deg(math.asin(-aim.z)), math.deg(math.atan2(aim.y, aim.x)), 0)
end

return rmutil