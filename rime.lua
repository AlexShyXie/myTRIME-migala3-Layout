-- version: 1.0.1

-- 日期/时间格式化
function date_translator(input, seg)
	-- Candidate(type, start, end, text, comment)
	if (input == "date") then
		yield(Candidate("date", seg.start, seg._end, os.date("%Y-%m-%d"), "日期"))
		yield(Candidate("date", seg.start, seg._end, os.date("%Y年%m月%d日"), "日期"))
	elseif (input == "time") then
		yield(Candidate("time", seg.start, seg._end, os.date("%H:%M:%S"), "时间"))
	elseif (input == "dt" or input == "dtime") then
		yield(Candidate("dtime", seg.start, seg._end, os.date("%Y-%m-%d %H:%M:%S"), "日期时间"))
		yield(Candidate("dtime", seg.start, seg._end, os.date("%Y-%m-%dT%H:%M:%S"), "日期时间"))
	end
end

-- 过滤器：候选短的优先
function short_first_filter(input)
	-- 如何确认已输入编码的长度?
	-- 1. 单字优先
	local phrase = {}	-- 非单字的词组
	for cand in input:iter() do
		if (utf8.len(cand.text) == 1) then
			yield(cand) -- 为单字生成候选项
		else
			table.insert(phrase, cand) -- 词组先放到phrase中
		end
	end
	-- 2. 短词优先
	table.sort(phrase, function(a, b) 
		return utf8.len(a.text) < utf8.len(b.text)
	end)
	for i, cand in ipairs(phrase) do
		yield(cand)
	end
end
