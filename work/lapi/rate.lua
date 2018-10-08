local CONFIG        = require("config")
local ERRNO         = require("errno") 
local common        = require("common")
local LOG           = require("log")

local LAPI_NAME = "rate"

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
    { name = "feetype", type = "number"},
    { name = "random", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "auth", pattern = ".+", length = {1, 64}, type = "string"},
}

local opt_param = {
}

local GET_RATE_CONFIG = "select * from " .. CONFIG.DB_EXRATE_CONFIG .. " where coin_id = %d;"

local function handle(req, sql, rate_config)
    local feetype   = req["feetype"]

    local query = string.format(GET_RATE_CONFIG, feetype)
    local res, err = sql:query(query)
    LOG.DEBUG(err, res)

    if not res then
        LOG.ERROR("rate config read error: " .. err)
        return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
    end

    if #res <= 0 then
        LOG.DEBUG("coin type error")
        return common.ERROR(ERRNO.UNKNOWN_COIN_TYPE)
    end

    local ret = {
        code = 0,
        selfrate = tostring(rate_config.exchange_rate),
        targetrate = tostring(res[1].exchange_rate),
    }

    return ret
end

common.main(handle, LAPI_NAME, base_param, opt_param)
