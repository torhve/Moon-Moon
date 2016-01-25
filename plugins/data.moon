Logger = require 'logger'

serve_self ==> setmetatable(@, {__call: ()=>pairs(@)})

{
	hooks:
		['CONNECT']: =>
			-- Welcome
			@channels = serve_self {}
			@users    = serve_self {}
			@server   =            {
				caps: {},
				ircv3_caps: {}
			}
	handlers:
		['005']: (prefix, args)=>
			-- Capabilities
			caps = {select 2, unpack args}
			for _, cap in pairs caps
				if cap\find "="
					key, value = cap\match '^(.-)=(.+)'
					@server.caps[key] = value
				else
					@server.caps[cap] = true
		['JOIN']: (prefix, args, trail)=>
			-- user JOINs a channel
			local channel
			local account
			if @server.ircv3_caps['extended-join']
				account = args[2] if args[2] != '*'
				channel = args[1]
			else
				channel = args[1] or trail
			nick, username, host = prefix\match '^(.-)!(.-)@(.-)$'
			if prefix\match '^.-!.-@.-$'
				nick, username, host = prefix\match '^(.-)!(.-)@(.-)$'
				if not @users[nick] then
					@users[nick] = {
						account: account
						channels: {
							[channel]: {
								status: ""
							}
						},
						:username,
						:host
					}
				else
					if not @users[nick].channels
						@users[nick].channels = {
							[channel]: {
								status: ""
							}
						}
					else
						@users[nick].channels[channel] = status: ""
				@users[nick].account = account if account
			if not @channels[channel]
				@channels[channel] = {
					users: {
						[nick]: @users[nick]
					}
				}
		['NICK']: (prefix, args, trail)=>
			old = prefix\match('^(.-)!') or prefix
			new = args[1] or trail
			for channel_name in pairs @users[old].channels
				@channels[channel_name].users[new] = @channels[channel_name].users[old]
				@channels[channel_name].users[old] = nil
			@users[new] = @users[old]
			@users[old] = nil
		['MODE']: (prefix, args)=>
			-- User or bot called /mode
			if args[1]\sub(1,1) == "#"
				@send_raw ('NAMES %s')\format args[1]
		['353']: (prefix, args, trail)=>
			-- Result of NAMES
			channel = args[3]
			statuses = @server.caps.PREFIX and @server.caps.PREFIX\match '%(.-%)(.+)' or "+@"
			statuses = "^[" .. statuses\gsub("%[%]%(%)%.%+%-%*%?%^%$%%", "%%%1") .. "]"
			for text in trail\gmatch '%S+'
				local status, nick
				if text\match statuses
					status, nick = text\match '^(.)(.+)'
				else
					status, nick = '', text
				if not @users[nick]
					@users[nick] = {channels: {}}
				if @channels[channel].users[nick]
					if @users[nick].channels[channel]
						@users[nick].channels[channel].status = status
					else
						@users[nick].channels[channel] = :status
				else
					@channels[channel].users[nick] = @users[nick]
					@users[nick].channels[channel] = :status
		['KICK']: (prefix, args)=>
			channel = args[1]
			nick = args[2]
			@users[nick].channels[channel] = nil
			if #@users[nick].channels == 0
				@users[nick] = nil
		['PART']: (prefix, args)=>
			-- User or bot parted channel, clear from lists
			channel = args[1]
			nick = prefix\match '^(.-)!'
			@users[nick].channels[channel] = nil
			if #@users[nick].channels == 0
				@users[nick] = nil -- User left network, garbagecollect
		['QUIT']: (prefix, args)=>
			-- User or bot parted network, nuke from lists
			channel = args[1]
			nick = prefix\match '^(.-)!'
			for channel in pairs @users[nick].channels
				@channels[channel].users[nick] = nil
			@users[nick] = nil
		['CAP']: (prefix, args, trailing)=>
			if args[2] == 'LS'
				for item in trailing\gmatch '%S+'
					if item == 'extended-join'
						@send_raw 'CAP REQ ' .. item
						@fire_hook 'REG_CAP'
			elseif args[2] == 'ACK' or args[2] == 'NAK'
				local has_extjoin
				for item in trailing\gmatch '%S+'
					if item == 'extended-join'
						has_extjoin = true
				@server.ircv3_caps['extended-join'] = true if has_extjoin and args[2] == 'ACK'
				@fire_hook 'ACK_CAP' if has_extjoin
}
