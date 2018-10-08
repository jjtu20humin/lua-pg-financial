local CONFIG        = require("config")
local ERRNO         = require("errno") 
local common        = require("common")
local LOG           = require("log")
local finance       = require("finance")

local LAPI_NAME = "record"

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
    { name = "userid", pattern = ".+", length = {1, 64}, type = "string"},    
    { name = "random", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "auth", pattern = ".+", length = {1, 64}, type = "string"},
}

local opt_param = {
	{ name = "page", pattern = GT0, type = "number", default = 1},
    { name = "pagesize", pattern = GT0, type = "number", default = 20},
    { name = "dealtype", type = "number" },
    { name = "source", type = "number" },
    { name = "starttime", pattern = GT0, type = "number" },
    { name = "endtime", pattern = GT0, type = "number" },
}

local function handle(req, pgsql, rate_config)
	return finance.record( req, pgsql)
end

common.main(handle, LAPI_NAME, base_param, opt_param)
