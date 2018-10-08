-- @brief:  配置文件

local config = {
    LANG                    = "zh_cn",

    ROLE_SDK                = 0,
    ROLE_SERVER             = 1,
    ROLE_CONFIG             = {
        ["recharge"] = 1,
        ["consume"] = 1,
        ["exchange"] = 1,
        ["change"] = 1,
        ["convert"] = 1,
    },

    DEFAULT_APP_KEY         = "AJPYn8EBOFLur8m8Lusz7fckSPh1D28q4fVLMJ26",

    PG_HOST                 = "172.17.0.1",
    PG_PORT                 = "40011",

    PG_DBNAME               = "droi_fin_master",
    PG_USER                 = "usr_fin_master",
    PG_PASSWORD             = "111222",

    MAGIC_INTEGER           = 2654435769,

    DEAL_TYPE_MONEY         = 0,
    DEAL_TYPE_ACTIVITY      = 1,
    DEAL_TYPE_MASTER        = 2,
    DEAL_TYPE_CONSUME       = 3,
    DEAL_TYPE_EXCHANGE      = 4,

   
    DB_EXRATE_CONFIG_SEQ    = "fin_exrate_config_coin_id_seq",
    DB_DEAL_LOG_SEQ         = "fin_user_coins_deallog_id_seq",
    DB_INVITE_CODE_SEQ      = "ms_master_users_id_seq",


    DB_FEEDBACK_RATIO       = "ms_feedback_ratio_config",
    -- level
    -- ratio
    -- modify_time

    DB_RELATION             = "ms_master_users",
    -- id
    -- app_id
    -- user_id
    -- invitation_code
    -- master_id
    -- bind_time

    DB_EXRATE_CONFIG        = "fin_exrate_config",
    -- app_id
    -- app_key
    -- signature
    -- coin_id
    -- coin_name
    -- exchange_rate
    -- cach_deposit
    -- operator_id
    -- operate_time
    -- is_open
    
    DB_USER_COINS           = "fin_user_coins",
    -- user_id
    -- coin_id
    -- coin_num
    -- operate_time

    DB_DEAL_LOG             = "fin_user_coins_deallog",
    -- id
    -- user_id
    -- coin_id
    -- deal_type
    -- source
    -- description
    -- exchange_rate
    -- order_no
    -- deal_no
    -- deal_seq
    -- operator_id
    -- operate_time
    -- ip
    -- droi_coins_before
    -- droi_coins_after
    -- deal_coins_before
    -- deal_coins_after

}

return config
