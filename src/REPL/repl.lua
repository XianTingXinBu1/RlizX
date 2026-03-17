-- RlizX REPL module (pure Lua)
local M = {}

local function printf(fmt, ...)
  io.stdout:write(string.format(fmt, ...))
end

local function get_stty_state()
  local p = io.popen("stty -g 2>/dev/null")
  if not p then return nil end
  local state = p:read("*l")
  p:close()
  return state
end

local function set_raw_mode()
  -- raw + no-echo + immediate input
  os.execute("stty -echo -icanon min 1 time 0")
end

local function restore_mode(state)
  if state and state ~= "" then
    os.execute("stty " .. state)
  else
    os.execute("stty sane")
  end
end

local function read_key()
  local c = io.stdin:read(1)
  if not c then return nil end
  if c == "\27" then
    local c2 = io.stdin:read(1)
    if c2 == "[" then
      local c3 = io.stdin:read(1)
      return "ESC[" .. (c3 or "")
    end
    return "ESC"
  end

  local b = string.byte(c)
  if b and b >= 0x80 then
    local len
    if b >= 0xF0 then
      len = 4
    elseif b >= 0xE0 then
      len = 3
    elseif b >= 0xC0 then
      len = 2
    else
      len = 1
    end
    if len > 1 then
      local rest = io.stdin:read(len - 1) or ""
      return c .. rest
    end
  end

  return c
end

local function utf8_chars(s)
  local t = {}
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    t[#t + 1] = ch
  end
  return t
end

local function utf8_width(ch)
  local b = string.byte(ch)
  if not b or b < 0x80 then
    return 1
  end
  -- 近似宽度：把大多数多字节字符当作宽 2
  return 2
end

local function buf_width(buf, n)
  local w = 0
  for i = 1, n do
    w = w + utf8_width(buf[i])
  end
  return w
end

local function render_line(prompt, buf, cursor)
  io.stdout:write("\r")
  io.stdout:write(prompt)
  io.stdout:write(table.concat(buf))
  io.stdout:write("\27[0K")
  local target = #prompt + buf_width(buf, cursor)
  io.stdout:write("\r")
  if target > 0 then
    io.stdout:write(string.format("\27[%dC", target))
  end
end

local function read_line(prompt, history)
  local buf = {}
  local cursor = 0
  local hist_index = nil
  local saved_line = ""

  local function set_buffer(text)
    buf = utf8_chars(text)
    cursor = #buf
  end

  render_line(prompt, buf, cursor)

  while true do
    local k = read_key()
    if not k then return nil end

    if k == "\r" or k == "\n" then
      io.stdout:write("\n")
      return table.concat(buf)
    elseif k == "\127" or k == "\8" then
      if cursor > 0 then
        table.remove(buf, cursor)
        cursor = cursor - 1
      end
    elseif k == "\3" then
      -- Ctrl+C
      io.stdout:write("\n")
      return nil, "interrupt"
    elseif k == "ESC[A" then
      if #history > 0 then
        if not hist_index then
          hist_index = #history
          saved_line = table.concat(buf)
        elseif hist_index > 1 then
          hist_index = hist_index - 1
        end
        set_buffer(history[hist_index] or "")
      end
    elseif k == "ESC[B" then
      if hist_index then
        if hist_index < #history then
          hist_index = hist_index + 1
          set_buffer(history[hist_index] or "")
        else
          hist_index = nil
          set_buffer(saved_line)
        end
      end
    elseif k == "ESC[D" then
      if cursor > 0 then
        cursor = cursor - 1
      end
    elseif k == "ESC[C" then
      if cursor < #buf then
        cursor = cursor + 1
      end
    elseif k >= " " then
      table.insert(buf, cursor + 1, k)
      cursor = cursor + 1
    end

    render_line(prompt, buf, cursor)
  end
end

function M.start(opts)
  opts = opts or {}
  local version = opts.version or "0.1.0"
  local prompt = opts.prompt or "> "

  local function print_version()
    printf("RlizX v%s\n", version)
  end

  local function repl_help()
    io.stdout:write([[
REPL 指令:
  /help                     显示本帮助
  /version                  显示版本
  /clear                    清屏
  /exit                     退出 REPL
  /switch <名称>            切换当前 agent
  /agent list               列出所有 agent
  /agent add <名称>         新增 agent（创建目录与默认配置）
  /agent delete <名称>      删除 agent 目录

快捷键:
  ↑/↓                       历史命令（当前 agent）
  ←/→                       光标移动
  Backspace                 删除字符

说明:
  每个 agent 独立历史记录与配置。
]])
  end

  io.stdout:write("RlizX REPL\n")
  io.stdout:write("输入 '/help' 查看指令，'/exit' 退出。\n")

  local stty_state = get_stty_state()
  set_raw_mode()

  local function script_dir()
    local info = debug.getinfo(1, "S")
    local src = info and info.source or ""
    if src:sub(1, 1) == "@" then
      src = src:sub(2)
    end
    return src:match("^(.*)/") or "."
  end

  local function trim(s)
    return (s:match("^%s*(.-)%s*$") or "")
  end

  local function is_valid_agent_name(name)
    return name and name:match("^[%w%-%_]+$") ~= nil
  end

  local function ensure_dir(path)
    os.execute("mkdir -p " .. path)
  end

  local function remove_dir(path)
    os.execute("rm -rf " .. path)
  end

  local function path_exists(path)
    local ok = os.execute("test -e " .. path .. " >/dev/null 2>&1")
    return ok == true or ok == 0
  end

  local function dir_exists(path)
    local ok = os.execute("test -d " .. path .. " >/dev/null 2>&1")
    return ok == true or ok == 0
  end

  local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local c = f:read("*a")
    f:close()
    return c
  end

  local function write_file(path, content)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
  end

  local function list_dir(path)
    local p = io.popen("ls -1 " .. path .. " 2>/dev/null")
    if not p then return {} end
    local t = {}
    for line in p:lines() do
      if line ~= "." and line ~= ".." then
        t[#t + 1] = line
      end
    end
    p:close()
    table.sort(t)
    return t
  end

  local function read_default_agent_config(base)
    local path = base .. "/../../rlizx.config.json"
    local raw = read_file(path)
    if not raw then return nil end
    local openai = raw:match('"openai"%s*:%s*%{(.-)%}')
    if not openai then return nil end

    local function get(key)
      local pat = '"' .. key .. '"%s*:%s*"(.-)"'
      return openai:match(pat)
    end

    local model = get("model") or ""
    return string.format('{"model":"%s"}', model)
  end

  local function json_escape(s)
    return (tostring(s)
      :gsub("\\", "\\\\")
      :gsub("\"", "\\\"")
      :gsub("\n", "\\n")
      :gsub("\r", "\\r")
      :gsub("\t", "\\t"))
  end

  local function json_unescape(s)
    return (s:gsub("\\n", "\n")
             :gsub("\\r", "\r")
             :gsub("\\t", "\t")
             :gsub('\\"', '"')
             :gsub("\\\\", "\\"))
  end

  local function agent_memory_dir(root, name)
    return root .. "/" .. name .. "/.rlizx/memory"
  end

  local function agent_longterm_path(root, name)
    return agent_memory_dir(root, name) .. "/long-term.db"
  end

  local function ensure_longterm_file(root, name)
    local path = agent_longterm_path(root, name)
    if not path_exists(path) then
      write_file(path, "[]")
    end
  end

  local base = script_dir()
  local gateway = dofile(base .. "/../Gateway/gateway.lua")
  local agents_root = base .. "/../../agents"

  ensure_dir(agents_root)

  local current_agent = nil
  local histories = {}

  local function get_history(agent)
    if not histories[agent] then
      histories[agent] = {}
    end
    return histories[agent]
  end

  local function agent_config_path(name)
    return agents_root .. "/" .. name .. "/.rlizx/config.json"
  end

  local function init_agent(name)
    if not is_valid_agent_name(name) then
      return false, "非法名称，仅允许字母/数字/下划线/短横线"
    end

    local agent_dir = agents_root .. "/" .. name
    local cfg_dir = agent_dir .. "/.rlizx"
    local cfg_path = cfg_dir .. "/config.json"

    ensure_dir(cfg_dir)
    ensure_dir(cfg_dir .. "/memory")
    ensure_longterm_file(agents_root, name)

    if not path_exists(cfg_path) then
      local default_cfg = read_default_agent_config(base) or "{}"
      if not write_file(cfg_path, default_cfg) then
        return false, "写入配置失败: " .. cfg_path
      end
    end

    return true
  end

  local function delete_agent(name)
    if not is_valid_agent_name(name) then
      return false, "非法名称，仅允许字母/数字/下划线/短横线"
    end
    local agent_dir = agents_root .. "/" .. name
    if not dir_exists(agent_dir) then
      return false, "agent 不存在: " .. name
    end
    remove_dir(agent_dir)
    histories[name] = nil
    if current_agent == name then
      current_agent = nil
    end
    return true
  end

  local function list_agents()
    return list_dir(agents_root)
  end

  local function switch_agent(name)
    if not is_valid_agent_name(name) then
      return false, "非法名称，仅允许字母/数字/下划线/短横线"
    end
    local agent_dir = agents_root .. "/" .. name
    if not dir_exists(agent_dir) then
      local ok, err = init_agent(name)
      if not ok then return false, err end
    end
    current_agent = name
    return true
  end

  local function parse_command(line)
    if line:sub(1, 1) ~= "/" then
      return nil
    end
    local cmdline = trim(line:sub(2))
    if cmdline == "" then
      return { cmd = "" }
    end

    local parts = {}
    for w in cmdline:gmatch("%S+") do
      parts[#parts + 1] = w
    end

    local cmd = parts[1]
    table.remove(parts, 1)
    return { cmd = cmd, args = parts }
  end

  local function handle_command(cmd)
    if cmd.cmd == "help" then
      repl_help()
      return true
    elseif cmd.cmd == "version" then
      print_version()
      return true
    elseif cmd.cmd == "clear" then
      io.stdout:write("\27[2J\27[H")
      return true
    elseif cmd.cmd == "exit" then
      return false, "exit"
    elseif cmd.cmd == "switch" then
      local name = cmd.args[1]
      if not name then
        io.stdout:write("用法: /switch <名称>\n")
        return true
      end
      local ok, err = switch_agent(name)
      if not ok then
        io.stdout:write("[Agent Error] " .. tostring(err) .. "\n")
        return true
      end
      io.stdout:write("已切换到 agent: " .. name .. "\n")
      return true
    elseif cmd.cmd == "agent" then
      local sub = cmd.args[1]
      if sub == "list" then
        local list = list_agents()
        if #list == 0 then
          io.stdout:write("暂无 agent\n")
        else
          io.stdout:write("agents:\n")
          for _, n in ipairs(list) do
            if n == current_agent then
              io.stdout:write("  * " .. n .. "\n")
            else
              io.stdout:write("  - " .. n .. "\n")
            end
          end
        end
        return true
      elseif sub == "add" then
        local name = cmd.args[2]
        if not name then
          io.stdout:write("用法: /agent add <名称>\n")
          return true
        end
        local ok, err = init_agent(name)
        if not ok then
          io.stdout:write("[Agent Error] " .. tostring(err) .. "\n")
          return true
        end
        io.stdout:write("已创建 agent: " .. name .. "\n")
        return true
      elseif sub == "delete" then
        local name = cmd.args[2]
        if not name then
          io.stdout:write("用法: /agent delete <名称>\n")
          return true
        end
        local ok, err = delete_agent(name)
        if not ok then
          io.stdout:write("[Agent Error] " .. tostring(err) .. "\n")
          return true
        end
        io.stdout:write("已删除 agent: " .. name .. "\n")
        return true
      else
        io.stdout:write("用法: /agent list | /agent add <名称> | /agent delete <名称>\n")
        return true
      end
    else
      io.stdout:write("未知命令: /" .. cmd.cmd .. "\n")
      return true
    end
  end

  local ok, err = pcall(function()
    while true do
      local active_agent = current_agent or "default"
      local history = get_history(active_agent)
      local line, reason = read_line(prompt, history)
      if not line then
        if reason == "interrupt" then
          break
        end
        break
      end

      line = trim(line)
      if line ~= "" then
        history[#history + 1] = line
      end

      if line == "" then
        -- 空行忽略
      else
        local cmd = parse_command(line)
        if cmd then
          local okc, flag = handle_command(cmd)
          if okc == false and flag == "exit" then
            break
          end
        else
          if not current_agent then
            io.stdout:write("请先 /switch <名称> 选择 agent\n")
          else
            local okm1, errm1 = pcall(gateway.append_memory, current_agent, "user", line)
            if not okm1 and errm1 then
              io.stdout:write("[Gateway Memory Error] " .. tostring(errm1) .. "\n")
            end

            local ok2, resp = pcall(gateway.handle_input, line, current_agent)
            if ok2 then
              if resp ~= nil then
                io.stdout:write(tostring(resp) .. "\n")
                local okm2, errm2 = pcall(gateway.append_memory, current_agent, "assistant", tostring(resp))
                if not okm2 and errm2 then
                  io.stdout:write("[Gateway Memory Error] " .. tostring(errm2) .. "\n")
                end
              end
            else
              io.stdout:write("[Gateway Error] " .. tostring(resp) .. "\n")
            end
          end
        end
      end
    end
  end)

  restore_mode(stty_state)
  if not ok then
    error(err)
  end
end

return M
