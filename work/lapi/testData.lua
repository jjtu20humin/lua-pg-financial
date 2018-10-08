--insert data
local CONFIG        = require("config")
local ERRNO         = require("errno")
local common        = require("common")
local LOG           = require("log")

local finance        = require("finance")

local base_param = {
    { name = "tab", pattern = ".+", length = {1, 64}, type = "string"},
    -- { name = "data", pattern = ".+", length = {1,1024}, type = "string"},
}

local opt_param = {
}

local function handle(req , pgsql)
	return finance.insertTest( req , pgsql )
    -- return {errorCode = 0}
end

common.main(handle, base_param, opt_param)
