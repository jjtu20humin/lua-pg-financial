local CONFIG        = require("config")
local ERRNO         = require("errno") 
local common        = require("common")
local LOG           = require("log")

local LAPI_NAME = "change"

local function GT0(fee)
    if fee > 0 then
        return true
    else
        return false
    end
end

local function ROLLBACK(sql)
    local rollback, err = sql:query("ROLLBACK;")
    if not rollback then
        LOG.DEBUG("ROLLBACK error")
    end
end

local base_param = {
    { name = "appid", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "sign", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "role", pattern = {0, 1}, type = "number"},
    { name = "userid", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "fee", pattern = GT0, type = "number"},
    { name = "feetype", type = "number"},
    { name = "orderno", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "random", pattern = ".+", length = {1, 64}, type = "string"},
    { name = "auth", pattern = ".+", length = {1, 64}, type = "string"},
}

local opt_param = {
    { name = "source", type = "number"},
    { name = "dealdesc", pattern = ".+", length = {1, 128}, type = "string"},
}

local GET_RATE_CONFIG = "select * from " .. CONFIG.DB_EXRATE_CONFIG .. " where coin_id = %d;"
local GET_USER_COIN = "select * from " .. CONFIG.DB_USER_COINS .. " where coin_id = %d and user_id = %s;"
local GET_NEXT_ID = "select nextval('" .. CONFIG.DB_DEAL_LOG_SEQ .. "') id;"
local GET_DEAL_LOG = "select * from " .. CONFIG.DB_DEAL_LOG .. " where operator_id = %s and order_no = %s;"

local function handle(req, sql, rate_config)
    local appid     = req["appid"]
    local userid    = req["userid"]
    local fee       = req["fee"]
    local feetype   = req["feetype"]
    local orderno   = req["orderno"]
    local source    = req["source"] or -1
    local dealdesc  = req["dealdesc"]
    local ip        = ngx.var.remote_addr

    -- 获取合作方货币与卓易币兑换比例
    local query = string.format(GET_RATE_CONFIG, feetype)
    local res, err = sql:query(query)
    LOG.DEBUG(err, res)

    if not res then
        LOG.ERROR("rate config read error: " .. err)
        return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
    end

    if #res <= 0 or res[1].is_open ~= 1 then
        LOG.ERROR("unknown coin type")
        return common.ERROR(ERRNO.UNKNOWN_COIN_TYPE)
    end

    -- 开启事务
    local begin, err = sql:query("BEGIN;")
    if not begin then
        LOG.ERROR("BEGIN error")
        return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
    end

    -- 查看appid，orderno是否交易过
    local deal = string.format(GET_DEAL_LOG, sql:escape_literal(appid), sql:escape_literal(orderno))
    local deal_res, deal_err = sql:query(deal)
    LOG.DEBUG(deal_err, deal_res)

    if not deal_res then
        ROLLBACK(sql)
        LOG.ERROR("deal log read error: " .. deal_err)
        return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
    end

    -- 防止重复交易，重放攻击
    if #deal_res > 0 then
        ROLLBACK(sql)
        LOG.ERROR("APPID[" .. appid .. "] ORDERNO[" .. orderno .. "] repeat")
        return common.ERROR(ERRNO.ORDER_REPEAT)
    end

    -- 查询userid，合作方币种余额
    local coin = string.format(GET_USER_COIN, feetype, sql:escape_literal(userid))
    local coin_res, coin_err = sql:query(coin)
    LOG.DEBUG(coin_err, coin_res)

    if not coin_res then
        ROLLBACK(sql)
        LOG.DEBUG("coin read error: " .. coin_err)
        return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
    end

    -- 余额不足
    if #coin_res <= 0 or coin_res[1].coin_num < fee then
        ROLLBACK(sql)
        LOG.DEBUG("balance not enough")
        return common.ERROR(ERRNO.BALANCE_NOT_ENOUGH)
    end

    local coin_num = coin_res[1].coin_num
    local coin_id = feetype
    local coin_rate = res[1].exchange_rate 
    local coin_droi = res[1].cash_deposit or 0
    local droi_num = fee / coin_rate

    -- 查询userid，当前币种余额
    local coin2 = string.format(GET_USER_COIN, rate_config.coin_id, sql:escape_literal(userid))
    local coin2_res, coin2_err = sql:query(coin2)
    LOG.DEBUG(coin2_err, coin2_res)

    if not coin2_res then
        ROLLBACK(sql)
        LOG.DEBUG("coin read error: " .. coin2_err)
        return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
    end

    local coin2_num = 0
    local have_record = false

    if #coin2_res <= 0 then
        coin2_num = 0
    else
        have_record = true
        coin2_num = coin2_res[1].coin_num 
    end
    local coin2_id = rate_config.coin_id
    local coin2_rate = rate_config.exchange_rate
    local coin2_droi = rate_config.cash_deposit or 0
    local coin2_num_incr = droi_num * coin2_rate 

    -- 生成流水号
    local nextid_res, nextid_err = sql:query(GET_NEXT_ID)
    LOG.DEBUG(nextid_err, nextid_res)
    if not nextid_res or #nextid_res < 0 then
        ROLLBACK(sql)
        LOG.DEBUG("get nextval error: " .. nextid_err)
        return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
    end

    local id = nextid_res[1].id
    local dealno = common.ID2STR(id)

	local tab = {
		order_no = orderno,
		deal_no = dealno,
		deal_type = CONFIG.DEAL_TYPE_EXCHANGE,
		source = source,
		deal_seq = 0,
		user_id = userid,
		coin_id = coin_id,
		exchange_rate = coin_rate,
		droi_coins_before = coin_droi,
		droi_coins_after = coin_droi - droi_num,
		deal_coins_before = coin_num,
		deal_coins_after = coin_num - fee,
		operator_id = appid,
		operate_time = 'NOW()',
		ip = ip,
		description = dealdesc,
	}
		
    local tab2 = {
		order_no = orderno,
		deal_no = dealno,
		deal_type = CONFIG.DEAL_TYPE_EXCHANGE,
		source = source,
		deal_seq = 0,
		user_id = userid,
		coin_id = coin2_id,
		exchange_rate = coin2_rate,
		droi_coins_before = coin2_droi,
		droi_coins_after = coin2_droi + droi_num,
		deal_coins_before = coin2_num,
		deal_coins_after = coin2_num + coin2_num_incr,
		operator_id = appid,
		operate_time = 'NOW()',
		ip = ip,
		description = dealdesc,
	}


    if have_record then
        local UPDATE_USER_COIN = [[
            update fin_user_coins set coin_num = coin_num - %d, operate_time = now() where coin_id = %d and user_id = %s;
            update fin_exrate_config set cash_deposit = %d where coin_id = %d;
            insert into fin_user_coins_deallog(%s) values(%s);
            update fin_user_coins set coin_num = coin_num + %d, operate_time = now() where coin_id = %d and user_id = %s;
            update fin_exrate_config set cash_deposit = %d where coin_id = %d;
            insert into fin_user_coins_deallog(%s) values(%s);
        ]]

        local keys, vals = common.fields_val(tab)
        local keys2, vals2 = common.fields_val(tab2)
        local update = string.format(UPDATE_USER_COIN, 
                                     fee, coin_id, sql:escape_literal(userid), 
                                     tab.droi_coins_after, coin_id,
                                     keys, vals, 
                                     coin2_num_incr, coin2_id, sql:escape_literal(userid),
                                     tab2.droi_coins_after, coin2_id,
                                     keys2, vals2)
        local update_res, update_err = sql:query(update)
        if type(update_err) ~= "number" then
            ROLLBACK(sql)
            LOG.ERROR("update error: " .. update_err)
            return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
        else
            local commit_res, commit_err = sql:query("COMMIT;")
            if not commit_res then
                ROLLBACK(sql)
                LOG.ERROR("commit error")
                return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
            end

            local ret = {
                code = 0,
            }

            return ret
        end
    else
        if not common.check_userid(userid) then
            ROLLBACK(sql)
            LOG.DEBUG("USERID[" .. userid .. "] not exist")
            return common.ERROR(ERRNO.USER_ID_NOT_FOUND)
        end

        local INSERT_USER_COIN = [[
            update fin_user_coins set coin_num = coin_num - %d, operate_time = now() where coin_id = %d and user_id = %s;
            update fin_exrate_config set cash_deposit = %d where coin_id = %d;
            insert into fin_user_coins_deallog(%s) values(%s);
            insert fin_user_coins(%s) values(%s);
            update fin_exrate_config set cash_deposit = %d where coin_id = %d;
            insert into fin_user_coins_deallog(%s) values(%s);
        ]]

        local value = {
            user_id = userid,
            coin_id = coin2_id,
            coin_num = coin2_num_incr,
            operate_time = "NOW()",
        }

        local keys, vals = common.fields_val(tab)
        local keys2, vals2 = common.fields_val(tab2)
        local value_keys, value_val = common.fields_val(value)
        local insert = string.format(INSERT_USER_COIN, 
                                     fee, coin_id, sql:escape_literal(userid), 
                                     tab.droi_coins_after, coin_id,
                                     keys, vals,
                                     value_keys, value_val,
                                     tab.droi_coins_after, coin2_id,
                                     keys2, vals2)
        local insert_res, insert_err = sql:query(insert)
        if type(insert_err) ~= "number" then
            ROLLBACK(sql)
            LOG.ERROR("update error: " .. insert_err)
            return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
        else
            local commit_res, commit_err = sql:query("COMMIT;")
            if not commit_res then
                ROLLBACK(sql)
                LOG.ERROR("commit error")
                return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
            end

            local ret = {
                code = 0,
            }

            return ret
        end
    end
end

common.main(handle, LAPI_NAME, base_param, opt_param)
