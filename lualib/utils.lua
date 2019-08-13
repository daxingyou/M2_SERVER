-- local crypt = require "skynet.crypt"
-- local hmac = crypt.hmac_sha1
-- local base64encode = crypt.base64encode
-- local md5 = require "md5"
-- local httpc = require("http.httpc")
local utils = {}

function utils:getFileName(path)
    return string.match(path, ".+/([^/]*%.%w+)$")
end

--下载文件
--http://lsjgame.oss-cn-hongkong.aliyuncs.com/HotUpdate/index.html

--上传文件
--example: bucket_name=lsjgame path=HotUpdate/test2.txt content为字符串或者字节流
--host = "lsjgame.oss-cn-hongkong.aliyuncs.com"
function utils:ossRequest(host,bucket_name,path,content)
    local access_key_id = "LTAI7X831y2ygKTf"
    local access_key_secret = "kyhihlZhrneTp856smDukaBEbY2foU"
 
    local method = "PUT"
    --要转换成0时区的时间,而不是本地时间
    local now = os.date("!%a, %d %b %Y %X GMT") 
    --经过base64的md5码
    local md5code = base64encode(md5.sum(content))
    --传输的大小
    local length = #content
    --二进制流方式传输
    local content_type = "application/octet-stream"
    --文件名
    local file_name = self:getFileName(path)
    --校验字符串
    local signature = base64encode(hmac(access_key_secret,
                method .. "\n"
                .. md5code .. "\n"
                ..content_type.."\n" 
                .. now .. "\n"
                ..string.format("/%s/%s",bucket_name,path)
                ))

    local authorization = "OSS " .. access_key_id .. ":" .. signature

    
    local headers = {
                        ["authorization"] = authorization,
                        ["date"] = now,
                        ["content-type"] = content_type,
                        ["content-length"] = length,
                        ["content-disposition"] = file_name,
                        ["content-md5"] = md5code
                    }

    local status ,body = httpc.request(method,host, "/"..path, nil, headers, content,true)
    if tonumber(status) ~= 200 then
        print("error:=>status=",status)
        print("msg=\n",body)
        return false
    end

    print("---------put success-------")

    return true
end


--洗牌  FisherYates洗牌算法
--算法的思想是每次从未选中的数字中随机挑选一个加入排列，时间复杂度为O(n)
function utils:fisherYates(card_list)
    for i = #card_list,1,-1 do
        --在剩余的牌中随机取一张
        local j = math.random(i)
        --交换i和j位置的牌
        local temp = card_list[i]
        card_list[i] = card_list[j]
        card_list[j] = temp
    end
    return card_list
end

--A~Z 65-90 所以最高支持format为36进制
--10进制转换目标进制
function utils:binaryConversion(format,value)
    assert(format <= 36,"unsupport format too biger")
    local list = {}
    repeat
        local var = value%format
        if var > 9 then
            var = string.char(55+var)
        end
        table.insert(list,1,var)
        value = math.floor(value/format)
    until (value == 0)
    return table.concat(list,"")
end

--生成36进制的玩家ID
function utils:generalUserId(serverId,instanceId)
    local id = tonumber(serverId .. string.format("%07d",intId))
    return self:binaryConversion(36,id)
end

local function dump_value_(v)
    if type(v) == "string" then
        v = "\"" .. v .. "\""
    end
    return tostring(v)
end

function utils:dump(value, description, nesting)
    if type(nesting) ~= "number" then nesting = 3 end

    local lookupTable = {}
    local result = {}

    local traceback = string.split(debug.traceback("", 2), "\n")
    print("dump from: " .. string.trim(traceback[3]))

    local function dump_(value, description, indent, nest, keylen)
        description = description or "<var>"
        local spc = ""
        if type(keylen) == "number" then
            spc = string.rep(" ", keylen - string.len(dump_value_(description)))
        end
        if type(value) ~= "table" then
            result[#result +1 ] = string.format("%s%s%s = %s", indent, dump_value_(description), spc, dump_value_(value))
        elseif lookupTable[tostring(value)] then
            result[#result +1 ] = string.format("%s%s%s = *REF*", indent, dump_value_(description), spc)
        else
            lookupTable[tostring(value)] = true
            if nest > nesting then
                result[#result +1 ] = string.format("%s%s = *MAX NESTING*", indent, dump_value_(description))
            else
                result[#result +1 ] = string.format("%s%s = {", indent, dump_value_(description))
                local indent2 = indent.."    "
                local keys = {}
                local keylen = 0
                local values = {}
                for k, v in pairs(value) do
                    keys[#keys + 1] = k
                    local vk = dump_value_(k)
                    local vkl = string.len(vk)
                    if vkl > keylen then keylen = vkl end
                    values[k] = v
                end
                table.sort(keys, function(a, b)
                    if type(a) == "number" and type(b) == "number" then
                        return a < b
                    else
                        return tostring(a) < tostring(b)
                    end
                end)
                for i, k in ipairs(keys) do
                    dump_(values[k], k, indent2, nest + 1, keylen)
                end
                result[#result +1] = string.format("%s}", indent)
            end
        end
    end
    dump_(value, description, "- ", 1)

    for i, line in ipairs(result) do
        print(line)
    end
end













--------------
--string 扩展方法
-------------

function string.split(input, delimiter)
    local arr = {}
    string.gsub(input, '[^'..delimiter..']+', function(w) table.insert(arr, w) end)
    return arr
end

function string.trim(input)
    input = string.gsub(input, "^[ \t\n\r]+", "")
    return string.gsub(input, "[ \t\n\r]+$", "")
end

return utils