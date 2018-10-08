local CONFIG        = require("config")
local ERRNO         = require("errno") 
local common        = require("common")
local LOG           = require("log")

local cjson         = require("cjson.safe")

local LAPI_NAME = "relation"

local function GT0(fee)
    if fee > 0 then
        return true
    else
        return false
    end
end

local base_param = {
    { name = "appid", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "sign", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "role", pattern = {0, 1}, type = "number"},
    { name = "userid", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "random", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "auth", pattern = ".+", length = {1, 64}, type = "string"},
}

local opt_param = {
    { name = "page", pattern = GT0, type = "number", default = 1},
    { name = "pagesize", pattern = GT0, type = "number", default = 20},
}

local GET_MASTER = "select * from " .. CONFIG.DB_RELATION .. " where app_id = %s and user_id = %s;"
local GET_PRENTICE = "select user_id, bind_time from " .. CONFIG.DB_RELATION .. " where app_id = %s and master_id = %s order by bind_time desc limit %d offset %d;"

local function handle(req, sql, rate_config)
    local appid     = req["appid"]
    local userid    = req["userid"]
    local page      = req["page"]
    local pagesize  = req["pagesize"]

    local master = string.format(GET_MASTER, sql:escape_literal(appid), sql:escape_literal(userid))
    local master_res, master_err = sql:query(master)
    LOG.DEBUG(master_err, master_res)

    if not master_res then
        LOG.DEBUG("master info read error: " .. master_err)
        return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
    end

    local list = {}

    local master_id
    if #master_res == 0 then 
        master_id = nil
    else
        master_id = master_res[1].master_id
        table.insert(list, master_id)
    end

    local offset = (page - 1) * pagesize
    local prentice = string.format(GET_PRENTICE, sql:escape_literal(appid), sql:escape_literal(userid), pagesize, offset)
    local prentice_res, prentice_err = sql:query(prentice)
    LOG.DEBUG(prentice_err, prentice_res)

    if not prentice_res then
        LOG.DEBUG("prentice info read error: " .. prentice_err)
        return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
    end 

    local bind_time = {}
    local prentices
    if #prentice_res == 0 then
        prentices = nil
    else
        for i = 1, #prentice_res do
            local p = prentice_res[i]
            if p.user_id and p.bind_time then
                table.insert(list, p.user_id)
                bind_time[p.user_id] = p.bind_time
            end
        end
    end

    if #list == 0 then
        return {code = 0}
    end

    local result = common.get_user_info(list)
    if not result then
        LOG.DEBUG("get_user_info error")
        return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
    end

    local master_out
    local prentices_out = {}
    for key, val in pairs(result) do
        if key == master_id then
            master_out = val
        else
            val.bindtime = bind_time[key]
            table.insert(prentices_out, val)
        end
    end

    local err
    local master_str
    if master_out then
        master_str, err = cjson.encode(master_out)
        if not master_str then
            LOG.ERROR("master json encode error: " .. err)
            return common.ERROR(ERRNO.JSON_ENCODE_ERROR)
        end
    end

    local prentice_str
    if #prentices_out > 0 then
        prentices_str, err = cjson.encode(prentices_out)
        if not prentices_str then
            LOG.ERROR("prentices json encode error: " .. err)
            return common.ERROR(ERRNO.JSON_ENCODE_ERROR)
        end
    end


    local ret = {
        code = 0,
        master = master_str,
        prentices = prentices_str,
    }

    return ret
end

common.main(handle, LAPI_NAME, base_param, opt_param)
