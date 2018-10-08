-- @author: qianye@droi.com
-- @brief: 获取短信验证码

local Logger    = ngx
local cjson     = require("cjson.safe")

local _M = {}

local function log(level, msg, req, err)
    if not msg then return end

    local errmsg = "[MESSAGE]: " .. msg

    if req then
        errmsg = errmsg .. "[REQUEST]: " .. cjson.encode(req)
    end

    if err then
        errmsg = errmsg .. "[ERROR]: " .. cjson.encode(err)
    end

    Logger.log(level, errmsg) 
end

function _M.ERROR(msg, req, err)
    log(Logger.ERR, msg, req, err)
end

function _M.WARN(msg, req, err)
    log(Logger.WARN, msg, req, err)
end

function _M.INFO(msg, req, err)
    log(Logger.INFO, msg, req, err)
end

function _M.DEBUG(msg, req, err)
    log(Logger.DEBUG, msg, req, err)
end

return _M
