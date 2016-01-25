local Logger = require('logger')
local patterns = {
  JOIN = "\00308[\003%s\00308]\003 \00309>\003 %s",
  MODE = "\00308[\003%s\00308]\003 Mode %s by %s",
  KICK = "\00308[\003%s\00308]\003 %s kicked %s",
  KICK_2 = "\00308[\003%s\00308]\003 %s kicked %s \00315(%s)",
  PART = "\00308[\003%s\00308]\003 \00304<\003 %s",
  PART_2 = "\00308[\003%s\00308]\003 \00304<\003 %s \00315(%s)",
  QUIT = "\00311<\003%s\00311>\003 \00304<\003",
  QUIT_2 = "\00311<\003%s\00311>\003 \00304<\003 \00315(%s)",
  ACTION = "\00308[\003%s\00308]\003 * %s %s",
  ACTION_2 = "* %s %s",
  PRIVMSG = "\00311<\00308[\003%s\00308]\003%s\00311>\003 %s",
  PRIVMSG_2 = "\00311<\003%s\00311>\003 %s",
  NOTICE = "\00311-\00308[\003%s\00308]\003%s\00311-\003 %s",
  NOTICE_2 = "\00311-\003%s\00311-\003 %s"
}
local serve_self
serve_self = function(self)
  return setmetatable(self, {
    __call = function(self)
      return pairs(self)
    end
  })
end
return {
  handlers = {
    ['JOIN'] = function(self, prefix, args, trail)
      return Logger.print(patterns.JOIN:format(args[1], prefix:match('^(.-)!') or prefix))
    end,
    ['NICK'] = function(self, prefix, args, trail)
      local old = prefix:match('^(.-)!') or prefix
      local new = args[1] or trail
      return Logger.print(('%s \00309>>\003 %s'):format(old, new))
    end,
    ['MODE'] = function(self, prefix, args, trailing)
      local channel = args[1]
      table.remove(args, 1)
      if channel:sub(1, 1) == "#" then
        return Logger.print(patterns.MODE:format(channel, table.concat(args, " "), prefix:match('^(.-)!') or prefix))
      end
    end,
    ['KICK'] = function(self, prefix, args, trailing)
      local channel = args[1]
      local nick = args[2]
      local kicker = prefix:match('^(.-)!') or prefix
      if trailing then
        return Logger.print(patterns.KICK_2:format(channel, kicker, nick, trailing))
      else
        return Logger.print(patterns.KICK:format(channel, kicker, nick))
      end
    end,
    ['PART'] = function(self, prefix, args, trailing)
      local channel = args[1]
      local nick = prefix:match('^(.-)!') or prefix
      if trailing then
        return Logger.print(patterns.PART_2:format(channel, nick, trailing))
      else
        return Logger.print(patterns.PART:format(channel, nick))
      end
    end,
    ['QUIT'] = function(self, prefix, args, trailing)
      local nick = prefix:match('^(.-)!') or prefix
      if trailing then
        return Logger.print(patterns.QUIT_2:format(nick, trailing))
      else
        return Logger.print(patterns.QUIT:format(nick))
      end
    end,
    ['PRIVMSG'] = function(self, prefix, args, trailing)
      local nick = prefix:match('^(.-)!') or prefix
      if not args[1]:sub(1, 1) == '#' then
        if trailing:match("^\001ACTION .-\001$") then
          return Logger.print(patterns.ACTION_2:format(nick, trailing:match('^%S+%s+(.+)')))
        elseif not trailing:match('^\001') then
          return Logger.print(patterns.PRIVMSG_2:format(nick, trailing))
        end
      else
        local ch = args[1]
        if trailing:match("^\001ACTION .-\001$") then
          return Logger.print(patterns.ACTION:format(ch, nick, trailing:match('^%S+%s+(.+)')))
        elseif not trailing:match('^\001') then
          return Logger.print(patterns.PRIVMSG:format(ch, nick, trailing))
        end
      end
    end,
    ['NOTICE'] = function(self, prefix, args, trailing)
      if trailing:sub(1, 1) == '\001' then
        return 
      end
      local nick = prefix:match('^(.-)!') or prefix
      if args[1]:sub(1, 1) == '#' then
        return Logger.print(patterns.NOTICE:format(args[1], nick, trailing))
      else
        return Logger.print(patterns.NOTICE_2:format(nick, trailing))
      end
    end,
    ['CAP'] = function(self, prefix, args, trailing)
      if args[2] == 'LS' then
        local has_echo
        for item in trailing:gmatch('%S+') do
          if item == 'echo-message' then
            has_echo = true
            self:send_raw('CAP REQ ' .. item)
          end
        end
        if not has_echo then
          return self:fire_hook('ACK_CAP')
        end
      elseif args[2] == 'ACK' or args[2] == 'NAK' then
        local has_echo
        for item in trailing:gmatch('%S+') do
          if item == 'echo-message' then
            has_echo = true
          end
        end
        if has_echo and args[2] == 'ACK' then
          self.server.ircv3_caps['echo-message'] = true
        end
        if has_echo then
          return self:fire_hook('ACK_CAP')
        end
      end
    end
  },
  hooks = {
    ['CAP_LS'] = function(self)
      return self:fire_hook('REG_CAP')
    end
  }
}
