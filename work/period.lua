-- @author: qianye@droi.com
-- @brief: 返回时间区间

local CONFIG        = require(prefix .. "config")
local DroiTime      = Droi.Time.Time

local MDAYS = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
local SECONDS_PER_DAY = 24 * 60 * 60
local SECONDS_PER_HOUR = 60 * 60

local function get_mdays(year, month)
    if month == 2 then
        if ((year % 4 == 0 and year % 100 ~= 0) or
            (year % 100 == 0 and year % 400 == 0)) then
            return 29
        else
            return 28
        end
    end

    return MDAYS[month]
end

local _M = {}

function _M.month()
    local date = DroiTime.Now()
    local year = date:Year()
    local month = date:Month()
    local days = get_mdays(year, month)

    local start_time = DroiTime.Date(year, month, 0, 0, 0, 0, 0):Timestamp()
    local end_time = start_time + days * SECONDS_PER_DAY

    return start_time, end_time
end

function _M.monthdays()
    local date = DroiTime.Now()
    local year = date:Year()
    local month = date:Month()
    local days = get_mdays(year, month)

    local start_time = DroiTime.Date(year, month, 0, 0, 0, 0, 0):Timestamp()
    local end_time = start_time + SECONDS_PER_DAY
    
    local startperiod = {
        starttime = start_time,
        endtime = end_time,
    }

    local ret = {}
    table.insert(ret, startperiod)

    local lastendtime = end_time
    for i = 2, days do
        local period = {
            starttime = lastendtime,
            endtime = lastendtime + SECONDS_PER_DAY,
        }

        table.insert(ret, period)
        lastendtime = period.endtime
    end

    return ret
end

function _M.day()
    local date = DroiTime.Now()
    local year = date:Year()
    local month = date:Month()
    local day = date:Day()

    local start_time = DroiTime.Date(year, month, day, 0, 0, 0, 0):Timestamp()
    local end_time = start_time + SECONDS_PER_DAY

    return start_time, end_time
end

function _M.day7()
    local date = DroiTime.Now()
    local year = date:Year()
    local month = date:Month()
    local day = date:Day()

    local time = DroiTime.Date(year, month, day, 0, 0, 0, 0):Timestamp()
    local end_time = time + SECONDS_PER_DAY
    local start_time = time - SECONDS_PER_DAY * 6

    return start_time, end_time
end

function _M.day7days()
    local date = DroiTime.Now()
    local year = date:Year()
    local month = date:Month()
    local day = date:Day()

    local time = DroiTime.Date(year, month, day, 0, 0, 0, 0):Timestamp()
    local start_time = time - SECONDS_PER_DAY * 6
    local end_time = start_time + SECONDS_PER_DAY

     local startperiod = {
        starttime = start_time,
        endtime = end_time,
    }

    local ret = {}
    table.insert(ret, startperiod)

    local lastendtime = end_time
    for i = 2, 7 do
        local period = {
            starttime = lastendtime,
            endtime = lastendtime + SECONDS_PER_DAY,
        }

        table.insert(ret, period)
        lastendtime = period.endtime
    end

    return ret
end

function _M.hour1()
    local end_time = DroiTime.Now():Timestamp()
    local start_time = end_time - SECONDS_PER_HOUR

    return start_time, end_time
end

function _M.hour12()
    local end_time = DroiTime.Now():Timestamp()
    local start_time = end_time - 12 * SECONDS_PER_HOUR

    return start_time, end_time
end

function _M.hour24()
    local end_time = DroiTime.Now():Timestamp()
    local start_time = end_time - SECONDS_PER_DAY

    return start_time, end_time
end

function _M.getPeriodByType(periodtype)
    if periodtype == CONFIG.PERIOD_TODAY then
        return _M.day()
    elseif periodtype == CONFIG.PERIOD_YESTODAY then
        local start_time, end_time = _M.day()
        return start_time - SECONDS_PER_DAY, end_time - SECONDS_PER_DAY
    elseif periodtype == CONFIG.PERIOD_7DAY then
        return _M.day7()
    elseif periodtype == CONFIG.PERIOD_MONTH then
        return _M.month()
    end
end

function _M.getPeriodsByType(periodtype)
    local ret = {}
    if periodtype == CONFIG.PERIOD_TODAY then
        local start_time, end_time = _M.day()
        local period = {
            starttime = start_time,
            endtime = end_time,
        }
        table.insert(ret, period)
        return ret
    elseif periodtype == CONFIG.PERIOD_YESTODAY then
        local start_time, end_time = _M.day()
        local period = {
            starttime = start_time - SECONDS_PER_DAY,
            endtime = end_time - SECONDS_PER_DAY,
        }
        table.insert(ret, period)
        return ret
    elseif periodtype == CONFIG.PERIOD_7DAY then
        return _M.day7days()
    elseif periodtype == CONFIG.PERIOD_MONTH then
        return _M.monthdays()
    end
end

function _M.getPeriodsByCustom(start_time, end_time)
    local total = end_time - start_time
    local startdate = DroiTime.New(start_time)
    local enddate   = DroiTime.New(end_time)
    
    local startyear = startdate:Year()
    local startmonth = startdate:Month()
    local startday = startdate:Day()

    local endyear = enddate:Year()
    local endmonth = enddate:Month()
    local endday = enddate:Day()

    local ret = {}

    if  startyear == endyear and
        startmonth == endmonth and
        startday == endday then
        local period = {
            starttime = start_time,
            endtime = endtime,
        }

        table.insert(ret, period)
        return ret
    end

    local startdaytime = DroiTime.Date(startyear, startmonth, startday, 0, 0, 0, 0):Timestamp()
    local enddaytime = DroiTime.Date(startyear, startmonth, startday, 0, 0, 0, 0):Timestamp()
    
    local startdayperiod = {
        starttime = start_time,
        endtime = startdaytime + SECONDS_PER_DAY, 
    }

    local startdayused = startdaytime + SECONDS_PER_DAY - start_time
    local enddayused = end_time - enddaytime

    local rest = total - startdayused - enddayused
    local restdays = math.floor(rest / SECONDS_PER_DAY)

    table.insert(ret, startdayperiod)
    local lastendtime = startdayperiod.endtime
    for i = 1, restdays do
        local period = {
            starttime = lastendtime,
            endtime = lastendtime + SECONDS_PER_DAY,
        }

        table.insert(ret, period)
        lastendtime = period.endtime
    end
    
    local enddayperiod = {
        starttime = lastendtime,
        endtime = end_time,
    }
    table.insert(ret, startdayperiod)

    return ret
end

return _M
