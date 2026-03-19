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

local function text_width(s)
  return buf_width(utf8_chars(s or ""), #(utf8_chars(s or "")))
end

local function render_line(prompt, buf, cursor, menu, selected_index, last_menu_lines)
  io.stdout:write("\r")
  io.stdout:write(prompt)
  io.stdout:write(table.concat(buf))
  io.stdout:write("\27[0K")

  for _ = 1, (last_menu_lines or 0) do
    io.stdout:write("\n\27[0K")
  end
  for _ = 1, (last_menu_lines or 0) do
    io.stdout:write("\27[1A")
  end

  local menu_lines = 0
  if menu and #menu > 0 then
    menu_lines = #menu
    for i, item in ipairs(menu) do
      local prefix = (i == selected_index) and "  > " or "    "
      io.stdout:write("\n\27[0K" .. prefix .. item.label)
    end
    for _ = 1, menu_lines do
      io.stdout:write("\27[1A")
    end
  end

  local target = text_width(prompt) + buf_width(buf, cursor)
  io.stdout:write("\r")
  if target > 0 then
    io.stdout:write(string.format("\27[%dC", target))
  end
  io.stdout:flush()
  return menu_lines
end

local function read_line(prompt, history, complete_fn)
  local buf = {}
  local cursor = 0
  local hist_index = nil
  local saved_line = ""
  local menu = {}
  local selected_index = 1
  local last_menu_lines = 0
  local suppress_menu_once = false

  local function current_text()
    return table.concat(buf)
  end

  local function set_buffer(text)
    buf = utf8_chars(text)
    cursor = #buf
  end

  local function refresh_menu()
    if suppress_menu_once then
      menu = {}
      selected_index = 1
      suppress_menu_once = false
      return
    end

    if not complete_fn then
      menu = {}
      selected_index = 1
      return
    end

    local items = complete_fn(current_text()) or {}
    menu = items
    if #menu == 0 then
      selected_index = 1
    elseif selected_index < 1 then
      selected_index = 1
    elseif selected_index > #menu then
      selected_index = #menu
    end
  end

  local function redraw()
    last_menu_lines = render_line(prompt, buf, cursor, menu, selected_index, last_menu_lines)
  end

  local function accept_completion()
    local item = menu[selected_index]
    if not item then
      return false
    end
    set_buffer(item.value)
    hist_index = nil
    suppress_menu_once = not item.keep_menu_open
    refresh_menu()
    redraw()
    return true
  end

  refresh_menu()
  redraw()

  while true do
    local k = read_key()
    if not k then return nil end

    if k == "\r" or k == "\n" then
      if #menu > 0 then
        accept_completion()
      else
        io.stdout:write("\n")
        return current_text()
      end
    elseif k == "\127" or k == "\8" then
      if cursor > 0 then
        table.remove(buf, cursor)
        cursor = cursor - 1
        hist_index = nil
      end
      refresh_menu()
    elseif k == "\3" then
      io.stdout:write("\n")
      return nil, "interrupt"
    elseif k == "ESC[A" then
      if #menu > 0 then
        if selected_index > 1 then
          selected_index = selected_index - 1
        end
      elseif #history > 0 then
        if not hist_index then
          hist_index = #history
          saved_line = current_text()
        elseif hist_index > 1 then
          hist_index = hist_index - 1
        end
        set_buffer(history[hist_index] or "")
        refresh_menu()
      end
    elseif k == "ESC[B" then
      if #menu > 0 then
        if selected_index < #menu then
          selected_index = selected_index + 1
        end
      elseif hist_index then
        if hist_index < #history then
          hist_index = hist_index + 1
          set_buffer(history[hist_index] or "")
        else
          hist_index = nil
          set_buffer(saved_line)
        end
        refresh_menu()
      end
    elseif k == "ESC[D" then
      if cursor > 0 then
        cursor = cursor - 1
      end
      refresh_menu()
    elseif k == "ESC[C" then
      if cursor < #buf then
        cursor = cursor + 1
      end
      refresh_menu()
    elseif k >= " " then
      table.insert(buf, cursor + 1, k)
      cursor = cursor + 1
      hist_index = nil
      refresh_menu()
    end

    redraw()
  end
end

function M.start(opts)
  opts = opts or {}
  local version = opts.version or "0.1.0"
  local default_prompt = opts.prompt or "> "

  local function print_version()
    printf("RlizX v%s\n", version)
  end

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

  local base = script_dir()
  local gateway = dofile(base .. "/../Gateway/gateway.lua")
  local agent_mod = dofile(base .. "/../Hub/agent.lua")
  local agent_manager = agent_mod.create_manager(base)

  local histories = {}

  local function current_agent_label()
    return agent_manager.current_agent or "未选择"
  end

  local function build_prompt()
    if agent_manager.current_agent then
      return string.format("[%s] > ", agent_manager.current_agent)
    end
    return string.format("[%s] %s", current_agent_label(), default_prompt)
  end

  local function print_status()
    local count = #agent_manager.list_agents()
    io.stdout:write(string.format("状态: agent=%s | agents=%d\n", current_agent_label(), count))
    if not agent_manager.current_agent then
      io.stdout:write("提示: 先使用 /switch <名称> 选择或创建 agent。\n")
    end
  end

  local command_specs = {
    { label = "/help", value = "/help", desc = "显示本帮助" },
    { label = "/status", value = "/status", desc = "显示当前状态" },
    { label = "/version", value = "/version", desc = "显示版本" },
    { label = "/clear", value = "/clear", desc = "清屏" },
    { label = "/exit", value = "/exit", desc = "退出 REPL" },
    { label = "/switch ", value = "/switch ", desc = "切换当前 agent", keep_menu_open = true },
    { label = "/agent list", value = "/agent list", desc = "列出所有 agent" },
    { label = "/agent add ", value = "/agent add ", desc = "新增 agent" },
    { label = "/agent delete ", value = "/agent delete ", desc = "删除 agent", keep_menu_open = true },
  }

  local function complete_command(text)
    if text:sub(1, 1) ~= "/" then
      return {}
    end

    local function complete_agent_names(prefix, base_cmd)
      local partial = text:sub(#prefix + 1)
      local matches = {}
      for _, name in ipairs(agent_manager.list_agents()) do
        if name:sub(1, #partial) == partial then
          matches[#matches + 1] = {
            label = string.format("%-16s %s", base_cmd .. name, "agent"),
            value = prefix .. name,
            keep_menu_open = false,
          }
        end
      end
      return matches
    end

    if text:sub(1, 8) == "/switch " then
      return complete_agent_names("/switch ", "/switch ")
    end

    if text:sub(1, 14) == "/agent delete " then
      return complete_agent_names("/agent delete ", "/agent delete ")
    end

    local matches = {}
    for _, spec in ipairs(command_specs) do
      if spec.value:sub(1, #text) == text then
        matches[#matches + 1] = {
          label = string.format("%-16s %s", spec.label, spec.desc),
          value = spec.value,
          keep_menu_open = spec.keep_menu_open,
        }
      end
    end
    return matches
  end

  local function repl_help()
    io.stdout:write([[
REPL 指令:
  /help                     显示本帮助
  /status                   显示当前状态
  /version                  显示版本
  /clear                    清屏
  /exit                     退出 REPL
  /switch <名称>            切换当前 agent
  /agent list               列出所有 agent
  /agent add <名称>         新增 agent（创建目录与默认配置）
  /agent delete <名称>      删除 agent 目录

快捷键:
  ↑/↓                       历史命令（当前 agent）/补全项选择
  ←/→                       光标移动
  Backspace                 删除字符
  Ctrl+C                    退出 REPL
  / 后继续输入              弹出命令补全
  Enter                     确认补全或提交输入

说明:
  每个 agent 独立历史记录与配置。
  当前提示符会显示已选中的 agent。
]])
  end

  io.stdout:write(string.format("RlizX REPL v%s\n", version))
  io.stdout:write("输入 '/help' 查看指令，'/exit' 退出。\n")
  print_status()

  local stty_state = get_stty_state()
  set_raw_mode()

  local function get_history(agent)
    if not histories[agent] then
      histories[agent] = {}
    end
    return histories[agent]
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
    elseif cmd.cmd == "status" then
      print_status()
      return true
    elseif cmd.cmd == "version" then
      print_version()
      return true
    elseif cmd.cmd == "clear" then
      io.stdout:write("\27[2J\27[H")
      print_status()
      return true
    elseif cmd.cmd == "exit" then
      return false, "exit"
    elseif cmd.cmd == "switch" then
      local name = cmd.args[1]
      if not name then
        io.stdout:write("用法: /switch <名称>\n")
        return true
      end
      local ok, err = agent_manager.switch_agent(name)
      if not ok then
        io.stdout:write("[Agent Error] " .. tostring(err) .. "\n")
        return true
      end
      io.stdout:write("已切换到 agent: " .. name .. "\n")
      return true
    elseif cmd.cmd == "agent" then
      local sub = cmd.args[1]
      if sub == "list" then
        local list = agent_manager.list_agents()
        if #list == 0 then
          io.stdout:write("暂无 agent，可使用 /switch <名称> 直接创建。\n")
        else
          io.stdout:write(string.format("agents (%d):\n", #list))
          for _, n in ipairs(list) do
            if n == agent_manager.current_agent then
              io.stdout:write("  * " .. n .. " (current)\n")
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
        local ok, err = agent_manager.init_agent(name)
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
        local ok, err = agent_manager.delete_agent(name)
        if ok then
          histories[name] = nil
        end
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
      io.stdout:write("未知命令: /" .. cmd.cmd .. "，输入 /help 查看可用指令。\n")
      return true
    end
  end

  local ok, err = pcall(function()
    while true do
      local active_agent = agent_manager.current_agent or "default"
      local history = get_history(active_agent)
      local line, reason = read_line(build_prompt(), history, complete_command)
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

      if line ~= "" then
        local cmd = parse_command(line)
        if cmd then
          local okc, flag = handle_command(cmd)
          if okc == false and flag == "exit" then
            break
          end
        else
          if not agent_manager.current_agent then
            io.stdout:write("请先使用 /switch <名称> 选择或创建 agent。\n")
          else
            io.stdout:write(string.format("[状态] 正在请求 agent: %s\n", agent_manager.current_agent))

            local okm1, errm1 = pcall(gateway.append_memory, agent_manager.current_agent, "user", line)
            if not okm1 and errm1 then
              io.stdout:write("[Gateway Memory Error] " .. tostring(errm1) .. "\n")
            end

            local function on_tool_progress(msg)
              io.stdout:write(msg .. "\n")
              io.stdout:flush()
            end

            restore_mode(stty_state)
            local ok2, resp = pcall(gateway.handle_input, line, agent_manager.current_agent, on_tool_progress)
            set_raw_mode()

            if ok2 then
              if resp ~= nil then
                local output = tostring(resp)
                local cfg_mod = dofile(base .. "/../Hub/config.lua")
                local cfg = cfg_mod.load_config(agent_manager.current_agent)
                local is_stream = cfg and cfg.stream or false

                if output ~= "" then
                  if not is_stream then
                    io.stdout:write(output .. "\n")
                  end
                  local okm2, errm2 = pcall(gateway.append_memory, agent_manager.current_agent, "assistant", output)
                  if not okm2 and errm2 then
                    io.stdout:write("[Gateway Memory Error] " .. tostring(errm2) .. "\n")
                  end
                else
                  io.stdout:write("[状态] 请求完成，但未返回可显示内容。\n")
                end
              else
                io.stdout:write("[状态] 请求完成，但未返回可显示内容。\n")
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
