-- @author: qianye@droi.com
-- @brief: 通用函数

local CONFIG        = require("config")
local ERRNO         = require("errno") 
local LOG           = require("log")
local ERRINFO       = require(CONFIG.LANG)

local cjson         = require("cjson.safe")

local _M = {}

function _M.ERROR(errno)
    local msg = ERRINFO[errno]

    local err = {
        code = errno, 
        msg = msg,
    }

    return err
end

function _M.ERROR_INFO(errno)
    local info = ERRINFO[errno] or "UNKNOW ERROR"
    return info
end

function _M.urldecode(str)
    str = string.gsub(str, '+', ' ')
    str = string.gsub(str, '%%(%x%x)', function(h)
        return string.char(tonumber(h, 16))
    end)
    str = string.gsub(str, '\r\n', '\n')
    return str
end

function _M.urlencode(str)
    if str then
        str = string.gsub(str, '\n', '\r\n')
        str = string.gsub(str, '([^%w])', function(c)
            return string.format('%%%02X', string.byte(c))
        end)
    end
    return str
end

function _M.split(s, c)
	if not s then return nil end

	local m = string.format("([^%s]+)", c)
	local t = {}
	local k = 1
	for v in string.gmatch(s, m) do
		t[k] = v
		k = k + 1
	end
	return t
end

local pgmoon = require("pgmoon")

local function pgsql()
    local pg = pgmoon.new({
        host        = CONFIG.PG_HOST,
        port        = CONFIG.PG_PORT,
        database    = CONFIG.PG_DBNAME,
        user        = CONFIG.PG_USER,
        password    = CONFIG.PG_PASSWORD,
    })

    local success, err = pg:connect()
    if success then
        return pg, nil
    else
        LOG.ERROR("sql connect error: " .. err)
        return nil, err
    end
end

local function check_sign(req, sql)
    local appid = sql:escape_literal(req["appid"])
    local sign  = sql:escape_literal(req["sign"])

    local query = string.format(CONFIG.PG_CHECK_SIGN, appid, sign)
    local result, err = sql:query(query)
    LOG.ERROR(err, result)
    if result then
        return 0
    else
        return ERRNO.ILLEGAL_SIGN
    end
end

local function param_check(req, param, isbase)
    for _, v in pairs(param) do
        local key = v.name
        local val = req[key]
        if isbase and val == nil then
            return ERRNO.REQ_PARAM_ERROR, "Param [" .. key .. "] must exist."
        end

        if type(val) == "nil" then
            if v.default then
                val = v.default
                req[key] = val
            end
        end

        if type(val) ~= "nil" then
            local pattern = v.pattern
            local ptype = v.type
            if type(val) ~= ptype then
                return ERRNO.REQ_PARAM_ERROR, "Param [" .. key .. "] must be " .. ptype ..  "."
            end

            local pattern_type = type(pattern)
            if pattern_type == "string" then
                local len = v.length or {0, 9999}
                local len_min = len[1] or 0
                local len_max = len[2] or 9999
                local val_len = string.len(val)

                if (val_len < len_min) or (val_len > len_max) then
                    local errmsg = "Parma [" .. key .. "] length = " .. val_len .. ", out of range [" .. len_min ..", " .. len_max .. "]."
                    return ERRNO.REQ_PARAM_ERROR, errmsg
                end

                local vmatch = string.match(val, v.pattern)
                if vmatch ~= val then
                    return ERRNO.REQ_PARAM_ERROR, "Param [" .. key .. "] value, has invalid charactors."
                end
            elseif pattern_type == "table" then
                local flag = false
                for i = 1, #pattern do
                    if val == pattern[i] then
                        flag = true
                        break
                    end
                end

                if not flag then
                    local ret, err = cjson.encode(pattern)
                    if ret then
                        return ERRNO.REQ_PARAM_ERROR, "Param [" .. key .. "] must be one of " .. ret .. "."
                    else
                        return ERRNO.REQ_PARAM_ERROR, "Param [" .. key .. "] is invalid."
                    end
                end
            elseif pattern_type == "function" then
                local ret = pattern(val)
                if not ret then
                    return ERRNO.REQ_PARAM_ERROR, "Param [" .. key .. "] is invalid."
                end
            end
        end
    end

    return 0, nil
end

local function check_param(req, base_param, opt_param)
    if not req then
        if base_param then
            return ERRNO.REQ_PARAM_ERROR, "Require parameters." 
        else
            return 0, nil
        end
    end

    local errno = 0
    local errmsg = nil
    if base_param then
        errno, errmsg = param_check(req, base_param, true)
        if errno < 0 then return errno, errmsg end
    end

    if opt_param then
        errno, errmsg = param_check(req, opt_param, false)
    end

    return errno, errmsg
end

---- insert into tab(fields) values(val);
function _M.fields_val( tab )
	if(not next(tab)) then
		return
	end
	local fields = {};
	local values = {};
	local val = "";
	for k ,v in pairs(tab) do
		table.insert(fields ,k);
		table.insert(values,v);
	end
	local len = #values;
	for k,v in pairs(values) do
		if (val~="") then
			val = val..','
		end
		if (type(v)=='number') then
			val = val..v;
		elseif(v=="NOW()") then
			val = val..'now()';
		else
			val = val..'\''..v..'\''
		end
	end
	return table.concat(fields ,",") ,val;
end

local bit = require("bit")

function _M.ID2STR(id)
    local tmp = bit.bxor(id, CONFIG.MAGIC_INTEGER)
    local hex = bit.tohex(tmp, -8)
    return hex
end


local function get_keys(tab)
    local keys = {} 
    for key, val in pairs(tab) do
        if key ~= "auth" and type(val) ~= "table" then
            table.insert(keys, key)
        end
    end

    return keys
end

local function gen_auth(req, app_key)
    local keys = get_keys(req)
    table.sort(keys)

    local auth = ""
    for i = 1, #keys do
        local key = keys[i]
        if auth and auth == "" then
            auth = key .. "=" .. req[key]
        else
            auth = auth .. "&" .. key .. "=" .. req[key]
        end
    end

    if app_key then
        LOG.DEBUG(auth .. "&key=" .. app_key)
        return string.upper(ngx.md5(auth .. "&key=" .. app_key))
    else
        LOG.DEBUG(auth)
        return string.upper(ngx.md5(auth))
    end
end

local function gen_random()
    math.randomseed(os.time())
    local rand = os.time() .. math.random()
    return ngx.md5(rand)
end

local function INPUT()
    ngx.req.read_body()
    local method = ngx.req.get_method()
    if method ~= "POST" then
        if method then
            LOG.DEBUG("unsupport http method: " .. method)
        else
            LOG.DEBUG("unknown http method")
        end

        return ERRNO.HTTP_METHOD_NOT_SUPPORT, nil
    end

    local body = ngx.req.get_body_data()
    if body then
        local param, err = cjson.decode(body)
        if param then
            return 0, param
        else
            LOG.ERROR("request body json decode error: " .. err)
            LOG.ERROR("request body json decode error(body): " .. body)
            return ERRNO.REQ_PARAM_DECODE_ERROR, nil
        end
    else
        return ERRNO.REQ_PARAM_EMPTY, nil
    end
end

local RES_PARAM_ERROR = '{"code":-20013,"msg":"返回参数错误"}'

local function OUTPUT(out, role, rate_config)
    if type(out) ~= "table" then
        LOG.ERROR("response is not a table")
        ngx.header["Content-type"] = "application/json;charset=utf-8";
        ngx.header["Content-Length"] = #RES_PARAM_ERROR;
        ngx.say(RES_PARAM_ERROR)
        return
    end

    out.random = gen_random()

    local auth
    if role == CONFIG.ROLE_SDK then 
        auth = gen_auth(out)
    else
        auth = gen_auth(out, rate_config.app_key)
    end

    out.auth = auth

    local output, err = cjson.encode(out)
    if output then
        ngx.header["Content-type"] = "application/json;charset=utf-8";
        ngx.header["Content-Length"] = #output;
        ngx.say(output)
    else
        LOG.ERROR("response body json encode error: " .. err)
        ngx.header["Content-type"] = "application/json;charset=utf-8";
        ngx.header["Content-Length"] = #RES_PARAM_ERROR;
        ngx.say(RES_PARAM_ERROR)
    end
end

local function SQL_DISCONNECT(sql)
    local success, errstr = sql:disconnect()
    if not success then
        LOG.ERROR("sql disconnect error: " .. errstr)
    end
end

local GET_RATE_CONFIG = "select * from fin_exrate_config where app_id = %s"

function _M.main(handle, name, base_param, opt_param)
    local errno, req = INPUT()
    if errno < 0 then
        local ret = _M.ERROR(errno)
        return OUTPUT(ret, CONFIG.ROLE_SDK)
    end

    local errmsg
    errno, errmsg = check_param(req, base_param, opt_param)
    if errno < 0 then 
        local ret = { code = errno, msg = errmsg }
        return OUTPUT(ret, CONFIG.ROLE_SDK)
    end

    local sql, err = pgsql()
    if not sql then
        LOG.ERROR("sql connect error: "  .. err)
        local ret = _M.ERROR(ERRNO.DB_CONNECT_ERROR)
        return OUTPUT(ret, CONFIG.ROLE_SDK)
    end

    local tzone, tzone_err = sql:query("set session timezone=PRC;")
    if not tzone then
        LOG.ERROR("sql set timezone error: "  .. tzone_err)
        local ret = _M.ERROR(ERRNO.INTERNAL_ERROR)
        SQL_DISCONNECT(sql)
        return OUTPUT(ret, CONFIG.ROLE_SDK)
    end

    local appid = req["appid"]
    local sign  = req["sign"]
    local role  = req["role"]

    local ROLE_CONFIG = CONFIG.ROLE_CONFIG
    if ROLE_CONFIG[name] then
        role = ROLE_CONFIG[name]
    end

    LOG.DEBUG(appid)

    local query = string.format(GET_RATE_CONFIG, sql:escape_literal(appid))
    local config, err = sql:query(query)
    LOG.DEBUG(err, config)

    if not config then
        LOG.ERROR("get rate config error: "  .. err)
        local ret = _M.ERROR(ERRNO.RATE_CONFIG_READ_ERROR)
        SQL_DISCONNECT(sql)
        return OUTPUT(ret, CONFIG.ROLE_SDK)
    elseif #config == 0 then
        LOG.ERROR("APPID[" .. appid .. "] not exist")
        local ret = _M.ERROR(ERRNO.APP_ID_NOT_EXIST)
        SQL_DISCONNECT(sql)
        return OUTPUT(ret, CONFIG.ROLE_SDK)
    end

    local rate_config = config[1]
    if not rate_config.signature then
        LOG.ERROR("APPID[" .. appid .. "] app signature not set")
        local ret = _M.ERROR(ERRNO.APP_SIGN_NOT_SET)
        SQL_DISCONNECT(sql)
        return OUTPUT(ret, CONFIG.ROLE_SDK)
    end

    if rate_config.signature ~= sign then       
        LOG.ERROR("APPID[" .. appid .. "] app signature[" .. sign .. "] not match")
        local ret = _M.ERROR(ERRNO.APP_SIGN_NOT_MATCH)
        SQL_DISCONNECT(sql)
        return OUTPUT(ret, CONFIG.ROLE_SDK)
    end

    if role == CONFIG.ROLE_SERVER and not rate_config.app_key then        
        LOG.ERROR("APPID[" .. appid .. "] app key not set")
        local ret = _M.ERROR(ERRNO.APP_KEY_NOT_SET)
        SQL_DISCONNECT(sql)
        return OUTPUT(ret, CONFIG.ROLE_SDK)
    end

    local auth
    if role == CONFIG.ROLE_SDK then 
        auth = gen_auth(req)
    else
        auth = gen_auth(req, rate_config.app_key)
    end

        LOG.DEBUG("auth")
        LOG.DEBUG(auth)
    if auth ~= req["auth"] then
        local ret = _M.ERROR(ERRNO.REQ_PARAM_AUTH_FAILED)
        SQL_DISCONNECT(sql)
        return OUTPUT(ret, CONFIG.ROLE_SDK)
    end

    local res = handle(req, sql, rate_config)
    SQL_DISCONNECT(sql)

    OUTPUT(res, role, rate_config)
end

local GV_SIGNKEY = "ZYK_ac17c4b0bb1d5130bf8e0646ae2b4eb4";
local BATCH_QUERY = "batch_query"
local CHECK_EXIST = "checkexists2"

local function request(name, str)
	ngx.req.set_header( "Accept" , "application/json;charset=UTF-8" );
	ngx.req.set_header( "Content-Type" , "application/x-www-form-urlencoded" );
	ngx.req.set_header( "Content-Length" , #str );

	local res = ngx.location.capture('/proxy/http/10.0.10.105/80/oauth/' .. name, {
		method = ngx.HTTP_POST,
		body = str,
	});

	return res;
end

function _M.check_userid(userid)
    if not userid then
        return false
    end

    local str = "openid=" .. userid .. "&sign=" .. ngx.md5(userid .. GV_SIGNKEY)

    local res = request(CHECK_EXIST, str)
    LOG.DEBUG(res.body)

    if res.status ~= 200 or res.truncated then
        return false
    end

    local ret, err = cjson.decode(res.body)
    LOG.DEBUG(res.status)
    LOG.DEBUG(res.body)
    if not ret then
        LOG.DEBUG("check_userid res.body decode error: " .. err)
        LOG.DEBUG("check_userid res.body: " .. res.body)
        return false
    end

    if ret.result ~= 0 then
        return false
    else
        return true
    end
end

function _M.get_user_info(users)
    local list, errstr= cjson.encode(users)
    if not list then
        LOG.DEBUG("get_user_info users list encode error: " .. errstr)
        return nil
    end

    local str = "list=" .. list .. "&sign=" .. ngx.md5(list .. GV_SIGNKEY)

    local res = request(BATCH_QUERY, str)
    LOG.DEBUG(res.status)
    LOG.DEBUG(res.body)
    if res.status ~= 200 or res.truncated then
        return nil
    end

    local ret, err = cjson.decode(res.body)
    if not ret then
        LOG.DEBUG("get_user_info res.body decode error: " .. err)
        LOG.DEBUG("get_user_info res.body: " .. res.body)
        return nil
    end

    if ret.result ~= 0 then
        return nil
    else
        return ret.list
    end
end

return _M
