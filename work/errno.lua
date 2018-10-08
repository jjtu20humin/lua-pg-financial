-- @author: qianye@droi.com
-- @brief:  错误代码

local ERRNO = {

    -- 服务器内部错误
    INTERNAL_ERROR              = -20000,

    -- 服务不可用
    SERVICE_UNAVAILABLE         = -20001,

    -- HTTP方法不支持
    HTTP_METHOD_NOT_SUPPORT     = -20002,

    -- 请求参数不得为空
    REQ_PARAM_EMPTY             = -20003,

    -- 请求参数解析错误
    REQ_PARAM_DECODE_ERROR      = -20004,

    -- 请求参数错误
    REQ_PARAM_ERROR             = -20005,

    -- 数据库连接错误
    DB_CONNECT_ERROR            = -20006,

    -- APPID不存在
    APP_ID_NOT_EXIST            = -20007,

    -- 比率配置数据库读取错误
    RATE_CONFIG_READ_ERROR      = -20008,

    -- APP签名未设置
    APP_SIGN_NOT_SET            = -20009,

    -- APP签名不匹配
    APP_SIGN_NOT_MATCH          = -20010,

    -- APP秘钥未设置
    APP_KEY_NOT_SET             = -20011,

    -- 参数校验失败
    REQ_PARAM_AUTH_FAILED       = -20012,



    -- 返回参数错误
    RES_PARAM_ERROR             = -20013,



    -- JSON解析错误
    JSON_DECODE_ERROR           = -20014,

    -- JSON编码错误
    JSON_ENCODE_ERROR           = -20015,



    -- 邀请码未找到
    INVITE_CODE_NOT_FOUND       = -20016,

    -- 用户不存在
    USER_ID_NOT_FOUND           = -20017,

    -- 该用户在当前APP里已设置过师傅
    MASTER_ALREADY_SET          = -20018,

    -- 内部操作失败
    INTERNAL_OP_FAILED          = -20019,

    -- 余额不足
    BALANCE_NOT_ENOUGH          = -20020,

    -- 未知货币类型
    UNKNOWN_COIN_TYPE           = -20021,

    -- 该订单号已经完成
    ORDER_REPEAT                = -20022,

    -- 自己不能做自己的师傅 
    CAN_NOT_BIND_SELF           = -20023,

};

return ERRNO
