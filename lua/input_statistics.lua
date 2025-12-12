-- base on github.com/amzxyz
-- update by github.com/happyDom
--[[
首先，把本脚本放在你的方案下的lua文件夹内

※：如果你的脚本名称为 input_statistics ₂₀₂₅1208・A.lua，你需要把文件名改为 input_statistics.lua后再用

※：如果你第一次使用不早于 ₂₀₂₅1208・B 版本的本脚本，请把你原来lua文件夹下的 input_stats.lua删除

其次，如果你的方案可以输入 /fj 以输入特殊符号，可以忽略这条。否则你需要调整你的方案的 alphabet 设定（在补丁中调整），加入符号 /
  # 不需要与下面这条安全一样，但需要确认其中有符号 /
  speller/alphabet: "abcdefghijklmnopqrstuvwxyz;'/"
  # 如果你的方案中设置了 initials，请确认其中也包含符号 /，例如：
  speller/initials: ';abcdefghijklmnopqrstuvwxyz/'

再其次，在你的方案补丁文件中，在translators节点加入对 input_statistics 的引用，如下👇：
  engine/translators/+:				#定制translator如下
	- lua_translator@*input_statistics				# 统计输入速度等信息

再其次，为了让统计数据在输入 /01 时有响应，你需要在方案补丁文件中加入以下👇补丁（让方案捕捉/xx [xx为数字] 这类输入):
  recognizer/patterns/punct: '^/([0-9]+|[A-Za-z]+)$'

最后，重新部署你的rime/同文

使用提示（例如/01 /rtj 两种方式均可）：
/01 /rtj	 查看日统计
/02 /ztj	 查看周统计
/03 /ytj	 查看月统计
/04 /ntj	 查看年统计
/05 /sztj		 查看生字/词
/008 /qcsz	清除生字/词
/009 /qctj	 清除所有统计数据
]]

-- 输入方案名称
local schema_name = "小鹤九宫格双拼932"
-- 卡壳时间门限(单位：s)，当上屏的字/词距离前一次上屏时间大于该门限时，该字/词被记录为生字/词组数据
local boggleThd_s = 3
-- 在提交修改时，记录的码长做 + codeLenOffset 处理；如果你每个字需要选字或者空格上屏，则此处的1即表示一个空格的码长
local codeLenOffset = 1
-- 如果你想在最大分速后加以说明，请在这里自定义你的说明内容，可以使用 \n 换行
local maxSpdDesc = ''
-- 如果你想在平均码长后加以说明，请在这里自定义你的说明内容，可以使用 \n 换行
local avgCodeLenDesc = '〔含空格〕'

-- 分配一个变量，用于字符串拼接
local strTable = {}
-- 分隔线
local splitor = string.rep("─", 14)

-- 下面的信息是自动获取的
local software_name = rime_api.get_distribution_code_name()
local software_version = rime_api.get_distribution_version()

-- 一个数据结构体，用于处理平均速度统计临时数据
avgSpdInfo = {logSts = 0,		-- 统计状态，0：未统计，1:正在统计，2:统计结束
				startTime=0,	-- 如果正在记录，这里是开始的时间
				clickTime = 0,	-- 上次按键时间，通过记录按键间隔，判断是否输入超时
				commitTime=0,	-- 这是最近一次上屏的时间
				gapThd=5,		-- 如果此次按键距离前一次按键的时间大于此门限值，则重新开始计时
				count=0			-- 记录期间，上屏的字数
				}

-- 初始化统计表（若未加载）
input_stats = input_stats or {
	daily = {count = 0, length = 0, fastest = 0, ts = 0, lengths = {}, codeLengths = {}, avgGaps = {}, avgCnts = {}},
	weekly = {count = 0, length = 0, fastest = 0, ts = 0, lengths = {}, codeLengths = {}, avgGaps = {}, avgCnts = {}},
	monthly = {count = 0, length = 0, fastest = 0, ts = 0, lengths = {}, codeLengths = {}, avgGaps = {}, avgCnts = {}},
	yearly = {count = 0, length = 0, fastest = 0, ts = 0, lengths = {}, codeLengths = {}, avgGaps = {}, avgCnts = {}},
	daily_max = 0,
	newWords = {}
}

-- 定义一个求和函数，用于求取一个table内的数字的和
local function tableSum(tb)
	local sum = 0
	for i=1, #tb do
		sum = sum + tb[i]
	end
	return sum
end

-- 定义一个求和函数，用于求取一个table内尾部指定数量项的和
local function tableTailSum(tb,n)
	if type(tb) ~= "table" then return 0 end
    local len = #tb
	local n = tonumber(n) or 0  -- 非数字转 0
	if n < 1 or len < 1 then return 0 end
	
	local sum = 0
	local takeCount = math.min(n, len)
	for i = 1, takeCount do
        sum = sum + (tb[len - takeCount + i] or 0)
    end
	return sum
end

-- 时间戳工具函数
local function start_of_day(t)
	return os.time{year=t.year, month=t.month, day=t.day, hour=0}
end
local function start_of_week(t)
	local d = t.wday == 1 and 6 or (t.wday - 2)
	return os.time{year=t.year, month=t.month, day=t.day - d, hour=0}
end
local function start_of_month(t)
	return os.time{year=t.year, month=t.month, day=1, hour=0}
end
local function start_of_year(t)
	return os.time{year=t.year, month=1, day=1, hour=0}
end

-- 更新统计数据
local function update_stats(input_length, codeLen, avgAvailable)
	local now = os.date("*t")
	local now_ts = os.time(now)

	local day_ts = start_of_day(now)
	local week_ts = start_of_week(now)
	local month_ts = start_of_month(now)
	local year_ts = start_of_year(now)

	if input_stats.daily.ts ~= day_ts then
		input_stats.daily = {count = 0, length = 0, fastest = 0, ts = day_ts, lengths = {}, codeLengths = {}, avgGaps={}, avgCnts={}}
		input_stats.daily_max = 0
	end
	if input_stats.weekly.ts ~= week_ts then
		input_stats.weekly = {count = 0, length = 0, fastest = 0, ts = week_ts, lengths = {}, codeLengths = {}, avgGaps={}, avgCnts={}}
	end
	if input_stats.monthly.ts ~= month_ts then
		input_stats.monthly = {count = 0, length = 0, fastest = 0, ts = month_ts, lengths = {}, codeLengths = {}, avgGaps={}, avgCnts={}}
	end
	if input_stats.yearly.ts ~= year_ts then
		input_stats.yearly = {count = 0, length = 0, fastest = 0, ts = year_ts, lengths = {}, codeLengths = {}, avgGaps={}, avgCnts={}}
	end
	
	-- 更新平均分速统计数据
	if 1 == avgAvailable then
		local delt = avgSpdInfo.commitTime - avgSpdInfo.startTime
		table.insert(input_stats.daily.avgGaps, delt)
		table.insert(input_stats.weekly.avgGaps, delt)
		table.insert(input_stats.monthly.avgGaps, delt)
		table.insert(input_stats.yearly.avgGaps, delt)
		table.insert(input_stats.daily.avgCnts, avgSpdInfo.count)
		table.insert(input_stats.weekly.avgCnts, avgSpdInfo.count)
		table.insert(input_stats.monthly.avgCnts, avgSpdInfo.count)
		table.insert(input_stats.yearly.avgCnts, avgSpdInfo.count)
		
		-- 最后累计10s的提交数据，计算平均速度做为最大分速的参考
		local latestGapsSum = 0
		local latestCntsSum = 0
		local latestSpd = 0
		local len = #input_stats.daily.avgGaps
		for i=0,len - 1 do
			latestGapsSum = latestGapsSum + input_stats.daily.avgGaps[len - i]
			latestCntsSum = latestCntsSum + input_stats.daily.avgCnts[len - i]
			if latestGapsSum >= 10 then  -- 最后10s的平均速度做为瞬时速度
				break
			end
		end
		if latestGapsSum >= 10 then	-- 如果数据的时长小于10s，则不计算最大速度，避免瞬时偏差过大
			latestSpd = latestCntsSum / latestGapsSum * 60
			
			-- 更新最大分速值
			if latestSpd > input_stats.daily.fastest then input_stats.daily.fastest = latestSpd end
			if latestSpd > input_stats.weekly.fastest then input_stats.weekly.fastest = latestSpd end
			if latestSpd > input_stats.monthly.fastest then input_stats.monthly.fastest = latestSpd end
			if latestSpd > input_stats.yearly.fastest then input_stats.yearly.fastest = latestSpd end
		end
	end
	
	-- 如果输入字/词长度小于1（即为空），则不做后续的处理
	if input_length < 1 then return end

	-- 更新记录
	local update = function(stat)
		stat.count = stat.count + 1
		stat.length = stat.length + input_length
	end
	update(input_stats.daily)
	update(input_stats.weekly)
	update(input_stats.monthly)
	update(input_stats.yearly)

	if input_length > input_stats.daily_max then
		input_stats.daily_max = input_length
	end
	
	-- 更新输入字/词组数据
	input_stats.daily.lengths[input_length] = (input_stats.daily.lengths[input_length] or 0) + 1
	input_stats.weekly.lengths[input_length] = (input_stats.weekly.lengths[input_length] or 0) + 1
	input_stats.monthly.lengths[input_length] = (input_stats.monthly.lengths[input_length] or 0) + 1
	input_stats.yearly.lengths[input_length] = (input_stats.yearly.lengths[input_length] or 0) + 1
	
	-- 更新输入码长数据
	input_stats.daily.codeLengths[codeLen] = (input_stats.daily.codeLengths[codeLen] or 0) + 1
	input_stats.weekly.codeLengths[codeLen] = (input_stats.weekly.codeLengths[codeLen] or 0) + 1
	input_stats.monthly.codeLengths[codeLen] = (input_stats.monthly.codeLengths[codeLen] or 0) + 1
	input_stats.yearly.codeLengths[codeLen] = (input_stats.yearly.codeLengths[codeLen] or 0) + 1
end

-- 表序列化工具（请自行根据实际添加到环境中）
table.serialize = function(tbl)
	local lines = {"{"}
	for k, v in pairs(tbl) do
		local key = (type(k) == "string") and ("[\"" .. k .. "\"]") or ("[" .. k .. "]")
		local val
		if type(v) == "table" then
			val = table.serialize(v)
		elseif type(v) == "string" then
			val = '"' .. v .. '"'
		else
			val = tostring(v)
		end
		table.insert(lines, string.format("	%s = %s,", key, val))
	end
	table.insert(lines, "}")
	return table.concat(lines, "\n")
end

-- 保存至文件
local function save_stats()
	local path = rime_api.get_user_data_dir() .. "/lua/input_stats.lua"
	local file = io.open(path, "w")
	if not file then return end
	file:write("input_stats = " .. table.serialize(input_stats) .. "\n")
	file:close()
end

-- 显示函数（日统计）
local function format_daily_summary()
	local s = input_stats.daily
	if s.count == 0 then return "※ 今天没有任何记录。" end
	
	-- 统计各类输入组合的占比
	local val1 = s.lengths[1] or 0  -- 防止索引不存在时报错，默认0
	local val2 = (s.lengths[2] or 0) * 2
	local val3 = 0
	local total = 0		-- 总字数
	for key, value in pairs(s.lengths) do
		total = total + key * value  -- 累加所有值
	end
	if total == 0 then total = 1 end  -- 防止除以0报错
	val3 = total - val1 - val2
	local ratio1 = (val1 / total) * 100
	local ratio2 = (val2 / total) * 100
	local ratio3 = (val3 / total) * 100
	
	-- 统计码长的占比（分类为：频率最高的3种码长，和其它码长）
	local codeTable_sorted = {}
	local totalCodeLen = 0	-- 总码长
	local totalCodeCnt = 0	-- 总码数
	local codeTypeCnt = 0	-- 码长的种类数量
	for k,v in pairs(s.codeLengths) do
		totalCodeLen = totalCodeLen + v * k
		totalCodeCnt = totalCodeCnt + v
		codeTypeCnt = codeTypeCnt + 1
		table.insert(codeTable_sorted, {clen=k,count=v})
	end
	table.sort(codeTable_sorted, function(a,b)
		return a.count > b.count
		end)
	if totalCodeCnt == 0 then totalCodeCnt = 1 end	-- 防止除以0报错
	local codeTableFirstN = {}
	local ratioSumOfFirstN = 0
	for i = 1, 3 do
		if i <= codeTypeCnt then
			codeTableFirstN[i] = {codeLen = codeTable_sorted[i].clen, ratio = codeTable_sorted[i].count / totalCodeCnt * 100}
		else
			codeTableFirstN[i] = {codeLen = 0, ratio=0}
		end
		ratioSumOfFirstN = ratioSumOfFirstN + codeTableFirstN[i].ratio
	end
	codeTableFirstN[4] = {codeLen = 0, ratio = 100 - ratioSumOfFirstN}
	-- 计算平均码长
	local avgCodeLen = totalCodeLen / total
	
	
	-- 计算平均分速
	local avgV = tableSum(input_stats.daily.avgGaps)
	if avgV > 1 then
		avgV = tableSum(input_stats.daily.avgCnts) / avgV * 60
	end
	
	strTable[1] = '※ 日统计：'
	strTable[3] = string.format('上屏 %d 次',s.count)
	strTable[4] = string.format('输入 %d 字',s.length)
	strTable[5] = string.format('最大分速 %.1f 字%s',s.fastest, maxSpdDesc)
	strTable[6] = string.format('平均分速 %.1f 字',avgV)
	strTable[7] = string.format('平均码长 %.1f%s',avgCodeLen, avgCodeLenDesc)
	strTable[9] = string.format('单字占比：%.1f％',ratio1)
	strTable[10] = string.format('2字词占比：%.1f％',ratio2)
	strTable[11] = string.format('>2字词占比：%.1f％',ratio3)
	if codeTableFirstN[1].ratio > 0 then
		strTable[13] = string.format('%s码占比：%.1f％', codeTableFirstN[1].codeLen, codeTableFirstN[1].ratio)
	else
		strTable[13] = ''
	end
	if codeTableFirstN[2].ratio > 0 then
		strTable[14] = string.format('%s码占比：%.1f％', codeTableFirstN[2].codeLen, codeTableFirstN[2].ratio)
	else
		strTable[14] = ''
	end
	if codeTableFirstN[3].ratio > 0 then
		strTable[15] = string.format('%s码占比：%.1f％', codeTableFirstN[3].codeLen, codeTableFirstN[3].ratio)
	else
		strTable[15] = ''
	end
	if codeTableFirstN[4].ratio > 0 then
		strTable[16] = string.format('其它占比：%.1f％', codeTableFirstN[4].ratio)
	else
		strTable[16] = ''
	end

	return table.concat(strTable, '\n')
end

-- 显示函数（周统计）
local function format_weekly_summary()
	local s = input_stats.weekly
	if s.count == 0 then return "※ 本周没有任何记录。" end
	
	-- 统计各类输入组合的占比
	local val1 = s.lengths[1] or 0  -- 防止索引不存在时报错，默认0
	local val2 = (s.lengths[2] or 0) * 2
	local val3 = 0
	local total = 0
	for key, value in pairs(s.lengths) do
		total = total + key * value  -- 累加所有值
	end
	if total == 0 then total = 1 end  -- 防止除以0报错
	val3 = total - val1 - val2
	local ratio1 = (val1 / total) * 100
	local ratio2 = (val2 / total) * 100
	local ratio3 = (val3 / total) * 100
	
	-- 统计码长的占比（分类为：频率最高的3种码长，和其它码长）
	local codeTable_sorted = {}
	local totalCodeLen = 0	-- 总码长
	local totalCodeCnt = 0	-- 总码数
	local codeTypeCnt = 0	-- 码长的种类数量
	for k,v in pairs(s.codeLengths) do
		totalCodeLen = totalCodeLen + v * k
		totalCodeCnt = totalCodeCnt + v
		codeTypeCnt = codeTypeCnt + 1
		table.insert(codeTable_sorted, {clen=k,count=v})
	end
	table.sort(codeTable_sorted, function(a,b)
		return a.count > b.count
		end)
	if totalCodeCnt == 0 then totalCodeCnt = 1 end	-- 防止除以0报错
	local codeTableFirstN = {}
	local ratioSumOfFirstN = 0
	for i = 1, 3 do
		if i <= codeTypeCnt then
			codeTableFirstN[i] = {codeLen = codeTable_sorted[i].clen, ratio = codeTable_sorted[i].count / totalCodeCnt * 100}
		else
			codeTableFirstN[i] = {codeLen = 0, ratio=0}
		end
		ratioSumOfFirstN = ratioSumOfFirstN + codeTableFirstN[i].ratio
	end
	codeTableFirstN[4] = {codeLen = 0, ratio = 100 - ratioSumOfFirstN}
	-- 计算平均码长
	local avgCodeLen = totalCodeLen / total
	
	-- 计算平均分速
	local avgV = tableSum(input_stats.weekly.avgGaps)
	if avgV > 1 then
		avgV = tableSum(input_stats.weekly.avgCnts) / avgV * 60
	end
	
	strTable[1] = '※ 周统计：'
	strTable[3] = string.format('上屏 %d 次',s.count)
	strTable[4] = string.format('输入 %d 字',s.length)
	strTable[5] = string.format('最大分速 %.1f 字%s',s.fastest, maxSpdDesc)
	strTable[6] = string.format('平均分速 %.1f 字',avgV)
	strTable[7] = string.format('平均码长 %.1f%s',avgCodeLen, avgCodeLenDesc)
	strTable[9] = string.format('单字占比：%.0f％',ratio1)
	strTable[10] = string.format('2字词占比：%.0f％',ratio2)
	strTable[11] = string.format('>2字词占比：%.0f％',ratio3)
	if codeTableFirstN[1].ratio > 0 then
		strTable[13] = string.format('%s码占比：%.1f％', codeTableFirstN[1].codeLen, codeTableFirstN[1].ratio)
	else
		strTable[13] = ''
	end
	if codeTableFirstN[2].ratio > 0 then
		strTable[14] = string.format('%s码占比：%.1f％', codeTableFirstN[2].codeLen, codeTableFirstN[2].ratio)
	else
		strTable[14] = ''
	end
	if codeTableFirstN[3].ratio > 0 then
		strTable[15] = string.format('%s码占比：%.1f％', codeTableFirstN[3].codeLen, codeTableFirstN[3].ratio)
	else
		strTable[15] = ''
	end
	if codeTableFirstN[4].ratio > 0 then
		strTable[16] = string.format('其它占比：%.1f％', codeTableFirstN[4].ratio)
	else
		strTable[16] = ''
	end
	
	return table.concat(strTable, '\n')
end

-- 显示函数（月统计）
local function format_monthly_summary()
	local s = input_stats.monthly
	if s.count == 0 then return "※ 本月没有任何记录。" end
	
	-- 统计各类输入组合的占比
	local val1 = s.lengths[1] or 0  -- 防止索引不存在时报错，默认0
	local val2 = (s.lengths[2] or 0) * 2
	local val3 = 0
	local total = 0
	for key, value in pairs(s.lengths) do
		total = total + key * value  -- 累加所有值
	end
	if total == 0 then total = 1 end  -- 防止除以0报错
	val3 = total - val1 - val2
	local ratio1 = (val1 / total) * 100
	local ratio2 = (val2 / total) * 100
	local ratio3 = (val3 / total) * 100
	
	-- 统计码长的占比（分类为：频率最高的3种码长，和其它码长）
	local codeTable_sorted = {}
	local totalCodeLen = 0	-- 总码长
	local totalCodeCnt = 0	-- 总码数
	local codeTypeCnt = 0	-- 码长的种类数量
	for k,v in pairs(s.codeLengths) do
		totalCodeLen = totalCodeLen + v * k
		totalCodeCnt = totalCodeCnt + v
		codeTypeCnt = codeTypeCnt + 1
		table.insert(codeTable_sorted, {clen=k,count=v})
	end
	table.sort(codeTable_sorted, function(a,b)
		return a.count > b.count
		end)
	if totalCodeCnt == 0 then totalCodeCnt = 1 end	-- 防止除以0报错
	local codeTableFirstN = {}
	local ratioSumOfFirstN = 0
	for i = 1, 3 do
		if i <= codeTypeCnt then
			codeTableFirstN[i] = {codeLen = codeTable_sorted[i].clen, ratio = codeTable_sorted[i].count / totalCodeCnt * 100}
		else
			codeTableFirstN[i] = {codeLen = 0, ratio=0}
		end
		ratioSumOfFirstN = ratioSumOfFirstN + codeTableFirstN[i].ratio
	end
	codeTableFirstN[4] = {codeLen = 0, ratio = 100 - ratioSumOfFirstN}
	-- 计算平均码长
	local avgCodeLen = totalCodeLen / total
	
	-- 计算平均分速
	local avgV = tableSum(input_stats.monthly.avgGaps)
	if avgV > 1 then
		avgV = tableSum(input_stats.monthly.avgCnts) / avgV * 60
	end
	
	strTable[1] = '※ 月统计：'
	strTable[3] = string.format('上屏 %d 次',s.count)
	strTable[4] = string.format('输入 %d 字',s.length)
	strTable[5] = string.format('最大分速 %.1f 字%s',s.fastest, maxSpdDesc)
	strTable[6] = string.format('平均分速 %.1f 字',avgV)
	strTable[7] = string.format('平均码长 %.1f%s',avgCodeLen, avgCodeLenDesc)
	strTable[9] = string.format('单字占比：%.0f％',ratio1)
	strTable[10] = string.format('2字词占比：%.0f％',ratio2)
	strTable[11] = string.format('>2字词占比：%.0f％',ratio3)
	if codeTableFirstN[1].ratio > 0 then
		strTable[13] = string.format('%s码占比：%.1f％', codeTableFirstN[1].codeLen, codeTableFirstN[1].ratio)
	else
		strTable[13] = ''
	end
	if codeTableFirstN[2].ratio > 0 then
		strTable[14] = string.format('%s码占比：%.1f％', codeTableFirstN[2].codeLen, codeTableFirstN[2].ratio)
	else
		strTable[14] = ''
	end
	if codeTableFirstN[3].ratio > 0 then
		strTable[15] = string.format('%s码占比：%.1f％', codeTableFirstN[3].codeLen, codeTableFirstN[3].ratio)
	else
		strTable[15] = ''
	end
	if codeTableFirstN[4].ratio > 0 then
		strTable[16] = string.format('其它占比：%.1f％', codeTableFirstN[4].ratio)
	else
		strTable[16] = ''
	end
	
	return table.concat(strTable, '\n')
end

-- 显示函数（年统计）
local function format_yearly_summary()
	local s = input_stats.yearly
	if s.count == 0 then return "※ 本年没有任何记录。" end
	
	-- 统计各类输入组合的占比
	local val1 = s.lengths[1] or 0  -- 防止索引不存在时报错，默认0
	local val2 = (s.lengths[2] or 0) * 2
	local val3 = 0
	local total = 0
	for key, value in pairs(s.lengths) do
		total = total + key * value  -- 累加所有值
	end
	if total == 0 then total = 1 end  -- 防止除以0报错
	val3 = total - val1 - val2
	local ratio1 = (val1 / total) * 100
	local ratio2 = (val2 / total) * 100
	local ratio3 = (val3 / total) * 100
	
	-- 统计码长的占比（分类为：频率最高的3种码长，和其它码长）
	local codeTable_sorted = {}
	local totalCodeLen = 0	-- 总码长
	local totalCodeCnt = 0	-- 总码数
	local codeTypeCnt = 0	-- 码长的种类数量
	for k,v in pairs(s.codeLengths) do
		totalCodeLen = totalCodeLen + v * k
		totalCodeCnt = totalCodeCnt + v
		codeTypeCnt = codeTypeCnt + 1
		table.insert(codeTable_sorted, {clen=k,count=v})
	end
	table.sort(codeTable_sorted, function(a,b)
		return a.count > b.count
		end)
	if totalCodeCnt == 0 then totalCodeCnt = 1 end	-- 防止除以0报错
	local codeTableFirstN = {}
	local ratioSumOfFirstN = 0
	for i = 1, 3 do
		if i <= codeTypeCnt then
			codeTableFirstN[i] = {codeLen = codeTable_sorted[i].clen, ratio = codeTable_sorted[i].count / totalCodeCnt * 100}
		else
			codeTableFirstN[i] = {codeLen = 0, ratio=0}
		end
		ratioSumOfFirstN = ratioSumOfFirstN + codeTableFirstN[i].ratio
	end
	codeTableFirstN[4] = {codeLen = 0, ratio = 100 - ratioSumOfFirstN}
	-- 计算平均码长
	local avgCodeLen = totalCodeLen / total
	
	-- 计算平均分速
	local avgV = tableSum(input_stats.yearly.avgGaps)
	if avgV > 1 then
		avgV = tableSum(input_stats.yearly.avgCnts) / avgV * 60
	end
	
	strTable[1] = '※ 年统计：'
	strTable[3] = string.format('上屏 %d 次',s.count)
	strTable[4] = string.format('输入 %d 字',s.length)
	strTable[5] = string.format('最大分速 %.1f 字%s',s.fastest, maxSpdDesc)
	strTable[6] = string.format('平均分速 %.1f 字',avgV)
	strTable[7] = string.format('平均码长 %.1f%s',avgCodeLen, avgCodeLenDesc)
	strTable[9] = string.format('单字占比：%.0f％',ratio1)
	strTable[10] = string.format('2字词占比：%.0f％',ratio2)
	strTable[11] = string.format('>2字词占比：%.0f％',ratio3)
	if codeTableFirstN[1].ratio > 0 then
		strTable[13] = string.format('%s码占比：%.1f％', codeTableFirstN[1].codeLen, codeTableFirstN[1].ratio)
	else
		strTable[13] = ''
	end
	if codeTableFirstN[2].ratio > 0 then
		strTable[14] = string.format('%s码占比：%.1f％', codeTableFirstN[2].codeLen, codeTableFirstN[2].ratio)
	else
		strTable[14] = ''
	end
	if codeTableFirstN[3].ratio > 0 then
		strTable[15] = string.format('%s码占比：%.1f％', codeTableFirstN[3].codeLen, codeTableFirstN[3].ratio)
	else
		strTable[15] = ''
	end
	if codeTableFirstN[4].ratio > 0 then
		strTable[16] = string.format('其它占比：%.1f％', codeTableFirstN[4].ratio)
	else
		strTable[16] = ''
	end
	
	return table.concat(strTable, '\n')
end

-- 显示记录的生字/词
local function format_shengzi()
	if input_stats.newWords == nil then
		return string.format("※ 未发现生字/词记录。")
	end
	
	local tmpTable = {}
	local newWords = {}
	local verStr = strTable[#strTable]
	local cnt = 0
	local i = 1
	tmpTable[1] = ""
	for k, v in pairs(input_stats.newWords) do
		i = i + 1
		cnt = #v
		tmpTable[i] = string.format("%s：%d次，t\204\133 = %0.1fs", k, cnt, tableSum(v)/cnt)
		table.insert(newWords, k)
	end
	tmpTable[1] = string.format("共有 %d 个生字/词：", i - 1)	-- 设置表头
	
	tmpTable[i + 1] = splitor
	tmpTable[i + 2] = table.concat(newWords, '，')
	tmpTable[i + 3] = splitor
	tmpTable[i + 4] = verStr
	
	if i < 2 then
		return string.format("※ 未发现生字/词记录。")
	else
		return table.concat(tmpTable, '\n')
	end
end

-- 加载保存的统计数据（input_stats.lua）
local function load_stats_from_lua_file()
	local path = rime_api.get_user_data_dir() .. "/lua/input_stats.lua"
	local ok, result = pcall(function()
		local env = {}
		local f = loadfile(path, "t", env)
		if f then f() end
		return env.input_stats
	end)
	if ok and type(result) == "table" then
		input_stats = result
	else
		-- 保底初始化，防止错误
		input_stats = {
			daily = {count = 0, length = 0, fastest = 0, ts = 0, lengths = {}, codeLengths = {}, avgGaps = {}, avgCnts = {}},
			weekly = {count = 0, length = 0, fastest = 0, ts = 0, lengths = {}, codeLengths = {}, avgGaps = {}, avgCnts = {}},
			monthly = {count = 0, length = 0, fastest = 0, ts = 0, lengths = {}, codeLengths = {}, avgGaps = {}, avgCnts = {}},
			yearly = {count = 0, length = 0, fastest = 0, ts = 0, lengths = {}, codeLengths = {}, avgGaps = {}, avgCnts = {}},
			daily_max = 0,
			newWords = {}
		}
	end
end

-- 翻译器：处理统计命令
local function translator(input, seg, env)
	-- 判断是否在连续输入状态下
	local timeNow = os.time()
	if timeNow - avgSpdInfo.clickTime > avgSpdInfo.gapThd then	-- 如果距离上次按键超时了，即输入已经中断，这是重新开始的输入行为
		if avgSpdInfo.commitTime - avgSpdInfo.startTime >= 1 and avgSpdInfo.count > 0 then
			-- 此时的统计数据是有效
			update_stats(0, 0, 1)
		end
		
		-- 切换统计状态为未启动状态
		avgSpdInfo.logSts = 0
	end
	if 0 == avgSpdInfo.logSts then	-- 如果当前没有进行统计，则此次按键事件会触发统计启动动作
		-- 启动平均分速统计
		avgSpdInfo.logSts = 1
		-- 清除计时和计数
		avgSpdInfo.startTime = timeNow
		avgSpdInfo.commitTime = timeNow
		avgSpdInfo.count = 0
	end
	avgSpdInfo.clickTime = timeNow
	
	if input:sub(1, 1) ~= "/" then return end
	local summary = ""
	local avgAvailable = 0
	if avgSpdInfo.commitTime - avgSpdInfo.startTime >= 1 and avgSpdInfo.count > 0 then avgAvailable = 1 end
	if input == "/01" or input == "/rtj" then
		if avgAvailable == 1 then	-- 如果此时已经有统计数据，则记录该统计数据
			update_stats(0, 0, 1)
		end
		summary = format_daily_summary()
	elseif input == "/02" or input == "/ztj" then
		if avgAvailable == 1 then update_stats(0, 0, 1) end
		summary = format_weekly_summary()
	elseif input == "/03" or input == "/ytj" then
		if avgAvailable == 1 then update_stats(0, 0, 1) end
		summary = format_monthly_summary()
	elseif input == "/04" or input == "/ntj" then
		if avgAvailable == 1 then update_stats(0, 0, 1) end
		summary = format_yearly_summary()
	elseif input == "/05" or input == "/sztj" then
		if avgAvailable == 1 then update_stats(0, 0, 1) end
		summary = format_shengzi()
	elseif input == "/008" or input == "/qcsz" then
		input_stats.newWords = {}
		summary = "※ 生字词已清空。"
	elseif input == "/009" or input == "/qctj" then
		input_stats = {
			daily = {count = 0, length = 0, fastest = 0, ts = 0, lengths = {}, codeLengths = {}, avgGaps = {}, avgCnts = {}},
			weekly = {count = 0, length = 0, fastest = 0, ts = 0, lengths = {}, codeLengths = {}, avgGaps = {}, avgCnts = {}},
			monthly = {count = 0, length = 0, fastest = 0, ts = 0, lengths = {}, codeLengths = {}, avgGaps = {}, avgCnts = {}},
			yearly = {count = 0, length = 0, fastest = 0, ts = 0, lengths = {}, codeLengths = {}, avgGaps = {}, avgCnts = {}},
			daily_max = 0,
			newWords = {}
		}
		save_stats()
		summary = "※ 所有统计数据已清空。"
	end

	if summary ~= "" then
		yield(Candidate("stat", seg.start, seg._end, summary, ""))
	end
end

local function init(env)
	local ctx = env.engine.context
	-- 加载历史统计数据
	load_stats_from_lua_file()
	
	-- 初始化统计字符串
	strTable[1] = ''
	strTable[2] = splitor
	strTable[3] = ''
	strTable[4] = ''
	strTable[5] = ''
	strTable[6] = ''
	strTable[7] = ''
	strTable[8] = splitor
	strTable[9] = ''
	strTable[10] = ''
	strTable[11] = ''
	strTable[12] = splitor
	strTable[13] = ''
	strTable[14] = ''
	strTable[15] = ''
	strTable[16] = ''
	strTable[17] = splitor
	strTable[18] = '◉ 方案：'..schema_name
	strTable[19] = '◉ 平台：'..software_name..' '..software_version
	strTable[20] = splitor
	strTable[21] = '脚本：₂₀₂₅1210・C'

	-- 注册提交通知回调
	ctx.commit_notifier:connect(function()
		local commit_text = ctx:get_commit_text()
		if not commit_text or commit_text == "" then return end
		
		-- 如果输入与上屏内容一致，例如编码上屏，则不统计此项
		if ctx.input == commit_text then return end
		
		-- 如果输入是以 / 引导的，则不统计这个输入项
		if ctx.input:find("^/") then return end

		-- 如果是标点符号，则不进行统计
		if commit_text:match("^[！!@#$％^&?,.;？，。；/0123456789]+$") then return end
		
		local input_length = utf8.len(commit_text) or string.len(commit_text)
		-- 统计平均分速
		if 1 == avgSpdInfo.logSts then	-- 如果当前正在统计中
			local timeNow = os.time()
			local delt = timeNow - avgSpdInfo.commitTime
			
			-- 更新上屏时间
			avgSpdInfo.commitTime = timeNow
			-- 记录输入字数
			avgSpdInfo.count = avgSpdInfo.count + input_length
			
			-- 如果卡壳了(但是间隔时间小于Xs)，记录这个字/词
			if delt > boggleThd_s then
				if input_stats.newWords[commit_text] ~= nil then
					table.insert(input_stats.newWords[commit_text], delt)
				else
					input_stats.newWords[commit_text] = {delt}
				end
			elseif delt < boggleThd_s then
				-- 没有卡壳，则消除对该字的记录
				input_stats.newWords[commit_text] = nil
			end
		end
		
		-- 上屏统计
		update_stats(input_length, string.len(ctx.input) + codeLenOffset, 0)
		save_stats()
	end)
end
return { init = init, func = translator }