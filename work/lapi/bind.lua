local CONFIG        = require("config")
local ERRNO         = require("errno") 
local common        = require("common")
local LOG           = require("log")

local LAPI_NAME = "bind"

local base_param = {
    { name = "appid", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "sign", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "role", pattern = {0, 1}, type = "number"},
    { name = "userid", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "invitecode", pattern = ".+", length = {8, 8}, type = "string"},
    { name = "random", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "auth", pattern = ".+", length = {1, 64}, type = "string"},
}

local opt_param = {
}

local GET_BIND_INFO = "select * from " .. CONFIG.DB_RELATION .. " where app_id = %s and user_id = %s"
local GET_MASTER = "select * from " .. CONFIG.DB_RELATION .. " where app_id = %s and invitation_code = %s"
local GET_NEXT_ID = "select nextval('" .. CONFIG.DB_INVITE_CODE_SEQ .. "') id"
local INSERT_BIND_IFNO = "insert into " .. CONFIG.DB_RELATION .. " (app_id, user_id, invitation_code, master_id, bind_time) values (%s, %s, '%s', '%s', now())"
local UPDATE_BIND_INFO = "update " .. CONFIG.DB_RELATION .. " set master_id = '%s', bind_time = now() where app_id = %s and user_id = %s"

local function handle(req, sql, rate_config)
    local appid         = req["appid"]
    local userid        = req["userid"]
    local invitecode    = req["invitecode"]

    local query = string.format(GET_BIND_INFO, sql:escape_literal(appid), sql:escape_literal(userid))
    local res, err = sql:query(query)
    LOG.DEBUG(err, res)

    if not res then
        LOG.ERROR("bind info read error: " .. err)
        return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
    end

    if #res == 0 then
        if not common.check_userid(userid) then
            LOG.DEBUG("USERID[" .. userid .. "] not exist")
            return common.ERROR(ERRNO.USER_ID_NOT_FOUND)
        end

        local master = string.format(GET_MASTER, sql:escape_literal(appid), sql:escape_literal(invitecode))
        local master_res, master_err = sql:query(master)
        LOG.DEBUG(master_err, master_res)

        if not master_res then
            LOG.DEBUG("master info read error: " .. master_err)
            return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
        end

        if #master_res <= 0 then
            LOG.DEBUG("invite code not found")
            return common.ERROR(ERRNO.INVITE_CODE_NOT_FOUND)
        end

        local master_id = master_res[1].user_id
        if master_id == userid then
            LOG.DEBUG("can not bind self")
            return common.ERROR(ERRNO.CAN_NOT_BIND_SELF)
        end

        local nextid_res, nextid_err = sql:query(GET_NEXT_ID)
        LOG.DEBUG(nextid_err, nextid_res)
        if not nextid_res or #nextid_res < 0 then
            LOG.DEBUG("get nextval error: " .. nextid_err)
            return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
        end

        local id = nextid_res[1].id
        local invitecode = common.ID2STR(id)

        local insert = string.format(INSERT_BIND_IFNO, sql:escape_literal(appid), sql:escape_literal(userid), invitecode, master_id)
        local insert_res, insert_err = sql:query(insert)
        LOG.DEBUG(insert_err, insert_res)

        if not insert_res then
            LOG.ERROR("bind info insert error: " .. insert_err)
            return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
        end
        
        local ret = {
            code = 0,
            master = master_id,
        }

        return ret
    end

    local bind_info = res[1]
    if bind_info.master_id then
        LOG.ERROR("master already set")
        return common.ERROR(ERRNO.MASTER_ALREADY_SET)
    end

    local master = string.format(GET_MASTER, sql:escape_literal(appid), sql:escape_literal(invitecode))
    local master_res, master_err = sql:query(master)
    LOG.DEBUG(master_err, master_res)

    if not master_res then
        LOG.DEBUG("master info read error: " .. master_err)
        return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
    end

    if #master_res <= 0 then
        LOG.DEBUG("invite code not found")
        return common.ERROR(ERRNO.INVITE_CODE_NOT_FOUND)
    end

    local master_id = master_res[1].user_id
    if master_id == userid then
        LOG.DEBUG("can not bind self")
        return common.ERROR(ERRNO.CAN_NOT_BIND_SELF)
    end

    local update = string.format(UPDATE_BIND_INFO, master_id, sql:escape_literal(appid), sql:escape_literal(userid))
    local update_res, update_err = sql:query(update)
    LOG.DEBUG(update_err, update_res)

    if not update_res then
        LOG.ERROR("bind info update error: " .. update_err)
        return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
    end

    local ret = {
        code = 0,
        master = master_id,
    }

    return ret
end

common.main(handle, LAPI_NAME, base_param, opt_param)
