local cjson = require "cjson"
local skynet = require "skynet"
local log = require "skynet.log"
local constant = require "constant"
local ROOM_STATE = constant.ROOM_STATE
local Player = require "Player"
local PAY_TYPE = constant.PAY_TYPE
local ROUND_COST = constant.ROUND_COST
local GAME_OVER_TYPE = {
	NORMAL = 1, --正常胡牌
	FLOW = 2,	--流局
	DISTROY_ROOM = 3,   --房间解散推送结算积分
}
local room = {}
function room:init(data)
	self.room_id = data.room_id
	self.game_type = data.game_type
	self.round = data.round
	self.pay_type = data.pay_type
	self.seat_num = data.seat_num
	self.over_round = data.over_round
	self.other_setting = cjson.decode(data.other_setting)
    self.is_friend_room = data.is_friend_room
    self.is_open_voice = data.is_open_voice
    self.is_open_gps = data.is_open_gps
	self.owner_id = data.owner_id
	self.state = data.state
	self.expire_time = data.expire_time
	self.cur_round = data.cur_round

	self.player_list = {}
end

function room:recover(data)
	print("FYD====恢复房间 id = ",data.room_id)
	self.recover_state = true
	self.room_id = data.room_id
	self.game_type = data.game_type
	self.round = data.round
	self.pay_type = data.pay_type
	self.seat_num = data.seat_num
	self.over_round = data.over_round
	self.other_setting = cjson.decode(data.other_setting)
    self.is_friend_room = data.is_friend_room
    self.is_open_voice = data.is_open_voice
    self.is_open_gps = data.is_open_gps
	self.owner_id = data.owner_id
	self.state = data.state
	self.expire_time = data.expire_time
	self.cur_round = data.cur_round

	self.player_list = {}
	if data.player_list then
		local player_list = cjson.decode(data.player_list)
		for i,pinfo in ipairs(player_list) do
			local player = Player.new(pinfo)
			player.disconnect = true
			table.insert(self.player_list,player)
		end
	end
end


function room:addPlayer(info)
	local already_pos = {}
	for _,player in ipairs(self.player_list) do
		if player.user_pos then
			already_pos[player.user_pos] = true
		end
	end
	local unused_pos = nil
	for pos=1,self.seat_num do
		if not already_pos[pos] then
			unused_pos = pos
			break
		end
	end

	info.user_pos = unused_pos
	info.is_sit = false

	local player = Player.new(info)
	table.insert(self.player_list,player)
end


--删除玩家
function room:removePlayer(user_id)
	for index,player in ipairs(self.player_list) do
		if player.user_id == user_id then
			table.remove(self.player_list,index)
			break
		end
	end
end

function room:getPlayerInfo(...)
	local filters = {...}
	local info = {}
	for _,player in ipairs(self.player_list) do
		local temp = {}
		for _,key in ipairs(filters) do
			temp[key] = player[key]
		end
		table.insert(info,temp)
	end
	return info
end

function room:getPropertys(...)
	local args = {...}
	local info = {}
	for i,v in ipairs(args) do
		info[v] = self[v]
	end
	return info
end

function room:getPlayerByPos(pos)
	for _,player in ipairs(self.player_list) do
		if pos == player.user_pos then
			return player
		end
	end
end

function room:getPlayerByUserId(user_id)
	for _,player in ipairs(self.player_list) do
		if user_id == player.user_id then
			return player
		end
	end
end

--更新玩家的属性
function room:updatePlayerProperty(user_id,name,value)
	for index,player in ipairs(self.player_list) do
		if player.user_id == user_id then
			player[name] = value
			return true
		end
	end
	return false
end

function room:getRoomInfo()
	local rsp_msg = {}
	local players = self:getPlayerInfo("user_id","user_name","user_pic","user_ip","user_pos","is_sit","gold_num","score","cur_score","disconnect","sex","latitude","lontitude")
	local room_setting = self:getPropertys("game_type","round","pay_type","seat_num","is_friend_room","is_open_voice","is_open_gps","other_setting", "owner_id")
	rsp_msg.room_setting = room_setting
	rsp_msg.room_id = self.room_id
	rsp_msg.state = self.state
	rsp_msg.players = players
	rsp_msg.cur_round = self.cur_round
	return rsp_msg
end

function room:refreshRoomInfo()
	local rsp_msg = self:getRoomInfo()
	self:broadcastAllPlayers("refresh_room_info",rsp_msg)
end

function room:pushAllRoomInfo()
	local rsp_msg = self:getRoomInfo()
	self:broadcastAllPlayers("push_all_room_info",{refresh_room_info = rsp_msg})
end

function room:broadcastAllPlayers(proto_name,proto_data)
	for _,player in ipairs(self.player_list) do
		player:send({[proto_name]=proto_data})
	end
end

function room:userDisconnect(player)
	player.disconnect = true
	self:broadcastAllPlayers("notice_player_connect_state",{user_id=player.user_id,user_pos=player.user_pos,is_connect=false})
end

function room:userReconnect(player)
	player.disconnect = false
	self:broadcastAllPlayers("notice_player_connect_state",{user_id=player.user_id,user_pos=player.user_pos,is_connect=true})
end

function room:updatePlayersToDb()
    local data = {}
    local player_list = {}
    for _,player in ipairs(self.player_list) do
        local obj = {}
        obj.user_id = player.user_id
        obj.score = player.score
        obj.user_name = player.user_name
        obj.user_pic = player.user_pic
        obj.gold_num = player.gold_num
        obj.user_pos = player.user_pos
        obj.is_sit = player.is_sit
		obj.an_gang_num = player.an_gang_num
		obj.ming_gang_num = player.ming_gang_num
		obj.reward_num = player.reward_num
		obj.hu_num = player.hu_num
        table.insert(player_list,obj)
    end
    data.room_id = self.room_id
    data.player_list = cjson.encode(player_list)
    skynet.send(".mysql_pool","lua","insertTable","room_list",data)
end

function room:roundOver(msg,over_type)
	for i,player in ipairs(self.player_list) do
		player.is_sit = false
	end
	self.over_round = self.over_round + 1
    local data = {}
    data.room_id = self.room_id
    data.over_round = self.over_round
	data.cur_round = self.cur_round
    skynet.send(".mysql_pool","lua","insertTable","room_list",data)

    if msg then
    	msg.last_round = self.over_round >= self.round
		self:broadcastAllPlayers("notice_game_over",msg)
    end



    
	--计算金币并通知玩家更新
	self:updatePlayerGold(over_type)

    -- 同步玩家的个人数据到数据库
    self:updatePlayersToDb()
	skynet.send(".replay_cord","lua","saveRecord",self.game_type,self.replay_id)
	
	if self.over_round >= self.round then
		self:distroy(constant.DISTORY_TYPE.FINISH_GAME)
	end


	local temp = self:getPlayerInfo("user_id","user_name","score")
	local data = {players=cjson.encode(temp),replay_id=self.replay_id}
	skynet.call(".mysql_pool","lua","insertTable","replay_ids",data)
end

--更新玩家的金币
function room:updatePlayerGold(over_type)
	if over_type == GAME_OVER_TYPE.DISTROY_ROOM then
		return 
	end
 
	local players = self.player_list
	local cur_round = self.cur_round
	local round = self.round
	local seat_num = self.seat_num

	--花费
	local cost = round * ROUND_COST
	--出资类型
	local pay_type = self.pay_type
	--第一局结束 结算(房主出资/平摊出资)的金币
	if cur_round == 1 then
		--房主出资
		if pay_type == PAY_TYPE.ROOM_OWNER_COST then
			local owner_id = self.owner_id
			local owner = self:getPlayerByUserId(owner_id)
			--更新玩家的金币数量
			skynet.send(".mysql_pool","lua","updateGoldNum",-1*cost,owner_id)
			--如果owner不存在 有可能不在游戏中(比如:有人开房给别人玩,自己不玩)
			if owner then
				owner.gold_num = owner.gold_num -1*cost
				local gold_list = {{user_id = owner_id,user_pos = owner.user_pos,gold_num=owner.gold_num}}
				--通知房间中的所有人,有人的金币发生了变化
				self:broadcastAllPlayers("update_cost_gold",{gold_list=gold_list})
			end
		--平摊
		elseif pay_type == PAY_TYPE.AMORTIZED_COST then
			--每个人的花费
			local per_cost = math.floor(cost / seat_num)
			local gold_list = {}
			for i,obj in ipairs(players) do
				skynet.send(".mysql_pool","lua","updateGoldNum",-1*per_cost,obj.user_id)
				obj.gold_num = obj.gold_num -1*per_cost
				local info = {user_id = obj.user_id,user_pos = obj.user_pos,gold_num = obj.gold_num}
				table.insert(gold_list,info)
			end
			self:broadcastAllPlayers("update_cost_gold",{gold_list=gold_list})
		end   
	end
end

function room:startGame(recover)
	--current round + 1 after game begin
    self.cur_round = self.cur_round + 1
    --update room state after game begin
    self.state = ROOM_STATE.GAME_PLAYING
    --if first start game, need to update room expire time
    if self.cur_round == 1 then
        local now = skynet.time()
        self.expire_time = now + 12*60*60
        --更新销毁时间
        local data = {}
        data.room_id = self.room_id
	    data.expire_time = self.expire_time
	    data.state = self.state
	    data.over_round = self.over_round
		data.cur_round = self.cur_round
	    data.begin_time = 'NOW()'
	    skynet.send(".mysql_pool","lua","insertTable","room_list",data)
	end
	local data = {room_id = self.room_id,game_type=self.game_type,time="NOW()"}
	local info = skynet.call(".mysql_pool","lua","insertTable","replay_ids",data)
	if not info or not info.insert_id then
		log.error("not replay_id")
	end
	self.replay_id = info.insert_id
	if self.replay_id then
		local record_msg = self:getRoomInfo()
		skynet.send(".replay_cord","lua","insertRecord",self.replay_id,record_msg)
	else
		print("ERROR: 无法获取到replay_id")
	end
    local game_type = self.game_type

    print(string.format("game_type == %d", game_type))

    local path = string.format("%d.game",game_type)
    self.game = require(path)
    self.game:start(self,recover)
    self.recover_state = nil
end

function room:distroy(type)
	self.state = ROOM_STATE.ROOM_DISTROY
	-- 解散房间的时候更新状态,web端需要从数据库获取
	local data = {}
    data.room_id = self.room_id
    data.state = self.state
    skynet.send(".mysql_pool","lua","insertTable","room_list",data)

    print("room.over_round", room.over_round)

    if room.over_round >= 1 then
    	if room.game then
    		-- room.game:distroy()
    		room.game = nil
    	end
    	-- 扣费
    	self:settleAccounts()
    	--通知总结算
    	local rsp_msg = {}
    	rsp_msg.room_id = self.room_id
    	rsp_msg.sattle_list = self:getPlayerInfo("user_id","user_pos","hu_num","ming_gang_num","an_gang_num","reward_num","score")
    	
	    local ret = skynet.call(".mysql_pool","lua","selectTableAll","room_list","room_id="..self.room_id)
	    local info = ret[1]
	    if not info then
	        log.error("can't get room_list " .. self.room_id)
	        return "server_error"
	    end
	    rsp_msg.begin_time = info.begin_time

    	self:broadcastAllPlayers("notice_total_sattle",rsp_msg)
    end

    self:broadcastAllPlayers("notice_player_distroy_room",{room_id=self.room_id,type=type})
    room.player_list = {}

    --通知房间被销毁
    skynet.send(".agent_manager","lua","distroyRoom")
end

function room:getSitNums()
	local num = 0
	for i,player in ipairs(self.player_list) do
		if player.is_sit then
			num = num + 1
		end
	end
	return num
end

-- 扣房间费
function room:settleAccounts()
	local players = self.player_list
	local over_round = self.over_round
	local round = self.round
	-- 大赢家金币结算
	if over_round >= 1 then
		local pay_type = self.pay_type
		--赢家出资 积分高的掏钱
		if pay_type == PAY_TYPE.WINNER_COST then
			-- 积分从高到低排序
			table.sort(players,function(a,b) 
				return a.score > b.score
			end)

			local max_score = players[1].score
			--大赢家列表
			local winners = {}
			for i,obj in ipairs(players) do
				if obj.score >= max_score then
					table.insert(winners,obj)
				end
			end
			local gold_list = { }
			local per_cost = math.floor(cost/#winners)
			for _,obj in ipairs(winners) do

			    skynet.send(".mysql_pool","lua","updateGoldNum",-1*per_cost,obj.user_id)
				obj.gold_num = obj.gold_num -1*per_cost
				local info = {user_id=obj.user_id,user_pos=obj.user_pos,gold_num=obj.gold_num}
				table.insert(gold_list,info)
			end
			self:broadcastAllPlayers("update_cost_gold",{gold_list=gold_list})
		end
	end
end



return room