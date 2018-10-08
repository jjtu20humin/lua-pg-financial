local CONFIG        = require("config")
local ERRNO         = require("errno") 
local common        = require("common")
local LOG           = require("log")
local finance       = require("finance")

local LAPI_NAME = "consume"

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
    { name = "fee", pattern = GT0, type = "number"},
    { name = "orderno", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "random", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "auth", pattern = ".+", length = {1, 64}, type = "string"},
}

local opt_param = {
    { name = "source", type = "number"},
    { name = "dealdesc", pattern = ".+", length = {1, 80}, type = "string"},
}

local function handle(req, pgsql, rate_config)
    return finance.consume( req , pgsql )
end

common.main(handle, LAPI_NAME, base_param,opt_param)
