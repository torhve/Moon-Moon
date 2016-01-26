local Logger = require('logger')
local serve_self
serve_self = function(self)
  return setmetatable(self, {
    __call = function(self)
      return pairs(self)
    end
  })
end
return {
  hooks = {
    ['CONNECT'] = function(self)
      self.channels = serve_self({ })
      self.users = serve_self({ })
      self.server = {
        caps = { },
        ircv3_caps = { }
      }
    end
  },
  handlers = {
    ['005'] = function(self, prefix, args)
      local caps = {
        select(2, unpack(args))
      }
      for _, cap in pairs(caps) do
        if cap:find("=") then
          local key, value = cap:match('^(.-)=(.+)')
          self.server.caps[key] = value
        else
          self.server.caps[cap] = true
        end
      end
    end,
    ['AWAY'] = function(self, prefix, args, trail)
      local nick = prefix:match('^(.-)!')
      self.users[nick].away = trail
    end,
    ['ACCOUNT'] = function(self, prefix, args, trail)
      local nick = prefix:match('^(.-)!')
      self.users[nick].account = args[1] ~= "*" and args[1] or nil
    end,
    ['JOIN'] = function(self, prefix, args, trail, tags)
      local channel
      local account
      if self.server.ircv3_caps['extended-join'] then
        if args[2] ~= '*' then
          account = args[2]
        end
        channel = args[1]
      elseif self.server.ircv3_caps['account-tag'] and tags and tags.account then
        account = tags.account
        channel = args[1]
      else
        channel = args[1] or trail
      end
      local nick, username, host = prefix:match('^(.-)!(.-)@(.-)$')
      if prefix:match('^.-!.-@.-$') then
        if not self.users[nick] then
          self.users[nick] = {
            account = account,
            channels = {
              [channel] = {
                status = ""
              }
            },
            username = username,
            host = host
          }
        else
          if not self.users[nick].channels then
            self.users[nick].channels = {
              [channel] = {
                status = ""
              }
            }
          else
            self.users[nick].channels[channel] = {
              status = ""
            }
          end
        end
        if account then
          self.users[nick].account = account
        end
      end
      if not self.channels[channel] then
        if self.server.ircv3_caps['userhost-in-names'] then
          self:send_raw(('NAMES %s'):format(channel))
        else
          self:send_raw(('WHO %s'):format(channel))
        end
        self.channels[channel] = {
          users = {
            [nick] = self.users[nick]
          }
        }
      else
        self.channels[channel].users[nick] = self.users[nick]
      end
    end,
    ['NICK'] = function(self, prefix, args, trail)
      local old = prefix:match('^(.-)!') or prefix
      local new = args[1] or trail
      for channel_name in pairs(self.users[old].channels) do
        self.channels[channel_name].users[new] = self.channels[channel_name].users[old]
        self.channels[channel_name].users[old] = nil
      end
      self.users[new] = self.users[old]
      self.users[old] = nil
    end,
    ['MODE'] = function(self, prefix, args)
      if args[1]:sub(1, 1) == "#" then
        return self:send_raw(('NAMES %s'):format(args[1]))
      end
    end,
    ['353'] = function(self, prefix, args, trail)
      local channel = args[3]
      local statuses = self.server.caps.PREFIX and self.server.caps.PREFIX:match('%(.-%)(.+)' or "+@")
      statuses = "[" .. statuses:gsub("%p", "%%%1") .. "]"
      for text in trail:gmatch('%S+') do
        local status, pre, nick, user, host
        if text:match(statuses) then
          status, pre = text:match(('^(%s+)(.+)'):format(statuses))
        else
          status, pre = '', text
        end
        if self.server.ircv3_caps['userhost-in-names'] then
          nick, user, host = pre:match('^(.-)!(.-)@(.-)$')
        else
          nick = pre
        end
        if not self.users[nick] then
          self.users[nick] = {
            channels = { }
          }
        end
        if user then
          self.users[nick].user = user
        end
        if host then
          self.users[nick].host = host
        end
        if self.channels[channel].users[nick] then
          if self.users[nick].channels[channel] then
            self.users[nick].channels[channel].status = status
          else
            self.users[nick].channels[channel] = {
              status = status
            }
          end
        else
          self.channels[channel].users[nick] = self.users[nick]
          self.users[nick].channels[channel] = {
            status = status
          }
        end
      end
    end,
    ['352'] = function(self, prefix, args)
      local _, user, host, nick, away
      _, user, host, _, nick, away = unpack(args)
      if not self.users[nick] then
        self.users[nick] = {
          channels = { }
        }
      end
      self.users[nick].user = user
      self.users[nick].host = host
      self.users[nick].away = away:sub(1, 1) == "G"
    end,
    ['CHGHOST'] = function(self, prefix, args)
      local nick = prefix:match('^(.-)!')
      self.users[nick].user = args[1]
      self.users[nick].host = args[2]
    end,
    ['KICK'] = function(self, prefix, args)
      local channel = args[1]
      local nick = args[2]
      self.users[nick].channels[channel] = nil
      if #self.users[nick].channels == 0 then
        self.users[nick] = nil
      end
    end,
    ['PART'] = function(self, prefix, args)
      local channel = args[1]
      local nick = prefix:match('^(.-)!')
      self.users[nick].channels[channel] = nil
      if #self.users[nick].channels == 0 then
        self.users[nick] = nil
      end
    end,
    ['QUIT'] = function(self, prefix, args)
      local channel = args[1]
      local nick = prefix:match('^(.-)!')
      for channel in pairs(self.users[nick].channels) do
        self.channels[channel].users[nick] = nil
      end
      self.users[nick] = nil
    end,
    ['CAP'] = function(self, prefix, args, trailing)
      local caps = {
        'extended-join',
        'multi-prefix',
        'away-notify',
        'account-notify',
        'chghost',
        'server-time'
      }
      local to_send
      if args[2] == 'LS' then
        to_send = { }
      end
      for _index_0 = 1, #caps do
        local cap = caps[_index_0]
        if args[2] == 'LS' then
          for item in trailing:gmatch('%S+') do
            if item == cap then
              to_send[#to_send + 1] = cap
              self:fire_hook('REQ_CAP')
            end
          end
        elseif args[2] == 'ACK' or args[2] == 'NAK' then
          local has_cap
          for item in trailing:gmatch('%S+') do
            if item == cap then
              has_cap = true
            end
          end
          if has_cap and args[2] == 'ACK' then
            self.server.ircv3_caps[cap] = true
          end
          if has_cap then
            self:fire_hook('ACK_CAP')
          end
        end
      end
      if args[2] == 'LS' then
        return self:send_raw(('CAP REQ :%s'):format(table.concat(to_send, ' ')))
      end
    end
  }
}
