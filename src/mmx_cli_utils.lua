#!/usr/bin/lua
--[[
################################################################################
#
# mmx_cli_utils.lua
#
# Copyright (c) 2013-2021 Inango Systems LTD.
#
# Author: Inango Systems LTD. <support@inango-systems.com>
# Creation Date: Jan 2013
#
# The author may be reached at support@inango-systems.com
#
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# Subject to the terms and conditions of this license, each copyright holder
# and contributor hereby grants to those receiving rights under this license
# a perpetual, worldwide, non-exclusive, no-charge, royalty-free, irrevocable
# (except for failure to satisfy the conditions of this license) patent license
# to make, have made, use, offer to sell, sell, import, and otherwise transfer
# this software, where such license applies only to those patent claims, already
# acquired or hereafter acquired, licensable by such copyright holder or contributor
# that are necessarily infringed by:
#
# (a) their Contribution(s) (the licensed copyrights of copyright holders and
# non-copyrightable additions of contributors, in source or binary form) alone;
# or
#
# (b) combination of their Contribution(s) with the work of authorship to which
# such Contribution(s) was added by such copyright holder or contributor, if,
# at the time the Contribution is added, such addition causes such combination
# to be necessarily infringed. The patent license shall not apply to any other
# combinations which include the Contribution.
#
# Except as expressly stated above, no rights or licenses from any copyright
# holder or contributor is granted under this license, whether expressly, by
# implication, estoppel or otherwise.
#
# DISCLAIMER
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
# USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# NOTE
#
# This is part of a management middleware software package called MMX that was developed by Inango Systems Ltd.
#
# This version of MMX provides web and command-line management interfaces.
#
# Please contact us at Inango at support@inango-systems.com if you would like to hear more about
# - other management packages, such as SNMP, TR-069 or Netconf
# - how we can extend the data model to support all parts of your system
# - professional sub-contract and customization services
#
################################################################################
--]]

require("mmx/mmx-frontapi")
require("mmx/ing_utils")
require("mmx/mmx_api_wrapper")
require("luci/mmx/mmx_web_info")

--  ---- Some  constants used by this code
local keysDelim = "  "
local cli_callerid = 2
local ERROR_NO_ERROR = 0
local MAX_EXTERNAL_ERROR = 100 --Errors which not from back-ends or entry-point

--[[ -----------------------------------------
--   Function parses input agrs of script.
--   Script`s args have format:
--       name1=value1 name2=value2...
--
--    Returns:
--       Resulting table contains array of agrs
--       arg_array={name1=value1, name2=value2}
-- ------------------------------------------]]
local function arg2hash()

    ing.utils.logMessage("mmx-cli", "Lua input args:\n", ing.utils.tableToString (arg))
    for i=1, #arg do
        arg[i] = string.gsub(arg[i],"=(.+)$","=\"%1\"")
    end
    local str = "arg_array={"..table.concat(arg,", ").."}"
    str = string.gsub(str, "\n", "")	--Cut newline character
    assert(loadstring(str))()
    return arg_array
end

--[[ -----------------------------------------
--   Function retreives table containing list of instances (indexes)
--   of the object specified by partPath
--    Input params:
--       partPath - string with object name ending by "."
--           (for example Device.Ethernet.Interface.{i}.)
--
--    Returns:
--       allList - table List of instanes
--       allList = { "Device.Ethernet.Interface.1.",
                     "Device.Ethernet.Interface.5." }
-- ------------------------------------------]]
--Limitation: works with no more then 2 indexes
--TODO!!! support more indeces
local function getInstList(partPath)
    local tail  = ""
    local function ends_with(str, ending)
	return ending == "" or str:sub(-#ending) == ending
    end
    string.gsub(partPath, "%b[]",
                        function(x) tail = x end)
    if (ends_with(partPath,tail..'.')) then
        return mmx_api_wrapper:countRow(partPath)
    else
	---- for objects like Device.IP.Interface.[1-3].IPv4Address.*.
	local allList = {}
	local errcode = 0
	local _, _, st, en = string.find(tail, "(%d+)-(%d+)")
	for i = st,en do
		local lst
		local subq = string.gsub(partPath, "%b[]",
			function(x) return tostring(i) end)
		errcode, lst =  mmx_api_wrapper:countRow(subq)
		if errcode ~= ERROR_NO_ERROR then break end
		for _, v in pairs(lst) do
			table.insert(allList, v)
		end
	end
	return errcode, allList
    end
end

--[[ -----------------------------------------
--   Function gets information needed for object rendering
--    Input params:
--       mngModObjName - object (for example Device.Ethernet.Interface.{i}.)
--
--    Returns:
--       section - object`s rendering section
-- ------------------------------------------]]
local function getObjSection(mngModObjName, sectId)

    ing.utils.logMessage("mmx-cli",  "getObjSection for object ", mngModObjName)
    for grname, grinfo in pairs(mmx_web_info["info_groups"] or {}) do
            for secnum, section in pairs (grinfo["sections"] or {}) do
               if (section["mmgModObjName"] == mngModObjName) and section["sectionId"] == sectId then
                   ing.utils.logMessage("mmx-cli",  "Found section ", sectId, " for object ", mngModObjName)
                   return section
               end
            end
    end
    
    ing.utils.logMessage("mmx-cli", "Cannot find section for object ", mngModObjName)
    return {}
end

--[[ ---------------------------------------------------------------
     Function returns properties (as Lua table) for specified parameter of
     specifiled management object
     Param info is selected from the global mmx_web_info table.
-- -----------------------------------------------------------------]]
local function getParaminfo(mngModObjName, paramName, sectId)

    local paramInfo = nil
    --ing.utils.logMessage("mmx-cli", "getParaminfo","Obj Name:", mngModObjName, ", ParamName:", paramName)
    
	local section = getObjSection(mngModObjName, sectId)
   --ing.utils.logMessage("mmx-cli",  "Found section for object ", mngModObjName, "section id ", sectId)
     
   for _, pInfo in ipairs (section["paramList"]) do
	   --ing.utils.logMessage("mmx-cli",  "Checking param name ", pInfo["param_name"])
	   if  pInfo["param_name"] == paramName then
		   paramInfo = pInfo
		   break
	   end
   end
		   
   return paramInfo
    
end

--[[
    Function returns Management Model object name bi object instance
    For example:
      input instance name: Device.Users.User.4. or Device.Users.User.*.
      output object name: device.Users.User.{i}.
--]]
local function getObjNameByInstance(instName)

    objname = nil
    objname = string.gsub(instName, "([^%.]+)%.",
                 function (mystr)
                     if string.match(mystr, "^%a+[%w_]*$") ==nil then return "{i}."
                     else return nil end
                 end  )
   --ing.utils.logMessage("mmx-cli","getObjNameByInstance", "inst name: ", instName,
   --                     "object name: ", objname)
   return  objname
end

--[[ ----------------------------------------------------------------
--   Function get pre-define values for all params of the object
--    Input params:
--       mngModObjName - object
--    (for example Device.Ethernet.Interface.{i}.)
--
--    Returns:
--       PreDefValArray - array of tables with pre-define values
--              for each parameter, if no pre-def values for a parameter,
--              "nil" is placed in the resulting array
-- ----------------------------------------------------------------]]
local function getPreDefValArray(mngModObjName, sectId)
    local PreDefValArray = {}
    local parName
    local section = getObjSection(mngModObjName, sectId)
    
    local plist = section["paramList"]
 
    for _, paramInfo in pairs(plist or {}) do
	     parName = paramInfo["param_name"]
	     if paramInfo["data_properties"] and paramInfo["data_properties"]["rules"] then
	        PreDefValArray[parName] = paramInfo["data_properties"]["rules"]["predef_values"] or nil
        end
    end

    return PreDefValArray
end

--[[ ----------------------------------------------------------------
--   Function extracts placeholder values from management object path
--    Input params:
--       resolvedPath - full resolved (without placeholders - {i}) path to management object
--    (for example "Device.Ethernet.Interface.1."")
--
--    Returns:
--       placeholders - list of placeholder values or empty list if given path doesn't contain them
--    (for example { "1" })
-- ----------------------------------------------------------------]]
local function extractPathPlaceholderValues(resolvedPath)
    local placeholders = {}

    local pathParts = ing.utils.split(resolvedPath, ".")
    for _, part in ipairs(pathParts) do
        local numberRepr = tonumber(part)
        if numberRepr then
            -- add only numbers to list of placeholders
            table.insert(placeholders, numberRepr)
        end
    end

    return placeholders
end

--[[ ----------------------------------------------------------------
--   Function replaces path placeholder(s) ({i}) with actual values.
--   Placeholders are replaced in order of following in list,
--   i.e., first placeholder is replaced with first value, second placeholder - with second value and so on
--    Input params:
--       path - full path to management object
--       placeholderValues - list of actual values of placeholders
--       resolveAnyPlaceholder - [Optional] if true indicates that "*" should be also resolved. Default value - false
--
--    Returns:
--       unchanged path - if given path doesn't contains placeholders;
--       path with placeholders replaced to actual values - if number of placeholder values is equal (or greater) of number of placeholders;
--       nil  - if path contains more placeholders than actual values
--
--       number of placeholders, which have been resolved or 0 if no placeholders were resolved
-- ----------------------------------------------------------------]]
local function resolvePathPlaceholders(path, placeholderValues, resolveAnyPlaceholder)
    local resolvedPath = path
    resolveAnyPlaceholder = resolveAnyPlaceholder or false

    local lastPlaceholderIdx = 0    -- index of last used placeholder

    for _, pathPart in ipairs(ing.utils.split(path, ".")) do
        if pathPart == "{i}" or (resolveAnyPlaceholder and pathPart == "*") then
            local unusedValue = placeholderValues[lastPlaceholderIdx + 1]

            if unusedValue == nil then
                -- path contains more placeholders than values
                ing.utils.logMessage("mmx-cli", string.format("Failed to resolve path [%s] with keys: %s", path, ing.utils.tableToString(placeholderValues)))
                return nil, 0
            end

            -- resolve first unresolved placeholder
            resolvedPath = string.gsub(resolvedPath, pathPart, unusedValue, 1)
            lastPlaceholderIdx = lastPlaceholderIdx + 1
        end
    end

    return resolvedPath, lastPlaceholderIdx
end

--[[ ----------------------------------------------------------------
--   Function retrieves paths of all indirect instances for given section
--    Input params:
--       section - Section information from mmx_web_info
--
--    Returns:
--       errorCode - non-zero error code indicates problem during interaction with EP
--       indirectPaths - Associative array of paths: key - indirect param name, value - array of all indirect object instances
-- ----------------------------------------------------------------]]
local function getIndirectParamPaths(section)
    local errorCode = ERROR_NO_ERROR
    local indirectPaths = {}

    for _, paramDef in ipairs(section["paramList"] or {}) do
        -- only indirect params of types I and III are applicable to CLI
        local indirectObjPath = paramDef["indirectObjName"]

        if indirectObjPath then
            -- we need to get all possible values of indirect param, so if index placeholder ("{i}") are present - replace to any placeholder ("*")
            indirectObjPath = string.gsub(indirectObjPath, "{i}", "*")

            indirectPaths[paramDef["param_name"]] = { indirectObjPath }
        end
    end

    ing.utils.logMessage("mmx-cli", "Indirect param paths: "..ing.utils.tableToString(indirectPaths).." ")
    return errorCode, indirectPaths
end

--[[ ----------------------------------------------------------------
--   Function retrieves values of all indirect params of given section
--    Input params:
--       section - Section information from mmx_web_info
--
--    Returns:
--       errorCode - non-zero error code indicates problem during interaction with EP
--       indirectPaths - Associative array of values: key - partial path to indirect object instance,
--                                                    value - map of all asked param names and their values
-- ----------------------------------------------------------------]]
local function getIndirectParamValues(section)
    -- get paths to all indirect params
    local errCode, indirectPaths = getIndirectParamPaths(section)
    if errCode ~= ERROR_NO_ERROR or next(indirectPaths) == nil then
        -- error occured or no indirect params are present
        return errCode, {}
    end

    -- table of paths and corresponding params to get for given path
    local pathParamTable = {}
    for paramName, allIndirectPaths in pairs(indirectPaths) do
        for _, indirectPath in pairs(allIndirectPaths) do
            local askedFields = pathParamTable[indirectPath] or {}

            -- add name of current param to one, we want to get
            table.insert(askedFields, paramName)
            pathParamTable[indirectPath] = askedFields
        end
    end

    -- get all required params for all paths with one complex GET request
    local errCode, errorList, response = mmx_api_wrapper:getMultipleInstances(pathParamTable)

    ing.utils.logMessage("mmx-cli", "Indirect param values: "..ing.utils.tableToString(response).." ")
    return errCode, response
end


--[[ -------------- verify_params_for_setting ------------------------
   The function verifies parameter values before setting them.
   Verification is performed according to the MMX management model.
   The function is used for "set" or "add" operations.
   Input:
     mmObjName - name of object
     sectId - section id (something like a global identifier of the section)
     paramTbl  - name-value table for parameters to be set
       For example:  mmObjName: "Device.Users.User.{i}."
                     paramTbl: {"Enable" = "true",  "Permissions" = "Guest"}
   Returns:
   rc code:
       true/false - verification is good/verification failed
   errmsg - error message in case of failure
       
   the input paramTbl is modified for those parameters having  pre-defined values
------------------------------------------------------------------------]]
local function verify_params_for_setting (mmObjName, sectId, paramTbl)

    local rc, errmsg = 0, ""
    local err
    local found = false
   
    local updatedParamTbl = {}
    local paramInfo = nil
    
    -- get section and param list of the object
    local section = getObjSection(mmObjName, sectId)
    if section == nil then
        return 9, "System section is not defined for object "..mmObjName
    end
    
    local plist = section["paramList"]
    local pinfo = nil
    for pname, pvalue in pairs(paramTbl or {}) do
        pinfo = getParaminfo(mmObjName, pname, sectId)
        
        if pinfo == nil then
            -- Impossible case, but we check it
           errmsg = "System definition error with parameter "..pname
           rc = 1
           break
        end

        if  pinfo["writable"] ~= true then
            errmsg = "Parameter "..pname.." is not writable"
            rc = 2
            break
        end
        
        if pinfo["rnd_type"] == "checkbox" then
            err, boolvalue = ing.utils.isBoolean(pvalue)
            if err ~= 0 then
                errmsg = "Bad value of boolean parameter, expected values are 'true', '1', 'false' or '0'"
                rc = 3
                break
            else
                if boolvalue == true then 
                    paramTbl[pname] = "true"
                else
                    paramTbl[pname] = "false"
                end
            end
        end

        if pinfo["rnd_type"] == "button" then
            err, boolvalue = ing.utils.isBoolean(pvalue)
            if err ~= 0 or boolvalue ~= true then
                errmsg = "Bad value of parameter, expected values are 'true' or '1' "
                rc = 3
                break
            else
                paramTbl[pname] = "true"
            end
        end
         
    if pinfo["data_properties"] and
        pinfo["data_properties"]["data_type"] == "enum" then
        
        predefTbl = pinfo["data_properties"]["rules"] and
                    pinfo["data_properties"]["rules"]["predef_values"]
            found, tmpStr = false, ""

            for realval, predefval in pairs(predefTbl) do
                tmpStr = predefval..","
                if predefval == pvalue then
                    found = true
                    --Update CLI param values by the "real" (not pre-defined) value
                    paramTbl[pname] = realval
                end
            end
            if not found and tmpStr == "" then
                errmsg = "Bad value of enum parameter, expected values: "..tmpStr
                errmsg[#errmsg]="" --remove the last comma
                rc = 4
                break;
            end
        end
        
        if pinfo["data_properties"] and
            pinfo["data_properties"]["data_type"] == "integer" then

            -- TODO check range of integer parameters

        end
    end

    return rc, errmsg
end


--  ---------------------------------------------------------------
--          Functions for print results of CLI commands
--  ----------------------------------------------------------------
--[[ ------------------ buildResRows ------------------------------
--   Function is used for the "get" operation.
--   It creates Lua table with parameter names used as a header row
--      of resulting table that is output on the CLI terminal screen.
--   Function returns array of responces and array of headers of object
--    Input params:
--     mmObjInstance - object instance (for ex: Device.Ethernet.Interface.2.)
--
--    Returns:
--       resRows 	- array of responces from API
--       objHeaders	- array of headers

-- TODO: current version of this function supports show all instances only,
-- we need to implement show by specific index or index range
-- -------------------------------------------------------------------]]
local function buildResRows(mmObjInstance, sectId )
    local objParams = {}
    local objHeaders = {}
    local errorlist, responseRows = {}
    local errorcode = 0
    local resRows, instList, sortRow = {}, {}, {}

    -- get section for the object
    local mngModObjName = getObjNameByInstance(mmObjInstance)
    local section = getObjSection(getObjNameByInstance(mmObjInstance), sectId)

    local isPlaceHolder = string.match(mngModObjName, "%.[%*%d%[%]%-{i}]+%.")
    if isPlaceHolder ~= nil then
        errorcode, instList = getInstList(mmObjInstance)
        if errorcode ~= ERROR_NO_ERROR then
            return errorcode, nil, nil
        end
    else
        instList[1] = mmObjInstance
    end

    --get predefine values for the object
    local preDefValArray = getPreDefValArray(mngModObjName, sectId)

    -- get indirect params values for section
    local indirectValues = {}
    errorcode, indirectValues = getIndirectParamValues(section)
    if errorcode ~= ERROR_NO_ERROR then
        return errorcode, nil, nil
    end

    -- get arrays of parameters names and parameters header
    for key, param in pairs(section["paramList"] or {}) do
        objParams[#objParams + 1] = param["param_name"]
        objHeaders[#objHeaders + 1] = param["rnd_header"]
    end

    --Generate rows for output table
    for _, objInst in pairs(instList or {}) do
        --get array contains names and values for every parameter of the instance
        errorcode, errorlist, responseRows = mmx_api_wrapper:getInstance(objInst, objParams)
        --ing.utils.logMessage("mmx-cli", "Response from get wrapper: errcode", errcode,
        --                      "\n",ing.utils.tableToString(responseRows))

        if (errorcode > ERROR_NO_ERROR and errorcode <= MAX_EXTERNAL_ERROR) then
            return errorcode, nil, nil
        end

        sortRow = {}
        for _, paramDef in pairs(section["paramList"]) do
            local paramName = paramDef["param_name"]
            local indirectObjName = paramDef["indirectObjName"]

            local resVal = responseRows[paramName]

            if indirectObjName then
                -- get keys (values of placeholders), which identify this object instance
                local rowKeys = extractPathPlaceholderValues(objInst)

                -- build path of indirect object instance, which corresponds to given main object instance
                local resolvedIndirectPath = resolvePathPlaceholders(indirectObjName, rowKeys)

                if resolvedIndirectPath and indirectValues[resolvedIndirectPath] and indirectValues[resolvedIndirectPath][paramName] then
                    resVal = indirectValues[resolvedIndirectPath][paramName]
                end

                ing.utils.logMessage("mmx-cli", string.format("For section row [%s] value of indirect param [%s] was set to [%s] (indirect path - %s)",
                                    objInst, paramName, tostring(resVal), resolvedIndirectPath))
            end

            if resVal ~= nil and preDefValArray ~= nil and preDefValArray[paramName] then
                resVal =  preDefValArray[paramName][resVal]
                --ing.utils.logMessage("mmx-cli","ParamName:",paramName,", resVal:", resVal,
                --    ", preDefValArray[paramName] =", ing.utils.tableToString(preDefValArray[paramName]))
            end

            -- Save value of parameter for output (accroding to the order
            -- specified in objParams )
            sortRow[#sortRow +1] = resVal or ""
            --ing.utils.logMessage("mmx-cli", "paramName:",paramName,", resVal:", resVal)
        end
        --collect all rows in one table
        table.insert(resRows, sortRow)
    end
    return errorcode, resRows, objHeaders
end

--[[ -----------------------------------------
--   Function returns array max width for every column in table
--    Input params:
--       tbl		- array of rows
--       headers	- array of headers
--
--    Returns:
--       width	- array of column widths
-- ------------------------------------------]]
local function widths(tbl, headers)
    local width = {}
    for i, hdr in ipairs(headers or {}) do
        width[i] = #hdr
        --width[i] = hdr:len()
    end

    for _, row in pairs(tbl or {}) do
        for i, val in ipairs(row or {}) do
            width[i] = math.max(width[i], #val)
            --width[i] = math.max(width[i], val:len())
        end
    end
    return width
end

--[[ -----------------------------------------
--   Function draw table on CLI
--    Input params:
--       tbl		- array of rows
--       headers	- array of headers
--
-- ------------------------------------------]]
local function drawTable(tbl, headers)
    local colDelim = " | "	--Column delimeter

    local width = widths(tbl, headers)

        -- format content of rows for output by add pads for each val
        local function formatRow(row)
            local fRow = {}
            for i, attr in ipairs(row or {}) do
                --table.insert(fRow, tostring(attr)..string.rep(" ", width[i] - attr:len()))
                table.insert(fRow, tostring(attr)..string.rep(" ", width[i] - #attr))
            end
            return table.concat(fRow, colDelim)
        end

        -- create array of horizontal lines per column
        local function horizontalLine()
            local dash = {}
            for i, wdth in ipairs(width or {}) do
                table.insert(dash, string.rep("-", wdth))
            end
            return table.concat(dash, colDelim)
        end

        local output = { formatRow(headers), horizontalLine() }
        for i, row in ipairs(tbl or {}) do
            table.insert(output, formatRow(row))
        end

        -- print headers, horizontal line and rows on cli
        for key, line in pairs (output or {}) do
            print(line)
        end
end

--[[ -----------------------------------------
-- ------------------------------------------]]
local function maxWidth(words)
    local max = 0
    for _, w in ipairs(words or {}) do
        max = math.max(max, w:len())
    end
    return max
end

--[[ -----------------------------------------
-- ------------------------------------------]]
local function wrap(words, width)
    local delim = "  "
    local len = 0
    local text = {}
    local line = {}
		
    local function formatLine(line)
        local str = table.concat(line, delim)
        return str..((" "):rep(width - str:len()))
    end

    for i, word in ipairs(words or {}) do
        if len + word:len() <= width then
            len = len + word:len() + delim:len()
            table.insert(line, word)
        else
            table.insert(text, formatLine(line))
            line = {}
            len = 0
            len = len + word:len() + 1
            table.insert(line, word)
        end

    end
    table.insert(text, formatLine(line))
    return text
end

--[[ -----------------------------------------
-- ------------------------------------------]]
local function concatColumns(lines1, lines2)
    local text = {}
    local delta = #lines2 - #lines1

    local function genFill(lines)
        local minWidth = 100000
        for _, line in ipairs(lines or {}) do
            minWidth = math.min(minWidth, line:len())
        end
        return (" "):rep(minWidth)
    end
        
    if delta > 0 then
        local fill = genFill(lines1)
        for i=1, delta do
             table.insert(lines1, fill)
        end
    elseif delta < 0 then
        fill = genFill(lines2)
        for i=1, -delta do
            table.insert(lines2, fill)
         end
    end
        
    for i=1, #lines1 do
        table.insert(text, lines1[i]..keysDelim..lines2[i])
    end
    return text
end

--[[ -----------------------------------------
--   Function print table on CLI
--    Input params:
--       tbl		- array of rows
--       headers	- array of headers
--
-- ------------------------------------------]]
local function printTableAsText(tbl, headers, screenWidth)
    local keyLines = {}
    local valLines = {}
    local output = {}
    
    -- Create two arrays.
    -- first contain the key value of the table (it is first parameter - index)
    -- second contain secondary parameters
    for rowNum, row in ipairs(tbl or {}) do
        local keyCol = {}
        local valCol = {}
        for key, val in pairs (tbl[rowNum] or {}) do
            if key == 1 then
                table.insert(keyCol, headers[key]..": "..val)
            else
                table.insert(valCol, headers[key]..": "..val)
            end

        end
        table.insert(keyLines, keyCol)
        table.insert(valLines, valCol)
    end

    for i=1, #valLines do
        local keyLine = keyLines[i] or {}
        local valLine = valLines[i] or {}
        local keyWidth = maxWidth(keyLine)
        
        -- Concatenate arrays of key and secondary values like two columns of table.
        local text = concatColumns(wrap(keyLine, keyWidth), wrap(valLine, screenWidth - keyWidth - keysDelim:len()))
            for _, l in ipairs(text or {}) do
                table.insert(output, l)
            end
            table.insert(output, "")
    end

    -- print text with parameters name and value on cli
    for key, val in pairs (output or {}) do
        print(val)
    end
end


--[[ -----------------------------------------
-- ------------------------------------------]]
local function tblWidth(tbl, headers)
    local wid = widths(tbl, headers)
    local total = 0
    for _, w in ipairs(wid or {}) do
        total = total + w
    end
    total = total + #headers*3 - 1
    return total
end

--[[ -----------------------------------------
-- ------------------------------------------]]
local function printToCli(tbl, headers)

    local size = nil
    local screenHeight, screenWidth = 0, 0
    --redefine output format when MMX_CLI_FORCE_TABLE=1
    local forceShowTable = os.getenv('MMX_CLI_FORCE_TABLE')
    
    --get height and width (i.e. rows and columns) of terminal screen
    local pipe = io.popen("stty size 2>/dev/null")
    size = pipe:read("*line")
    pipe:close()

    if size then
		local rows, columns = string.match(size, "(%d+) +(%d+)")
		screenHeight = tonumber(rows)
		screenWidth  = tonumber(columns)
	end
	
	--If we couldn't determine screen size, set default values (24 rows, 80 col)
    if screenWidth <= 0 then screenWidth = 80 end
    if screenHeight <= 0 then screenHeight = 24 end

    -- if table`s width is greater then screen width, print the info as text
    -- otherwise draw a table
    if tonumber(tblWidth(tbl, headers)) > screenWidth and forceShowTable ~= "1" then
        printTableAsText(tbl, headers, screenWidth)
    else
        drawTable(tbl, headers)
    end
end

--==================================================================================
--
--MAIN CODE
--
--==================================================================================
	--TODO ERROR CODES
	local CLI_INPUT_PARAM_ERROR = 21
	local CLI_UTILS_PARAM_ERROR = 22
	
	local errcode, errmsg = 0, ""
	local response, resRows, resHdrs

	-- Create mmx entry-point API wrapper
	mmx_api_wrapper = {}
	mmx_api_wrapper = MMXAPIWrapper.create(cli_callerid)

    -- Convert script's input params from string to table and verify them
	local arg_hash = arg2hash()
	ing.utils.logMessage("mmx-cli","------ New CLI request (type ", arg_hash["type"], ")------")
	ing.utils.logMessage("mmx-cli", "Script input parameters:\n", ing.utils.tableToString(arg_hash))

	if arg_hash and arg_hash["mmObjInstance"] == nil then
		ing.utils.logMessage("mmx-cli", "ERROR: Mgmt object instance is not specified")
		print("ERROR: Bad format of input parameters")
		os.exit(CLI_UTILS_PARAM_ERROR)
	end

	if arg_hash["type"] ~= "get" and arg_hash["type"] ~= "set" and
	   arg_hash["type"] ~= "add" and arg_hash["type"] ~= "del" and
	   arg_hash["type"] ~= "update" then
		  ing.utils.logMessage("mmx-cli", "ERROR: Unknown operation type -",arg_hash["type"])
		  print("ERROR: Unknown operation type")
		  os.exit(CLI_UTILS_PARAM_ERROR)
	end
	
	--Create table with object's parameters
	cliParamsTable = {}
	if arg_hash["cliParamsStr"] ~= nil then
		assert(loadstring("cliParamsTable={"..arg_hash["cliParamsStr"].."}"))()
    end
    ing.utils.logMessage("mmx-cli", "Object's parameters:\n",ing.utils.tableToString(cliParamsTable))

    -- Keep identifier of the rendering section
    local sectId = arg_hash["sectionId"]

    -- Determine mgmt model object name
    local mmObjInst = arg_hash["mmObjInstance"]
    local mmObjName = getObjNameByInstance(mmObjInst)

    -- If index range is specified as [[x-y]] (x, y are numbers) replace it to [x-y]
    mmObjInst = string.gsub(mmObjInst, "%[%[", "%[")
    mmObjInst = string.gsub(mmObjInst, "%]%]", "%]")

	if arg_hash["type"] == "get" then
		errcode, resRows, resHdrs = buildResRows(mmObjInst, sectId)
		if errcode == ERROR_NO_ERROR then
		    printToCli(resRows, resHdrs)
		    os.exit(ERROR_NO_ERROR)
		else
		    print("Operation failed - errcode: "..errcode)
		    ing.utils.logMessage("mmx-cli", "GET operation failed with error:", errcode)
		    os.exit(errcode)
		end
	end
	
	if arg_hash["type"] == "update" then
	
		errcode, response = mmx_api_wrapper:discoverConfig(mmObjName)
		if errcode == ERROR_NO_ERROR then
		    os.exit(ERROR_NO_ERROR)
		else
		    print("Operation failed - errcode: "..errcode)
		    ing.utils.logMessage("mmx-cli", "Refresh operation failed with error:", errcode)
		    os.exit(errcode)
		end
	end

	if arg_hash["type"] == "set" then
	    local setType = 3 -- "apply"(1) and "save"(2)
	    
		if cliParamsTable == {} then
			print("ERROR: No input parameters for 'set' operation")
			os.exit(CLI_INPUT_PARAM_ERROR)
		end

        errcode, errmsg = verify_params_for_setting (mmObjName, sectId, cliParamsTable)
        if errcode == 0 then
		    errcode, response = mmx_api_wrapper:setParamValue(mmObjInst,setType,
		                                                      cliParamsTable)
		    --ing.utils.logMessage("mmx-cli","Response of set req\n",
		    --                        ing.utils.tableToString(response))
		end

	elseif arg_hash["type"] == "add" then
	    -- mmObjInst and mmObjName for "add" don't contain the last index and {i}
	    -- here we add the placeholder to the end of the obj name
		errcode, errmsg = verify_params_for_setting (mmObjName.."{i}.", sectId, cliParamsTable)
        if errcode == 0 then
			ing.utils.logMessage("mmx-cli", " cliParamsTable:\n", ing.utils.tableToString(cliParamsTable))
			errcode, response = mmx_api_wrapper:addInstance(mmObjInst, cliParamsTable)
		end

	elseif arg_hash["type"] == "del" then
		errcode, response = mmx_api_wrapper:deleteInstance(mmObjInst)
				   
	end

	if errcode == 0 then
		if response.hdr.resCode == "0" then
			print("Operation completed successfully")
			os.exit(ERROR_NO_ERROR)
		else
			print("Operation failed - received errcode "..response.hdr.resCode)
			os.exit(tonumber(response.hdr.resCode))
		end
	else
	    local outputStr = "Operation failed - errcode: "..errcode
	    if #errmsg > 0 then
	        outputStr = outputStr .." "..errmsg
	    end
		print(outputStr)
		os.exit(errcode)
	end


--  ----------------- End of main chunk code ------------------------------
