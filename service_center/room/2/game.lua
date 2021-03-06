
local skynet = require "skynet"
-- local Room = require "Room"
local constant = require "constant"
local ALL_CARDS = constant.ALL_CARDS
-- local RECOVER_GAME_TYPE = constant.RECOVER_GAME_TYPE
-- local ALL_CARDS = constant.ALL_CARDS
local GAME_CMD = constant.GAME_CMD
local NET_RESULT = constant.NET_RESULT
local PLAYER_STATE = constant.PLAYER_STATE
local ZJ_MODE = constant.ZJ_MODE
local PUSH_EVENT = constant.PUSH_EVENT
local GANG_TYPE = constant.GANG_TYPE
local GAME_OVER_TYPE = constant.GAME_OVER_TYPE
local cjson = require "cjson"
local JudgeCard = require("2.judgeCard")


local conf = require("2.conf")
local log = require "skynet.log"

local game = {}
local game_meta = {}
setmetatable(game,game_meta)
game.__index = game_meta
game.__newindex = game_meta

function game:clear()
	local game_meta = {}
	setmetatable(game,game_meta)
	game.__index = game_meta
	game.__newindex = game_meta
end

function game:fisherYates()
	for i = #self.card_list,1,-1 do
		--在剩余的牌中随机取一张
		local j = math.random(i)
		--交换i和j位置的牌
		local temp = self.card_list[i]
		self.card_list[i] = self.card_list[j]
		self.card_list[j] = temp
	end
end

-- 开始游戏
function game:start(room, bRepate)
	print("ddz, start()")
	self.room = room

	-- 不是重开局的时候才会加1
	-- if not bRepate then
	-- 	self.room.cur_round = self.room.cur_round + 1
	-- end

	print("self.room.cur_round", self.room.cur_round)

	self.other_setting = self.room.other_setting
	--底分
	self.base_score = self.other_setting[1]
	self.iRoomTime = self.other_setting[1]
	self.waite_operators = {}
	
	self:initGame()
	-- 发牌，
	self:dealCardServer()
	self:demandPointServer()
end

function game:dealCardServer( ... )
	print("ddz, dealCardServer()")
	local players = self.room.player_list
	-- 每人先发13张牌
	local iHandCards = {}
	for i = 1, 3 do 
		iHandCards[i] = {} 
		for j = 1, 20 do 
			iHandCards[i][j] = 0
		end
	end

	for i = 1, 3 do 
		for j = 1, 17 do 
			iHandCards[i][j] = self.card_list[((i-1)*17 + j)]
			-- print(string.format("发牌iHandCards[%d][%d] = [%d]", i, j, iHandCards[i][j]))
		end	


		print("conf", cjson.encode(conf)) 
		-- 配牌
		if conf and conf.isUserMake and conf.isUserMake == true and conf["isOpen"..i] == true then
			for j = 1, 17 do 
				if conf["card" .. i] and conf["card" .. i][j] then
					iHandCards[i][j] = conf["card" .. i][j]
				end
			end
		end

		players[i].handle_cards = iHandCards[i]
		self.waite_operators[players[i].user_pos] = "WAIT_DEAL_FINISH"
	end

	-- 当前玩家剩余的排数 
	-- 底牌
	for i = 54, 52, -1 do 
		table.insert(self.baseCard, self.card_list[i])		
	end

	for index = 1, 3 do
		local player = self.room:getPlayerByPos(index)
		local cards = players[index].handle_cards
		local rsp_msg = {}
		rsp_msg.cards = cards
		rsp_msg.user_pos = player.user_pos
		rsp_msg.cur_round = self.room.cur_round

		player:send({deal_card = rsp_msg})
	end
end

-- 游戏当前的数据会在这个里面，用self去表示
function game:initGame( ... )
	print("game::initGame")
	math.randomseed(tostring(os.time()):reverse():sub(1, 6)) 
	self.card_list = {}
	local game_type = self.room.game_type

	for _,value in ipairs(ALL_CARDS[game_type]) do
		table.insert(self.card_list,value)
	end

	--洗牌
	self:fisherYates()
	self.other_setting = self.room.other_setting
	--底分
	self.base_score = self.other_setting[1]
	-- 是否是欢乐斗地主
	self.bHuanLe = self.other_setting[2] == 2
	-- 封顶数
	self.iMaxBoom = self.other_setting[3] or 3
	-- 当前操作状态
	self.waite_operators = {}
	--当前出牌的位置
	self.iCurPlayExtraNum = 0
	-- 叫分
	self.iDemandPoint = {0, 0, 0}
	-- 是否叫过分
	self.bDemand = {false, false, false}
	-- 底牌
	self.iBaseCard = {0, 0, 0}	
	-- 当前叫分玩家
	self.iCurDemandPlayer = 0
	-- 当前地主
	self.iLandOwer = 0
	-- 是否加倍
	self.bDoubleTime = {false, false, false}
	-- 地主出了几手牌 用来判断春天
	self.iTurn = 0
	-- 出的牌, 到时候扔进去, 最后填0 
	self.cSendCards = {{}, {}, {}}
	-- 当前出的牌的类型（用于断线重新连接的时候）
	self.cSendNum = {{}, {}, {}}

	for i = 1, 3 do 
		for j = 1, 20 do
			self.cSendNum[i][j] = 0
		end
	end
	-- first 
	self.iFirstDemand = 0
	-- 当前桌面上牌权的人 
	self.iTablePlayer = 0
	-- 当前桌子上的牌，用来判断后面牌的合法性
	self.cTableCard = {} -- 长度20数组
	-- 当前的倍数
	self.iNowBoom = 0
	-- 当前的底牌
	self.baseCard = {}
	-- 当前的最高的叫分
	self.iMaxPoint = 0
	-- 当局的底分
	self.iAmountResult = {0, 0, 0}
end

function game:demandPointServer( )
	-- local iRoundIndex = self.room.cur_round
	self.iCurDemandPlayer = math.floor(math.random(100) % 3 ) + 1
	local data = { userExtra = self.iCurDemandPlayer, userNowDemand = self.iMaxPoint, userPoint = self.iDemandPoint,};

	-- dump(data, "SERVER_POINT_DEMAND:data")
	for k,v in pairs(data) do
		print(k, v)
	end

	--通知所有人 现在让玩家叫地主
	self.room:broadcastAllPlayers("ServerPointDemand", data)
end

-- 获取下面三张牌的方法
function game:getBaseCard( ... )
	return self.baseCard
end

-- 客户端叫分通知
game["DEMAND"] = function(self, player, data)
	

	print("game :: DEMAND", player.user_pos, cjson.encode(data))

	local pos = player.user_pos
		
	if self.bDemand[pos] == true and self.iFirstDemand ~= pos then
		print(string.format("ERROR, bDemand[%d][%d], iFirstDemand = [%d]", pos,  self.bDemand[pos], self.iFirstDemand))	
		return "IS_DEMAND_POINT"
	end

	self.bDemand[pos] = true

	local bTempDemand = false
	-- 0  不叫
	if data.demandPoint == 0 then
		self.iDemandPoint[pos] = 0
		bTempDemand = false
	else -- 欢乐斗地主，只记录一分
		self.iDemandPoint[pos] = data.demandPoint  -- 欢乐斗地主只会传1和0
		bTempDemand = true
		if self.iFirstDemand == 0 then
			self.iFirstDemand = pos    -- 记录第一个叫分的人s
		end
	end

	-- 统计下叫分的情况
	local iDemandNums = 0
	-- 看下是否是只有一个人叫了地主
	local iDemandPlayNums = 0

	if not self.iMaxPoint then
		self.iMaxPoint = 0
	end
	log.info("--------------------------------------")
	log.info("self.iMaxPoint = ", self.iMaxPoint)
	log.info("self.iDemandPoint = ", cjson.encode(self.iDemandPoint))

	for i = 1, 3 do 
		if self.iDemandPoint[i] > self.iMaxPoint then
			self.iMaxPoint = self.iDemandPoint[i]
		end

		-- 有多少人叫了分数
		if self.iDemandPoint[i] > 0 then
			iDemandPlayNums = iDemandPlayNums + 1
		end
		-- 记录已经叫或者不叫多少个人了
		if self.bDemand[i] == true then
			iDemandNums = iDemandNums + 1
		end
	end

	local NPDmsg = {
		userExtra = player.user_pos,
		userDemand = data.demandPoint,
		nowTableTime = self.iRoomTime,
	}

	-- 通知玩家叫或者不叫
	self.room:broadcastAllPlayers("NoticePointDemand", NPDmsg)


	-- 叫了三分， 直接就是地主了
	if data.demandPoint == 3 then

		self.iRoomTime = 3
		self.iMainPlayer = pos  -- 这个人就是地主
		self.iCurPlayExtraNum = self.iMainPlayer

		local data = {userExtra = self.iMainPlayer, baseCard = {}, nowTableTime = self.iRoomTime,}
		local baseCard = self:getBaseCard()
		-- local player = self.room:getPlayerByPos(tempExtra)
		-- for i, v in pairs(baseCard) do 
		-- 	table.insert(player.handle_cards, v)
		-- end
		for i = 1, 3 do 
			for j = 1, 20 do 
				if player.handle_cards[j] == 0 then
					player.handle_cards[j] = baseCard[i]
					break
				end
			end
		end

		data.baseCard = baseCard
		self.room:broadcastAllPlayers("NoticeMainPlayer", data)

		-- 是否允许加倍（欢乐斗地主允许, 留个空, 没有加倍规则, 就出牌）
		-- if 0 then

		-- else
		-- 通知当前玩家出牌
		self:serverPushPlayCard(self.iCurPlayExtraNum)
		-- end

		return "success"
	elseif iDemandNums < 3 and self.iMaxPoint ~= 3 then  -- 经典斗地主, 没有叫三分，并且还有人没有叫分
		local next_pos = pos + 1

		if next_pos > 3 then
			next_pos = 1
		end
		-- local next_player = self.room:getPlayerByPos(next_pos)
		self.iCurDemandPlayer = next_pos

		local data = { 
			userExtra = self.iCurDemandPlayer, 
			userNowDemand = self.iMaxPoint,
			userPoint = self.iDemandPoint,
			};
		--通知所有人 现在 让 玩家叫地主
		self.room:broadcastAllPlayers("ServerPointDemand", data)
		return "success"
	else  -- 这个时候就应该是能分出来地主了

		
		-- 3个人都已经叫过分了， 检查下是否只有一个人叫
		if iDemandNums == 3 then
			-- 欢乐斗地主里面特有的
			if self.iFirstDemand == pos then
				if bTempDemand then
					self.iMainPlayer = self.iFirstDemand  -- 这个人就是地主
					self.iCurPlayExtraNum = self.iMainPlayer
										
					local data = {userExtra = self.iMainPlayer, baseCard = {}, nowTableTime = self.iRoomTime,}
					local baseCard = self:getBaseCard()
					local player = self.room:getPlayerByPos(tempExtra)
					for i, v in pairs(baseCard) do 
						table.insert(player.handle_cards, v)
					end
					data.baseCard = baseCard

					self.room:broadcastAllPlayers("NoticeMainPlayer", data)

					-- -- 通知当前玩家出牌
					self:serverPushPlayCard(self.iCurPlayExtraNum)
					return "success"
				else -- 坑上一个人的玩家， 就去找下上个是谁叫了

					local itemp = pos - 1
					if itemp <= 0 then
						itemp = 3
					end

					local tempExtra = 0
					for i = 1, 2 do 
						if self.iDemandPoint[itemp] > 0 then
							tempExtra = itemp
							break
						end

						itemp = itemp - 1
						if itemp <= 0 then
							itemp = 3
						end
					end

					if tempExtra == 0 then
						print("ERROR::tempExtra = ", tempExtra)
					end

					self.iMainPlayer = tempExtra  -- 这个人就是地主
					self.iCurPlayExtraNum = self.iMainPlayer

					local data = {userExtra = self.iMainPlayer, baseCard = {}, nowTableTime = self.iRoomTime,}
					local baseCard = self:getBaseCard()
					local player = self.room:getPlayerByPos(tempExtra)
					for i, v in pairs(baseCard) do 
						table.insert(player.handle_cards, v)
					end
					data.baseCard = baseCard
					self.room:broadcastAllPlayers("NoticeMainPlayer", data)
					-- 通知当前玩家出牌
					self:serverPushPlayCard(self.iCurPlayExtraNum)
					return "success"
				end
			end
			if iDemandPlayNums == 1 then

				self.iMainPlayer = self.iFirstDemand  -- 这个人就是地主
				self.iCurPlayExtraNum = self.iMainPlayer

				self.iRoomTime = self.iMaxPoint

				local data = {userExtra = self.iMainPlayer, baseCard = {}, nowTableTime = self.iRoomTime,}
				local baseCard = self:getBaseCard()

				local player = self.room:getPlayerByPos(tempExtra)
				for i, v in pairs(baseCard) do 
					table.insert(player.handle_cards, v)
				end

				data.baseCard = baseCard
				self.room:broadcastAllPlayers("NoticeMainPlayer", data)

				-- -- 通知当前玩家出牌
				self:serverPushPlayCard(self.iCurPlayExtraNum)
				return "success"
			elseif iDemandPlayNums > 0 then

				-- 欢乐斗地主，继续叫分
				if self.bHuanLe == true then
					local data = { userExtra = self.iFirstDemand, userNowDemand = self.iMaxPoint, userPoint = self.iDemandPoint,};
					self.room:broadcastAllPlayers("ServerPointDemand", data)
				else
					-- 谁的分数最大， 谁就是地主
					local iTempPos = 0
					for i = 1, 3 do 
						if self.iDemandPoint[i] == self.iMaxPoint then
							iTempPos = i
							break
						end
					end

					self.iMainPlayer = iTempPos -- 这个人就是地主
					self.iCurPlayExtraNum = self.iMainPlayer
					local data = {userExtra = self.iMainPlayer, baseCard = {}, nowTableTime = self.iRoomTime,}
					local baseCard = self:getBaseCard()

					local player = self.room:getPlayerByPos(iTempPos)
					for i, v in pairs(baseCard) do 
						table.insert(player.handle_cards, v)
					end

					data.baseCard = baseCard
					self.room:broadcastAllPlayers("NoticeMainPlayer", data)

					-- -- 通知当前玩家出牌
					self:serverPushPlayCard(self.iCurPlayExtraNum)
					return "success"
				end

				-- --通知所有人 现在 让 第一个玩家叫地主
				return "success"
			else
				-- 重新再来一次, 重新洗牌，重新发牌，再重新叫地主
				self:initGame()
				self:start(self.room, tr)
			end
		end  
	end

	return "success"
end
	


--通知玩家出牌
function game:serverPushPlayCard(iTableExtraNum)
	local players = self.room.player_list

	local cardNums = {0, 0, 0}
	-- for i = 1, 3 do 
	-- 	-- 统计一下牌数, 
	-- 	cardNums[i] = #players[i].handle_cards
	-- end
	for i = 1, 3 do
		for k, v in pairs(players[i].handle_cards) do 
			if v ~= 0 then
				cardNums[i] = cardNums[i] + 1		
			end
		end
	end


-- 	message PushPlayCard {
-- 	required int32 user_id = 1;
-- 	optional int32 user_pos = 2;
-- 	optional int32 operator = 3;   		// 2代表碰牌之后的出牌 1代表摸牌之后的出牌
-- 	repeated int32 card_list = 4;  		//玩家的手牌
-- 	repeated GPItem card_stack = 5;		//碰、杠、吃列表

-- 	// ddz
-- 	repeated int32 userCardNum = 6;

-- 	repeated FourCardItem four_card_list = 7;
-- }

	for i, player in ipairs(players) do
		local rsp_msg = {user_pos = iTableExtraNum}
		rsp_msg.user_id = player.user_id
		rsp_msg.userCardNum = cardNums
		if player.user_pos == iTableExtraNum then
			rsp_msg.card_list = player.handle_cards
		end
		player:send({push_play_card = rsp_msg})
		print("serverPushPlayCard通知玩家出牌", cjson.encode(rsp_msg))	
	end
end

--发牌完毕
game["DEAL_FINISH"] = function(self,player)

	local user_pos = player.user_pos
	if self.waite_operators[user_pos] ~= "WAIT_DEAL_FINISH" then
		return "invaild_operator"
	end
	self.waite_operators[user_pos] = nil
	--计算剩余的数量
	local num = 3
	for k,v in pairs(self.waite_operators) do
		num = num - 1
	end

	if num == 1 then
		--庄家出牌
	end
	return "success"
end



function game:handlingError(...)
	print("-------------------handlingError---------------------", ...)
end


--出牌
game["PLAY_CARD"] = function(self,player,data)
	-- if self.waite_operators[player.user_pos] ~= "WAIT_PLAY_CARD" then
	-- 	return "invaild_operator"
	-- end

	if self.iCurPlayExtraNum ~= player.user_pos then
		print ("非法的出牌, 不是当前玩家出牌")
		return "invaild_operator"
	end

	-- if not data.cardList then
	-- 	return "paramater_error"
	-- end

	-- 检测手牌
	local nodePlayer = player
	local iTableNumExtra = player.user_pos

	local cCards = data.cardList or {}
	local iCardType = data.nowType
	local iCardValue = data.nowValue
	local iCardNum = data.cardNums


	if #cCards ~= iCardNum then
		print(string.format("ERROR::card = [%d],iCardNum = [%d] ", #cCards, iCardNum))
	end
	print("cCards = ", cjson.encode(cCards))
	print("player.handle_cards = ", cjson.encode(player.handle_cards))



	-- 这手牌是否为Pass
	local isPass = false

	if iCardNum == 0 then
		isPass = true
	end


	-- 判断下是否是当前的牌权，如果是当前的牌权， 就直接干掉
	if self.iTablePlayer == iTableNumExtra then
		print(string.format("ERROR::cCards = [%d],iCardNum = [%d] ", #cCards, iCardNum))
	end

	local cCardTemp = {}
	for i, v in pairs(player.handle_cards) do 
		table.insert(cCardTemp, v)
	end

	local iOldType;
	local iOldValue;
	local iNowType;
	local iNowValue;

	if isPass == false then
		if iTableNumExtra == self.iMainPlayer then
			self.iTurn = self.iTurn + 1
		end

		-- 在这里判断扑克牌的存在合法性（如果不是Pass，才需要判断）
		for i = 1, 20 do 
			if not cCards[i] then
				break
			end

			local bFind = false
			for j = 1, 20 do 
				if cCardTemp[j] and cCardTemp[j] > 0 then
					if cCardTemp[j] == cCards[i] then
						bFind = true
						cCardTemp[j] = 0
						break
					end
				end	
			end

			if bFind == false then
				local error_msg = string.format("没有找到这张牌[%d][%d]", i, cCards[i])
				self:handlingError(error_msg)
				print("cCardTemp", cjson.encode(cCardTemp))

				return "ERROR"
			end
		end

		local temp = {}
		local iCardsCount = 0

		for i = 1, 20 do 
			if cCards[i] then
				temp[i] = math.floor(cCards[i] % 100)
				iCardsCount = iCardsCount + 1
			end
		end

		-- temp, iCardsCount, iNowValue)
		-- 判断合法之后，在判断牌型
		iNowType, iNowValue = JudgeCard:JudgeCardShape( temp, iCardsCount, iNowValue)		
		if iNowType ~= iCardType or iNowValue ~= iCardValue then
			local error_msg = string.format("ddz牌型牌值错误iNowType[%d]iCardType[%d]iNowValue[%d]iCardValue[%d]", iNowType, iCardType, iNowValue, iCardValue)
			self:handlingError(error_msg)
			return "ERROR"
		end

		if iNowType == -1 then
			local error_msg = string.format("ddz牌型牌值错误iNowType[%d]iCardType[%d]iNowValue[%d]iCardValue[%d]", iNowType, iCardType, iNowValue, iCardValue)
			self:handlingError(error_msg)
			return "ERROR"
		end

		-- 检测是否和当前桌面上的牌保持一致
		iCardsCount = 0
		temp = {}
		for i = 1, 20 do 
			if cCards[i] then
				temp[i] = math.floor(cCards[i] % 100)
				iCardsCount = iCardsCount + 1
			end
		end

		iOldType, iOldValue = JudgeCard:JudgeCardShape(temp, iCardsCount, iOldValue);

		local iAllow = 0
		if ((iNowValue == -1) or (iOldValue < 1 ) or (iOldType < 0)or (iOldType==iNowType and iNowValue>iOldValue) or (iNowType == JudgeCard.TYPE_ROCKET_CARD) or ( iNowType == TYPE_BOMB_CARD and iOldType  ~= JudgeCard.TYPE_BOMB_CARD and iOldType ~= JudgeCard.TYPE_ROCKET_CARD)) then
			-- local error_msg = string.format("ddz牌型牌值错误,  没有当前桌面上的牌值大iNowType[%d]iCardType[%d]iNowValue[%d]iCardValue[%d]", iNowType, iCardType, iNowValue, iCardValue)
			-- self:handlingError(error_msg)
			-- return "ERROR"

			iAllow = 1;
		end

		if iTableNumExtra ~= self.iCurPlayExtraNum then
			if(iAllow==0) then
				-- 踢人动作
				local error_msg = string.format("玩家出的牌没桌面上的牌大，可能用外挂，逃跑处理iNowType[%d]iCardType[%d]iNowValue[%d]iCardValue[%d]", iNowType, iCardType, iNowValue, iCardValue)
				self:handlingError(error_msg)
				return "ERROR"
			end
		end


		if (iNowType == JudgeCard.TYPE_ROCKET_CARD or iNowType == JudgeCard.TYPE_BOMB_CARD) then
			
			if self.iNowBoom < self.iMaxBoom then
				self.iRoomTime = self.iRoomTime * 2
			end
			-- 不管几炸， 全部都加上去
			self.iNowBoom = self.iNowBoom + 1
		end

		-- 删除手中的牌(手牌20张， 值可能为0 但是不会为空)
		for k = 1, 20 do
			if not cCards[k] then
				break
			end 
			for z = 1, 20 do 
				local bFind = false
				if player.handle_cards[z] == cCards[k] then
					bFind = true
					player.handle_cards[z] = 0
					print("找到了一张牌，k, z ", k, z)
					break
				end
				if bFind then
					break
				end
			end			
		end
		print("player.handle_cards after delete = ", cjson.encode(player.handle_cards))

		-- 标记现在桌面上出牌的人是谁（牌权）
		self.iCurPlayExtraNum = iTableNumExtra;
	else  
		-- 如果是Pass的话

		iNowType = 0;    -- 牌型置0
		iNowValue = 0;   -- 键牌值置0
	end


	-- 确定剩下的牌数

	local iCardLeft = 0

	for i = 1, 20 do 
		if player.handle_cards[i] ~= 0 then
			iCardLeft = iCardLeft + 1
		end
	end

	-- 通知出牌
	local msgNotice = {}

	-- cardList
	msgNotice.cCards = cCards
	msgNotice.userExtra = iTableNumExtra
	msgNotice.cCardNum = iCardNum
	msgNotice.cCardType = iCardType
	msgNotice.cCardValue = iCardValue

	-- 剩余牌数， 给前端显示用
	msgNotice.cLestCardNum = iCardLeft
	msgNotice.nowTableTime = self.iRoomTime
	self.room:broadcastAllPlayers("NoticeSendCard", msgNotice)
	print("iTableNumExtra == ", iTableNumExtra)

	-- 扔在自己出牌的数组里面
	for j = 1, iCardNum do 
		for i = 1, 20 do 
			if self.cSendCards[iTableNumExtra][i] == nil then	
				self.cSendCards[iTableNumExtra][i] =  cCards[j]
				break
			end 
		end
	end

	for i = 1, 20 do 
		while true do 
			if self.cSendNum[iTableNumExtra][i] ~= 0 then
				break;
			end

			if iCardType == JudgeCard.TYPE_ROCKET_CARD then
				self.cSendNum[iTableNumExtra][i] = 100
			elseif iCardType == JudgeCard.TYPE_BOMB_CARD then
				self.cSendNum[iTableNumExtra][i] = 99
			else
				self.cSendNum[iTableNumExtra][i] = iCardNum
			end
			break
		end	
	end

	-- 牌局结束,  算分
	if iCardLeft == 0 then
		local bIfSpring = false
		-- 地主赢了
		if iTableNumExtra == self.iMainPlayer then

			local iTempCardNum = {0, 0}
			local iPlayer = 1

			for i = 1, 3 do 
				if i ~= iTableNumExtra then
					local player = self.room:getPlayerByPos(i)
					for j = 1, 20 do 
						if player.handle_cards[j] and player.handle_cards[j] ~= 0 then
							iTempCardNum[iPlayer] = iTempCardNum[iPlayer] + 1
						end
					end
					iPlayer = iPlayer + 1
				end
			end

			if 	iTempCardNum[1] == 17 and iTempCardNum[2] == 17 then
				self.iRoomTime = self.iRoomTime * 2;
				bIfSpring = true;
			end		

		else
			if self.iTurn == 1 then
				-- 炸弹和底分都已经在这里面有加倍， 那就看个人是否加倍吧
				self.iRoomTime = self.iRoomTime * 2;
				bIfSpring = true;
			end
		end

		print("bIfSpring", bIfSpring)
		-- 先算出来底分和叫分的基础番数， 最后再算出来每个玩家需要的番数
		-- 取得炸弹番数， 炸弹翻倍， 是指数
		-- local iBoomNum = self.iNowBoom >= self.iMaxBoom and self.iMaxBoom or self.iNowBoom
		-- local iBoutResult = iBoomNum + 1
		
		local iBoutResult = self.iRoomTime -- 乘以底分之后的
		for i = 1,  3 do 
			if i ~= iTableNumExtra then	
				local bTempTime = 1
				if self.bDoubleTime[i] == true then
					bTempTime = bTempTime * 2
				end 
				if self.bDoubleTime[iTableNumExtra] == true then
					bTempTime = bTempTime * 2				
				end
				-- 算分
				self.iAmountResult[i] = self.iAmountResult[i] + (-1)*self.iRoomTime*bTempTime
				self.iAmountResult[iTableNumExtra] = self.iAmountResult[iTableNumExtra] + self.iRoomTime*bTempTime
			end
		end

		-- 把分数加载到玩家的身上去
		for i = 1, 3 do 
			local player = self.room:getPlayerByPos(i)
			player.cur_score = self.iAmountResult[i]
			player.score = player.score + self.iAmountResult[i]
		end

		print("self.iAmountResult = ", cjson.encode(self.iAmountResult))

		-- 通知结算信息
		local resultMsg = {}
		-- iLastCard
		resultMsg.over_type = self.room.cur_round >= self.room.round
		-- resultMsg.players = self.room.player_list
		resultMsg.players = {}
		for i = 1, 3 do 
			local player = {}
			player.user_id = self.room.player_list[i].user_id
			player.user_pos = self.room.player_list[i].user_pos
			player.cur_score = self.room.player_list[i].cur_score
			player.score = self.room.player_list[i].score
			player.card_list = self.room.player_list[i].handle_cards
			resultMsg.players[i] = player
		end

		resultMsg.bIfSpring = bIfSpring
		resultMsg.iTime = self.iRoomTime
		resultMsg.iBoomNums = self.iNowBoom
		resultMsg.nowTableTime = self.iRoomTime

		print("resultMsg", cjson.encode(resultMsg))

		-- 通知玩家游戏结束了
		self.room:broadcastAllPlayers("NoticeDDZGameOver", resultMsg)
		-- 刷新玩家状态并且记录复盘文件
		self.room.over_round = self.room.over_round + 1
		self.room:roundOver()
		-- self.room.over_round = self.room
		if self.room.cur_round >= self.room.round then
			-- 给前段发送结算消息
			self.room:distroy(constant.DISTORY_TYPE.FINISH_GAME)
			return "success"
		end
		-- 刷新玩家信息
		self.room:refreshRoomInfo()
		return "success"
	else   -- 通知下个人出牌
		local iJudgeCard = iTableNumExtra + 1

		if iJudgeCard > 3 then
			iJudgeCard = 1
		end

		self.iCurPlayExtraNum = iJudgeCard
		self:serverPushPlayCard(self.iCurPlayExtraNum)
	end


	return "success"
end

--返回房间,推送当局的游戏信息
function game:back_room(user_id)
	local player = self.room:getPlayerByUserId(user_id)
	local refresh_room_info = self.room:getRoomInfo()
	local rsp_msg = {}
	rsp_msg.refresh_room_info = refresh_room_info
	rsp_msg.card_list = player.handle_cards
	-- 当前要操作的人
	rsp_msg.operator = self.iCurPlayExtraNum
	-- 最后一首出牌的人，如果中间有间隔人的话就是过
	rsp_msg.cur_play_pos = self.iTablePlayer
	rsp_msg.zpos = self.iMainPlayer


	print("refresh_room_info", cjson.encode(refresh_room_info))

	local cardNums = {0, 0, 0}
	for i, v in pairs(refresh_room_info.players) do
		for j = 1, 20 do 
			if v.handle_cards[j] and v.handle_cards[j] ~= 0 then
				cardNums[v.user_pos] = cardNums[v.user_pos] + 1
			end
		end
	end

	rsp_msg.cur_table_cards = self.cSendCards
	rsp_msg.cur_table_Demand = self.iDemandPoint
	rsp_msg.cur_table_bDouble = self.bDoubleTime
	rsp_msg.cur_table_time = self.iRoomTime
	rsp_msg.cur_last_CardNums = cardNums
	rsp_msg.cBaseCards = self.baseCard

	player:send({push_all_room_info = rsp_msg})

	return "success"
end

function game:game_cmd(data)
	local user_id = data.user_id
	local command = data.command

	log.infof("data[%s]", cjson.encode(data))

	local func = game[command]
	if not func then
		return "no_support_command"
	end

	local player = self.room:getPlayerByUserId(user_id)
	local result = func(game, player, data)
	return result
end



function game:distory( tObj )
	
end

return game
