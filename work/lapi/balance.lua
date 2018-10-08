local CONFIG        = require("config")
local ERRNO         = require("errno") 
local common        = require("common")
local LOG           = require("log")

local finance        = require("finance")

local LAPI_NAME = "balance"

local base_param = {
    { name = "appid", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "sign", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "userid", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "role", pattern = {0, 1}, type = "number"},
    { name = "random", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "auth", pattern = ".+", length = {1, 64}, type = "string"},
}

local opt_param = {
	{ name = "feetype", type = "number"},
}

local function handle(req , pgsql, rate_config)
	return finance.balance( req , pgsql )
end

common.main(handle, LAPI_NAME, base_param, opt_param)
