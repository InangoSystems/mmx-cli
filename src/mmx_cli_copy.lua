#!/usr/bin/lua

--[[
#
# mmx_cli_copy.lua
#
# Copyright (c) 2013-2021 Inango Systems LTD.
#
# Author: Inango Systems LTD. <support@inango-systems.com>
# Creation Date: 11 Nov 2016
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
--]]

--[[
#----------------------------------------------------------------------------------------------------------
#  SUMMARY
#
#  This module prepare data for MMX Entry Point and start MMX copy commands.
#
#  Required source URI and destination URI
#  --------------------------------------------------------------------------------------------------------
#  |  Type                   |  Source                      |  Destination                                |
#  --------------------------------------------------------------------------------------------------------
#  |  CPU SW image loading:  |  tftp://<ipaddr>/<filename>  |  local://cpu_sw                             |
#  |                         |  ftp://<ipaddr>/<filename>   |  local://cpu_sw                             |
#  |  G.Fast FW loading:     |  tftp://<ipaddr>/<filename>  |  local://gfast_dfe_fw                       |
#  |                         |  ftp://<ipaddr>/<filename>   |  local://gfast_dfe_fw                       |
#  |  CPE FW loading:        |  tftp://<ipaddr>/<filename>  |  local://gfast_cpe_fw/<G.Fast line number>  |
#  |                         |  ftp://<ipaddr>/<filename>   |  local://gfast_cpe_fw/<G.Fast line number>  |
#  --------------------------------------------------------------------------------------------------------
#
#  Also can use key [status] as parameter without source and destination URI to get copy operation status
#  or [cancel] to cancel current copy operation
#
#  Usage: mmx_copy_command.lua <source URI> <destination URI>
#         mmx_copy_command.lua status       - To get Copy Command status
#         mmx_copy_command.lua cancel       - To cancel current operation
#  --------------------------------------------------------------------------------------------------------
--]]

require("mmx/mmx-frontapi")
require("mmx/ing_utils")

------------------------------------------------------------------------
-- Some constants used by this code
------------------------------------------------------------------------
local reqCallerId        = '1'
local reqTxaId           = '204799283'
local reqRespMode        = '0'
local reqMsgTypeGet      = 'GetParamValue'
local reqMsgTypeSet      = 'SetParamValue'
local reqMsgTypeDiscConf = 'DiscoverConfig'

local operationName      = 'Device.X_Inango_Copy.Operation.'
local historyName        = 'Device.X_Inango_Copy.History.*.'
local historyConfName    = 'Device.X_Inango_Copy.History.{i}.'

local directionSrc       = "Src"
local directionDst       = "Dst"

local reqFileName        = "FileName"
local reqHost            = "Host"
local reqProto           = "Proto"
local reqFileType        = "FileType"
local reqStart           = "Start"

local copyStatus         = "CopyStatus"

local histOperationId    = "OperationId"
local histErrorLog       = "ErrorLog"

local timeOut            = 5   -- timeout for waiting for answer from entry point

--[[--------------------------------------------------------------------
  Function name: parseURI

  Description:
      Validate and parse URI, storet data in table with keys:
                "proto" - protocol of current uri
                "host"  - host name
                "path"  - path to file
                "type"  - type of oparation

  Input parameters:
      URI

  Return:
      Table with parameters that fetched from URI

-------------------------------------------------------------------------]]
local function parseURI(uri)

    local proto = nil
    local host = ""
    local path = ""
    local ftype = ""

    local validURI = "^([^%d][^/?:#]+)://([^/?#*]+)/(.+)$"
    local localURI = "^(local)://([^:/?#*]+)/*(.*)$"

    proto, ftype, host = string.match(uri, localURI)
    if proto == nil then
        proto, host, path = string.match(uri, validURI)
    end

    if proto then
        local paramTable = {}
        paramTable["proto"] = proto
        paramTable["host"] = host
        paramTable["path"] = path
        paramTable["type"] = ftype
        return paramTable
    end

    return nil

end

--[[--------------------------------------------------------------------
  Function name: sendRequest

  Description:
        Send request to MMX Entry Point
  Input parameters:
        Table with request parameters
  Return:
        Result from Entry Point
-------------------------------------------------------------------------]]
local function sendRequest(request)

    local test_result, test_tab = mmx_frontapi_epexecute_lua(request,  timeOut) --timeout 5s

    return test_tab, test_result
end

--[[--------------------------------------------------------------------
  Function name: requestToStartCopyOperation

  Description:
      Take data from table (that created by parseURI function) and sending it to entry point
      to set data for copy operation and start operation

  Input parameters:
      Tables with data from src and dst URI

  Return:
      Result from entry point, table with answer data and result code

-------------------------------------------------------------------------]]

local function requestToStartCopyOperation(paramSrcUri, paramDstUri)

    local fe_request = {
        header={callerId   = reqCallerId,
                txaId      = reqTxaId,
                respMode   = reqRespMode,
                msgType    = reqMsgTypeSet,
        },
        body={
           setType = "1",
           paramNameValuePairs = {
               {name = operationName .. directionSrc .. reqFileName, value = paramSrcUri["path"]},
               {name = operationName .. directionSrc .. reqHost,     value = paramSrcUri["host"]},
               {name = operationName .. directionSrc .. reqProto,    value = paramSrcUri["proto"]},
               {name = operationName .. directionDst .. reqProto,    value = paramDstUri["proto"]},
               {name = operationName .. directionDst .. reqHost,     value = paramDstUri["host"]},
               {name = operationName .. directionDst .. reqFileName, value = paramDstUri["path"]},
               {name = operationName .. directionDst .. reqFileType, value = paramDstUri["type"]},
               {name = operationName .. reqStart, value = "true"},
           }
        }
    }
    return sendRequest(fe_request)
end

--[[--------------------------------------------------------------------
  Function name: requestToUpdateCopyHistory

  Description:
      Send request to udate copy history

  Input parameters:
      None
  Return:
      Result from entry point, table with answer data and result code

-------------------------------------------------------------------------]]
local function requestToUpdateCopyHistory()

    local fe_request = {
        header={callerId   = reqCallerId,
                txaId      = reqTxaId,
                respMode   = '2',
                msgType    = reqMsgTypeDiscConf,
        },

        body={
            objName = historyConfName,
            nextLevel = true,
        }
    }
    return sendRequest(fe_request)

end

--[[--------------------------------------------------------------------
  Function name: requestToGetCopyInfo

  Description:
      Send request to get copy operation status

  Input parameters:
      None
  Return:
      Result from entry point, table with answer data and result code

-------------------------------------------------------------------------]]
local function requestToGetCopyInfo()

    local fe_request = {
        header={callerId   = reqCallerId,
                txaId      = reqTxaId,
                respMode   = reqRespMode,
                msgType    = reqMsgTypeGet,
        },

        body={
           setType = "1",
           paramNames = {
                {name = operationName},
                {name = historyName .. histOperationId},
                {name = historyName .. histErrorLog},
               },
            nextLevel = true,
        }
    }
    return sendRequest(fe_request)

end

--[[--------------------------------------------------------------------
  Function name: requestToCancelCopyOperation

  Description:
      Send request to cancel copy operation

  Input parameters:
      None
  Return:
      Result from entry point, table with answer data and result code

-------------------------------------------------------------------------]]
local function requestToCancelCopyOperation()

    local fe_request = {
        header={callerId   = reqCallerId,
                txaId      = reqTxaId,
                respMode   = reqRespMode,
                msgType    = reqMsgTypeSet,
        },

        body={
           setType = "1",
           paramNameValuePairs = {
                {name = operationName .. reqStart, value = "false"},
               },
        }
    }
    return sendRequest(fe_request)

end

--[[--------------------------------------------------------------------
  Function name: checkCopyStatus

  Description:
      Find copy status string in result table from entry point

  Input parameters:
      None
  Return:
      String with status

-------------------------------------------------------------------------]]
local function getCopyStatus()

    local statusTable = {}
    local copyStatusTable, result = requestToUpdateCopyHistory()
    if result ~= 0 then
        return 'Failed to update copy history (' .. result .. ')'
    end

    copyStatusTable, result = requestToGetCopyInfo()

    if result == 0 then
      for index, paramPairs in pairs(copyStatusTable["body"]["paramNameValuePairs"]) do
          if paramPairs["name"] == operationName .. copyStatus then
              statusTable['CopyStatus'] = paramPairs["value"]

          elseif paramPairs["name"] == operationName .. histOperationId then
              statusTable['OperationId'] = paramPairs["value"]
          end
      end

      for index, paramPairs in pairs(copyStatusTable["body"]["paramNameValuePairs"]) do
          if paramPairs["value"] == statusTable['OperationId'] then
              statusTable['HistoryIndex'] = string.match(paramPairs["name"], '^.+%d')

          elseif statusTable['HistoryIndex'] ~= nil and paramPairs["name"] == statusTable['HistoryIndex'] .. '.ErrorLog' then
              statusTable['ErrorLog'] = paramPairs['value']
          end
      end

      if statusTable['ErrorLog'] == nil then
          return statusTable['CopyStatus']
      end

      return statusTable['CopyStatus'] .. ' (' .. statusTable['ErrorLog'] .. ')'
    end

    return 'Failed to get copy status (' .. result .. ')'

end

--=====================================================================================================
-- Only for testing
local function showResult(test_tab)

    if test_tab then
        print (ing.utils.tableToString(test_tab))
    end
end
--=====================================================================================================

--------------------------------------------------------------------------------
-- Main chunk
--------------------------------------------------------------------------------

if arg[1] == "status" then
    local status = getCopyStatus()
    print(status)

elseif arg[1] == "cancel" then
    requestToCancelCopyOperation()

else
    local suri = arg[1]
    local duri = arg[2]
    local paramSrcUri = {}
    local paramDstUri = {}

    paramSrcUri = parseURI(suri)
    paramDstUri = parseURI(duri)
    if paramSrcUri and paramDstUri then
        local data, result = requestToStartCopyOperation(paramSrcUri, paramDstUri)
        print(result)

    else
        print("Invalid URI.")
    end
end
