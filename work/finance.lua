--pg finance

--[[ ---table
	fin_exrate_config
		app_id, app_name, signature, coin_name, exchange_rate, cash_deposit, operator_id, operate_time
	fin_user_coins
		user_id, coin_name, coi_num, operate_time
	fin_user_coins_deallog
		id, user_id, coin_name, deal_type, exchange_rate, droi_coins_before, droi_coins_after, deal_coins_before, deal_coins_after, operator_id, operate_time, ip

	ms_feedback_ratio_config
		level, ratio, modify_time

	ms_master_users
		id, user_d, app_id, invitation_code, master_id, bind_time
--]]
local ERRNO         = require("errno") 
local common        = require("common")
local cjson         = require("cjson.safe")
local LOG = require('log')

local OK = 'OK';

local _M = {}


----get increment id
local function getNewId( pgsql )
	local sql_str1 = "select nextval('fin_user_coins_deallog_id_seq')  id ;" 
	local res1 = pgsql:query(sql_str1);
	if (res1 and type(res1)=='table' and #res1>0) then
		return res1[1].id;
	end
	return 0;
end

---- insert into tab(fields) values(val);
local function fields_val( tab )
	if(not next(tab)) then
		return
	end
	local fields = {};
	local values = {};
	local val = "";
	for k ,v in pairs(tab) do
		if (v) then
			table.insert(fields ,k);
			table.insert(values,v);
		end
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

--- tab = where  ,op='and' 'or'
local function condition_op( tab ,op)
	local list = {};
	for k ,v in pairs(tab) do
		table.insert(list ,(" %s='%s' "):format(k ,v));
	end
	return table.concat(list ,op);
end

local function checkOrder(pgsql, appid, orderno)
	if (not appid or not orderno or appid=="" or orderno=="") then
		return false;
	end
	local sql_str = string.format("SELECT * FROM fin_user_coins_deallog WHERE operator_id='%s' and order_no='%s' limit 1;",appid,orderno);
	local res,err = pgsql:query(sql_str);
	if (res and type(res)=='table' and #res>0) then
		return true;
	end
	return false;
end

function _M.insertTest( req, pgsql )
	local tab = req.tab;
	local data = req.data;
	if (not pgsql)  then
		return {code =0}
	end
	local sql_str1 =  string.format("insert into %s(%s) values(%s) ;",tab,fields_val(data) )
	ngx.log(ngx.DEBUG,sql_str1);
	local res1,err = pgsql:query(sql_str1);
	return {code =0}
end

function _M.recharge( req, pgsql)
	local appid = req.appid;
	local role = req.role;		--0sdk  1业务
	local userid = req.userid;
	local fee = req.fee;
	local dealtype = req.dealtype or 0;    ---0rmb,1 activity 2 3consumer 4exchange
	local dealdesc = req.dealdesc;
	local orderno = req.orderno or '';
	local source = req.source;
	local feedback = req.feedback;    ---0 否 ，1是

	if (not fee or type(fee)~='number' or fee<=0) then		
		return common.ERROR(ERRNO.REQ_PARAM_ERROR)
	end

	if(checkOrder(pgsql,appid,orderno)) then		
		return common.ERROR(ERRNO.ORDER_REPEAT)
	end

	----coin configure 
	local sql_str1 = string.format("SELECT * FROM fin_exrate_config WHERE app_id = '%s';",appid);
	local res1 = pgsql:query(sql_str1);
	if (not res1 or type(res1)~='table' or #res1<=0) then
		return common.ERROR(ERRNO.APP_ID_NOT_EXIST)
	end
	local rateA = res1[1].exchange_rate;
	local cidA = res1[1].coin_id;
	local cashA = res1[1].cash_deposit or 0;
	if (not cidA or not rateA or type(rateA)~='number' or rateA<=0) then
		return common.ERROR(ERRNO.UNKNOWN_COIN_TYPE)
	end

	----master
	local masters = {};
	if (feedback and feedback==1) then
		local sql_str2 = "SELECT * FROM ms_feedback_ratio_config WHERE ratio>0 ORDER BY level ASC;"
		local res2 = pgsql:query(sql_str2);
		if (res2 and type(res2)=='table' and #res2>0) then
			local sql_str = ""
			for k,v in pairs(res2) do
				if (v.level==1) then
					sql_str = sql_str..string.format("SELECT master_id, %d as ratio,%d as level FROM ms_master_users WHERE user_id = '%s' and app_id = '%s' ;",v.ratio,v.level,userid,appid);
				elseif(v.level==2) then
					sql_str = sql_str..string.format("SELECT master_id, %d as ratio,%d as level FROM ms_master_users WHERE app_id = '%s' AND user_id IN (SELECT master_id FROM ms_master_users WHERE user_id = '%s' and app_id = '%s' );",v.ratio,v.level,appid,userid,appid);
				end
			end
			if (#sql_str>0) then
				local res = pgsql:query(sql_str);
				if (res and type(res)=='table' and #res>0) then
					for k,v in pairs(res) do
                            LOG.ERROR(v[1].master_id)
                            LOG.ERROR(v[1].ratio)
                            LOG.ERROR(v[1].level)
                            LOG.ERROR(v[1].ratio * fee)
                        if v[1].master_id then
						    masters[v[1].master_id] = { ratio = v[1].ratio,level = v[1].level, fee = v[1].ratio*fee };
                        end
					end
				end
			end
		end
	end

	----add fee
	local dealno = getNewId(pgsql);
	local res = pgsql:query("BEGIN;");
	masters[userid] = {fee = fee, ratio = rateA };
	for k,v in pairs(masters) do
        LOG.ERROR(k)
		local uid = k;
		local cnum0 = 0;
		local cnum1 = 0;
		local sql_str = "";
		local sql_str3 = string.format("SELECT * FROM fin_user_coins WHERE user_id = '%s' and coin_id = %d ;", uid,cidA);
		local res3 = pgsql:query(sql_str3);
		if (res3 and type(res3)=='table' and #res3>0) then
			cnum0 = res3[1].coin_num;
			sql_str = string.format("update fin_user_coins set coin_num = coin_num + %d,operate_time = now() WHERE user_id='%s' and coin_id = %d; ",v.fee,uid,cidA)
		else
			----check userid exists
			if (not common.check_userid(userid)) then
	            pgsql:query("ROLLBACK;");
				return common.ERROR(ERRNO.USER_ID_NOT_FOUND); 
			end
			local data = {
				user_id = uid,
				coin_id = cidA,
				coin_num = v.fee,
				operate_time = 'NOW()',
			}
			sql_str = string.format("insert into fin_user_coins(%s) values(%s); ",fields_val(data))
		end
		cnum1 = cnum0 + v.fee;
		local rmb = v.fee/rateA;

		local deal_type,ratio = dealtype,v.ratio;
		if (k~=userid) then 
			deal_type = 2;	
		end

		sql_str = sql_str..string.format("update fin_exrate_config set cash_deposit = cash_deposit + %d,operate_time = now() where coin_id = %d;",rmb,cidA)

		local tab1 = {
				order_no = orderno,
				deal_no = dealno,
				deal_type = deal_type,
				source = source,
				deal_seq = 0,
				user_id = uid,
				coin_id = cidA,
				exchange_rate = rateA,
				droi_coins_before = cashA,
				droi_coins_after = cashA+rmb,
				deal_coins_before = cnum0,
				deal_coins_after = cnum1,
				operator_id = appid,
				operate_time = 'NOW()',
				ip = ngx.var.remote_addr or'',
				description = dealdesc,
			};

		sql_str = sql_str..string.format("insert into fin_user_coins_deallog(%s) values(%s); ",fields_val(tab1))	
		local res = pgsql:query(sql_str);
		if(not res) then			
	        pgsql:query("ROLLBACK;");
			return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
		end
	end

	pgsql:query("COMMIT;");

	local result = _M.balance(req, pgsql);
	return result;
end

function _M.consume( req, pgsql )
	local appid = req.appid;
	local role = req.role;
	local userid = req.userid;
	local fee = req.fee;
	-- local feetype = req.feetype;
	local orderno = req.orderno or '';
	local dealdesc = req.dealdesc;
	local source = req.source;
	local ip = ngx.var.remote_addr or '';

	local dealtype = 3;   ---消费

	if(checkOrder(pgsql,appid,orderno)) then
		return common.ERROR(ERRNO.ORDER_REPEAT)
	end

	local sql_str1 = string.format([[
			select  users.coin_num,users.coin_id,conf.exchange_rate,conf.cash_deposit
			from fin_user_coins users ,fin_exrate_config conf 
			where users.coin_id=conf.coin_id and users.user_id = '%s' and conf.app_id = '%s' ;
		]], userid, appid )

	
	local res1 = pgsql:query(sql_str1);
	if (not res1 or type(res1)~='table' or #res1<=0) then
		return common.ERROR(ERRNO.APP_ID_NOT_EXIST)
	end

	local cidA = res1[1].coin_id;
	local rateA = res1[1].exchange_rate;
	local cnumA = res1[1].coin_num;  
	local cashA = res1[1].cash_deposit;
	if (not cidA or not rateA or type(rateA)~='number' or rateA<=0) then
		return common.ERROR(ERRNO.USER_ID_NOT_FOUND)
	end

	local dealno = getNewId(pgsql);
	local res = pgsql:query("BEGIN;");
	---enough money
	if (cnumA>fee) then
		local rmb = fee/rateA;
		local tab1 = {
			order_no = orderno,
			deal_no = dealno or '',
			deal_type = dealtype,
			source = source,
			deal_seq = 0,
			user_id = userid,
			coin_id = cidA,
			exchange_rate = rateA,
			droi_coins_before = cashA,
			droi_coins_after = cashA - fee/rateA,
			deal_coins_before = cnumA,
			deal_coins_after = cnumA - fee,
			operator_id = appid,
			operate_time = 'NOW()',
			ip = ip,
			description = dealdesc or '消费',
		}

		-- local sql_str2 = string.format("update fin_user_coins set coin_num = coin_num - %d,operate_time = now() where user_id = '%s' and coin_id = %d;",fee, userid, cidA);
		-- local sql_str2 = string.format("update fin_exrate_config set cash_deposit = cash_deposit - %d,operate_time = now() where coin_id = %d;",rmb, cidA);
		-- local sql_str3 = string.format("insert into fin_user_coins_deallog(%s) values(%s); ",fields_val(tab1))
		local sql_str2 = string.format([[
			update fin_user_coins set coin_num = coin_num - %d,operate_time = now() where user_id = '%s' and coin_id = %d;
			update fin_exrate_config set cash_deposit = cash_deposit - %d,operate_time = now() where coin_id = %d;
			insert into fin_user_coins_deallog(%s) values(%s); 
			]],fee, userid, cidA,rmb, cidA,fields_val(tab1))

		local res2, err1 = pgsql:query(sql_str2);
		if(not res2) then
			pgsql:query("ROLLBACK;");
			return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
		end
		-- local res3 = pgsql:query(sql_str3);
		-- if(not res3) then
		-- 	pgsql:query("ROLLBACK;");
		-- end

	else

		local sql_str2;
		if (feetype) then
			sql_str2 = string.format([[
				select users.coin_num,conf.coin_id,conf.exchange_rate, users.coin_num/conf.exchange_rate as rmb  ,conf.cash_deposit
				from fin_user_coins users,
				(select coin_id,exchange_rate from fin_exrate_config where is_open=1 and coin_id = %s and  ) conf 
				where users.coin_id=conf.coin_id and user_id = '%s'
				ORDER BY users.coin_num/conf.exchange_rate desc;
			]],userid, feetype )
		else
			sql_str2 = string.format([[
				select users.coin_num,conf.coin_id,conf.exchange_rate, users.coin_num/conf.exchange_rate as rmb ,conf.cash_deposit 
				from fin_user_coins users,
				(select coin_id,exchange_rate from fin_exrate_config where is_open=1 and coin_id <> %s ) conf 
				where users.coin_id=conf.coin_id and user_id='%s'
				ORDER BY users.coin_num/conf.exchange_rate desc;
			]],userid, cidA )
		end

		local res2, err2 = pgsql:query(sql_str2);
		if (not res2 or type(res2)~='table' or #res2<=0) then			
			return common.ERROR(ERRNO.BALANCE_NOT_ENOUGH)
		end

		local need = fee - cnumA ;
		local exfee = 0;
		local supplier = {};
		for k,v in pairs(res2) do
			local val = rateA * v.rmb;
			if (val>need) then
				val = need;
			end
			if(need - val>=0) then
				need = need - val;
				table.insert(supplier,{val = val,coin_num = v.coin_num, rmb = rmb,rate = v.exchange_rate,coin_id = v.coin_id,cash = v.cash_deposit});
			end
			exfee = exfee + val;
		end

		if (need>0) then
			return common.ERROR(ERRNO.BALANCE_NOT_ENOUGH)
		end

		----执行交换，记录日志 
		local sql_str4 = "";
		for k,v in pairs(supplier) do
			local cost = v.rate*v.rmb;
			
			local tab1 = {
				order_no = orderno,
				deal_no = dealno or '',
				deal_type = dealtype,
				source = source,
				deal_seq = 0,
				user_id = userid,
				coin_id = v.coin_id,
				exchange_rate = v.rate,
				droi_coins_before = v.cash,
				droi_coins_after = v.cash-v.rmb,
				deal_coins_before = v.coin_num,
				deal_coins_after = v.coin_num - cost,
				operator_id = appid,
				operate_time = 'NOW()',
				ip = ip,
				description = dealdesc or '兑换',
			}

			sql_str4 = sql_str4..string.format( [[	
					update fin_user_coins set coin_num = coin_num - %d,operate_time = now() where user_id = '%s' and coin_id = %d;
					update fin_exrate_config set cash_deposit = cash_deposit - %d,operate_time = now() where coin_id = %d ;
					insert into fin_user_coins_deallog(%s) values(%s);
				]], cost, userid, v.coin_id,v.rmb,v.coin_id,fields_val(tab1))
					
		end
		local res4, err4 = pgsql:query(sql_str4);
		if (not res4) then
			pgsql:query("ROLLBACK;");
			return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
		end

		-- local sql_str2 = string.format("update fin_user_coins set coin_num = coin_num - %d,operate_time = now() where user_id = '%s' and coin_id = %d;",fee, userid, cidA);
		-- local sql_str3 = string.format("insert into fin_user_coins_deallog(%s) values(%s); ",fields_val(tab1))
		local sql_str2 = string.format( [[
			update fin_user_coins set coin_num = coin_num - %d,operate_time = now() where user_id = '%s' and coin_id = %d;
			update fin_exrate_config set cash_deposit = cash_deposit - %d,operate_time = now() where coin_id = %d ;
			insert into fin_user_coins_deallog(%s) values(%s);
			]],fee, userid, cidA,fee/rateA,cidA,fields_val(tab1))
		local res2, errx = pgsql:query(sql_str2);
		if (not res2) then
			pgsql:query("ROLLBACK;");
			return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
		end
		-- local res3 = pgsql:query(sql_str3);
		-- if (not res3) then
		-- 	pgsql:query("ROLLBACK;");
		-- end
	end

	pgsql:query("COMMIT;");
	local result = _M.balance(req, pgsql);
	return result;
end


function _M.exchange( req, pgsql )
	local appid = req.appid;
	local userid = req.userid;
	local need = req.fee;
	local coinid = req.feetype;
	local role = req.role;
	local orderno = req.orderno or '';
	local feetype = req.feetype;
	local dealdesc = req.dealdesc;
	local source = req.source;

	local dealtype = 4;   ---兑换

	if(checkOrder(pgsql,appid,orderno)) then
		return common.ERROR(ERRNO.ORDER_REPEAT)
	end

	local result = {};

	local sql_str1 = string.format("select coin_id,coin_num from fin_user_coins where user_id = '%s'", userid )
	if (feetype) then
		sql_str1 = sql_str1..' and coin_id = '..feetype;
	end
	sql_str1 = sql_str1 ..';'

	local res1 = pgsql:query(sql_str1);
	ngx.log(ngx.DEBUG,sql_str1);
	if (not res1 or type(res1)~='table' or #res1<=0) then
		return common.ERROR(ERRNO.USER_ID_NOT_FOUND)
	end


	local sql_str2 = string.format("select * from fin_exrate_config where app_id = '%s' ;", appid )
	local res2 = pgsql:query(sql_str2);
	if (not res2 or type(res2)~='table' or #res2<=0) then
		return common.ERROR(ERRNO.APP_ID_NOT_EXIST)
	end

	local cidA = res2[1].coin_id;
	local rateA = res2[1].exchange_rate;
	local cashA = res2[1].cash_deposit;
	local cnumA = 0;  
	if (not rateA or type(rateA)~='number' or rateA<=0) then
		return common.ERROR(ERRNO.UNKNOWN_COIN_TYPE)
	end

	local cids = {};
	for k,v in pairs(res1) do
		if(v.coin_id==cidA) then
			cnumA = v.coin_num;
		else
			table.insert(cids,v.coin_id);
		end
	end

	local cid_str = table.concat( cids,',' );

	local sql_str3 = string.format( [[
	select users.coin_num,conf.coin_id,conf.exchange_rate, conf.cash_deposit ,users.coin_num/conf.exchange_rate as rmb  
	from fin_user_coins users,
	(select coin_id,exchange_rate from fin_exrate_config where is_open=1 and coin_id IN (%s) ) conf 
	where users.coin_id=conf.coin_id 
	ORDER BY users.coin_num/conf.exchange_rate desc;
	]], cid_str);
	
	local res3 = pgsql:query(sql_str3);
	if (not res3 or type(res3)~='table' or #res3<=0) then		
		return common.ERROR(ERRNO.BALANCE_NOT_ENOUGH)
	end

	local exfee = 0;
	local supplier = {};
	for k,v in pairs(res3) do
		local rmb = v.rmb;
		local val = rateA * v.rmb;
		if (val>need) then
			val = need;
		end
		if(need - val>=0) then
			need = need - val;
			table.insert(supplier,{val = val,coin_num = v.coin_num, rate = v.exchange_rate,coin_id = v.coin_id,rmb = rmb,cash = v.cash_deposit });
		end
		exfee = exfee + val;
	end
	if (need>0) then
		return common.ERROR(ERRNO.BALANCE_NOT_ENOUGH)
	end

	pgsql:query("BEGIN;");
	local dealno = getNewId(pgsql) or '';
	local ip = ngx.var.remote_addr or ''
	----执行交换，记录日志 
	for k,v in pairs(supplier) do
		local valA = v.val;
		local valB = v.rate*v.val/rateA;
		local tab1 = {
			order_no = orderno,
			deal_no = dealno,
			deal_type = dealtype,
			source = source,
			deal_seq = 0,
			user_id = userid,
			coin_id = cidA,
			exchange_rate = rateA,
			droi_coins_before = cashA,
			droi_coins_after = cashA - v.rmb,
			deal_coins_before = v.coin_num,
			deal_coins_after = v.coin_num-v.rmb*rateA,
			operator_id = appid,
			operate_time = 'NOW()',
			ip = ip,
			description = dealdesc or '兑换',
		};

		cashA = cashA - v.rmb;

		local tab2 = {
			order_no = orderno,
			deal_no = dealno,
			deal_type = dealtype,
			source = source,
			deal_seq = 0,
			user_id = userid,
			coin_id = v.coin_id,
			exchange_rate = v.rateA,
			droi_coins_before = v.cash,
			droi_coins_after = v.cash+v.rmb,
			deal_coins_before = v.coin_num,
			deal_coins_after = v.coin_num+v.rmb*v.rate,
			operator_id = appid,
			operate_time = 'NOW()',
			ip = ip,
			description = dealdesc or '兑换',
		};

		local sql_str4 = string.format("update fin_user_coins set coin_num = coin_num + %d,operate_time = now() where user_id = '%s' and coin_id = %d;",valA, userid, cidA);
		sql_str4 = sql_str4..string.format("\n update fin_user_coins set coin_num = coin_num - %d,operate_time = now() where user_id = '%s' and coin_id = %d;",valB, userid, v.coin_id);
		sql_str4 = sql_str4..string.format("\n update fin_exrate_config set cash_deposit = cash_deposit + %d,operate_time = now() where coin_id = %d ;",v.rmb, cidA);
		sql_str4 = sql_str4..string.format("\n update fin_exrate_config set cash_deposit = cash_deposit - %d,operate_time = now() where coin_id = %d ;",v.rmb, v.coin_id);
		sql_str4 = sql_str4..string.format("\n insert into fin_user_coins_deallog(%s) values(%s);",fields_val(tab1));
		sql_str4 = sql_str4..string.format("\n insert into fin_user_coins_deallog(%s) values(%s);",fields_val(tab2));
		ngx.log(ngx.DEBUG,sql_str4)
		local res4,err = pgsql:query(sql_str4);	
		if (err) then
			pgsql:query("ROLLBACK;");	
			return common.ERROR(ERRNO.INTERNAL_OP_FAILED)
		end
	end
	pgsql:query("COMMIT;");	

    local zyl_fee = cnumA+need
    local zyl_exfee = exfee-need
	return {code = 0, msg = OK, fee = tostring(zyl_fee), exfee = tostring(zyl_exfee)}
end

function _M.balance( req, pgsql )
	local appid = req.appid;
	local userid = req.userid;
	local role = req.role;
	local feetype = req.feetype;

	local sql_str = string.format("SELECT users.coin_num as coin_num,conf.exchange_rate as exchange_rate from fin_user_coins users,fin_exrate_config conf WHERE user_id='%s' and conf.coin_id=users.coin_id and app_id='%s';",userid,appid);
	local res, errr = pgsql:query(sql_str); 
	if (not res or type(res)~='table') then
		return common.ERROR(ERRNO.USER_ID_NOT_FOUND)
    end

    local fee = 0
    local rateA = 0
    if #res > 0 then
	    fee = res[1].coin_num;
	    rateA = res[1].exchange_rate;
    end

	local exfee = 0;
	local sql_str = string.format("SELECT sum(users.coin_num/conf.exchange_rate) rmb from fin_user_coins users,fin_exrate_config conf WHERE user_id='%s' and conf.coin_id=users.coin_id and app_id<>'%s';",userid,appid);
	if (feetype) then   ---指定币种
		sql_str = string.format("SELECT sum(users.coin_num/conf.exchange_rate) rmb from fin_user_coins users,fin_exrate_config conf WHERE user_id='%s' and conf.coin_id=users.coin_id and app_id='%s';",userid,feetype);
    end
	local res = pgsql:query(sql_str); 
	if (res and type(res)=='table' and #res>0 and res[1].rmb) then
		exfee = res[1].rmb*rateA;
    else
        exfee = 0
	end

	--[[
	local sql_str1 = string.format("select * from fin_user_coins where user_id = '%s';", userid )
	
	local res1 = pgsql:query(sql_str1);

	if (not res1 or type(res1)~='table' or #res1<=0) then
		return common.ERROR(ERRNO.USER_ID_NOT_FOUND)
	end

	local cid_list = {};
	for k,v in pairs(res1) do
		local cid = v['coin_id'];
		table.insert( cid_list, cid );
	end

	local cid_str = table.concat( cid_list,',' )
	local sql_str2 = string.format("select * from fin_exrate_config where coin_id IN (%s) ;", cid_str )
	local res2 = pgsql:query(sql_str2);
	if (not res2 or type(res2)~='table' or #res2<=0 )  then
		return common.ERROR(ERRNO.APP_ID_NOT_EXIST)
	end

	local cid , rate ;
	local obj = {};
	for k,v in pairs(res2) do
		if (v.app_id==appid) then
			cid = v.coin_id;
			rate = v.exchange_rate;
		else
			obj['cid:'..v.coin_id] = v.exchange_rate;
		end
	end
	local fee = 0;
	local exfee = 0;
	for k,v in pairs(res1) do
		local id = v.coin_id;
		local num = v.coin_num;
		if (v.coin_id==cid) then
			fee = num;
		else
			if ( id and obj['cid:'..id]) then
				local val = num/obj['cid:'..id];
				local m = string.format("%.2f",val*rate);
				exfee = exfee + m;
			end
		end
	end
	--]]
	local result = {
		code = 0,
		msg = OK,
		fee = tostring(fee),
		exfee = tostring(exfee),
	}
	return result;
end

function _M.record( req, pgsql )
	local appid = req.appid;
	local userid = req.userid;
	local role = req.role;
	local page = req.page or 1;
	local pagesize = req.pagesize or 20;
	local dealtype = req.dealtype;
	local source = req.source;
	local starttime = req.starttime;
	local endtime = req.endtime;
    local orderno = req.orderno;

	local result = {
		code = 0,
		msg = OK,
		count = 0,		
	}

	local offset = (page - 1)*pagesize;
	local where = {
		['user_id'] = userid,
		['operator_id'] = appid,
	}
	local condition = condition_op(where ,'and');
	if (dealtype) then
		condition = condition..' and deal_type= '..dealtype;
	end
	if (source) then
		condition = condition..' and source = '..source;
    end

    if orderno then
		condition = string.format(" %s and order_no = '%s' ", condition, orderno);
    end

	if (starttime) then
		-- condition = string.format(' %s and datediff(d, %s, operate_time) >= 0 ',condition,starttime);
		condition = string.format(" %s and operate_time >= '%s' ",condition,os.date("%Y-%m-%d %H:%M:%S",starttime));
	end
	if (endtime) then
		-- condition = string.format(' %s and datediff(d, %s, operate_time) <= 0 ',condition,endtime);
		condition = string.format(" %s and operate_time) <= '%s' ",condition,os.date("%Y-%m-%d %H:%M:%S",endtime));
	end

	local sql_sum = string.format("select sum(log.deal_coins_before - log.deal_coins_after) n from fin_user_coins_deallog log where %s;", condition);
	local sum_res = pgsql:query(sql_sum);
    if sum_res and #sum_res > 0 then
        local sum = sum_res[1].n or 0
        result.sum = tostring(math.abs(sum))
    end

	local sql_str = string.format("select * from fin_user_coins_deallog where %s order by id DESC limit %d offset %d ;", condition ,pagesize , offset );
    LOG.DEBUG(sql_str)
	local res = pgsql:query(sql_str);
	if (res and #res>0) then
		result.data = res or {};
		result.count = #result.data;
	end
	return result;
end

return _M;
