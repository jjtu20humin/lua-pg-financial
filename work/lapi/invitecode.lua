local CONFIG        = require("config")
local ERRNO         = require("errno") 
local common        = require("common")
local LOG           = require("log")

local LAPI_NAME = "invitecode"

local base_param = {
    { name = "appid", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "sign", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "role", pattern = {0, 1}, type = "number"},
    { name = "userid", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "random", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "auth", pattern = ".+", length = {1, 64}, type = "string"},
}

local opt_param = {
}

local GET_INVITE_CODE = "select * from " .. CONFIG.DB_RELATION .. " where app_id = %s and user_id = %s;"
local GET_NEXT_ID = "select nextval('" .. CONFIG.DB_INVITE_CODE_SEQ .. "') id;"
local INSERT_INVITE_CODE = "insert into " .. CONFIG.DB_RELATION .. " (app_id, user_id, invitation_code) values (%s, %s, '%s');"

local function handle(req, sql, rate_config)
    local appid     = req["appid"]
    local userid    = req["userid"]

    local query = string.format(GET_INVITE_CODE, sql:escape_literal(appid), sql:escape_literal(userid))
    local res, err = sql:query(query)
    LOG.DEBUG(err, res)

    if not res then
        LOG.ERROR("invite code read error: " .. err)
        return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
    end

    if #res == 0 then
        if not common.check_userid(userid) then
            LOG.DEBUG("USERID[" .. userid .. "] not exist")
            return common.ERROR(ERRNO.USER_ID_NOT_FOUND)
        end

        local nextid_res, nextid_err = sql:query(GET_NEXT_ID)
        LOG.DEBUG(nextid_err, nextid_res)
        if not nextid_res or #nextid_res < 0 then
            LOG.DEBUG("get nextval error: " .. nextid_err)
            return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
        end

        local id = nextid_res[1].id
        local invitecode = common.ID2STR(id)

        local insert = string.format(INSERT_INVITE_CODE, sql:escape_literal(appid), sql:escape_literal(userid), invitecode)
        local insert_res, insert_err = sql:query(insert)
        LOG.DEBUG(insert_err, insert_res)

        if not insert_res then
            LOG.ERROR("invite code insert error: " .. insert_err)
            return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
        end
        
        local ret = {
            code = 0,
            invitecode = invitecode,
        }

        return ret
    end

    local data = res[1]
    local ret = {
        code = 0,
        invitecode = data.invitation_code,
    }

    return ret
end

common.main(handle, LAPI_NAME, base_param, opt_param)
