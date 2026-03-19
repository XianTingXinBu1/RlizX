-- RlizX REPL command/chat handlers (pure Lua)

local M = {}

local function trim(s)
  return (s:match("^%s*(.-)%s*$") or "")
end

function M.create_runtime(opts)
  opts = opts or {}

  local base = opts.base
  local agent_manager = opts.agent_manager
  local gateway = opts.gateway
  local histories = opts.histories or {}
  local stty_state = opts.stty_state
  local restore_mode = opts.restore_mode
  local set_raw_mode = opts.set_raw_mode
  local print_status = opts.print_status
  local print_version = opts.print_version

  local cfg_mod = dofile(base .. "/../Hub/config.lua")

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

  local function handle_chat_line(line)
    if not agent_manager.current_agent then
      io.stdout:write("请先使用 /switch <名称> 选择或创建 agent。\n")
      return
    end

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

    if not ok2 then
      io.stdout:write("[Gateway Error] " .. tostring(resp) .. "\n")
      return
    end

    if resp == nil then
      io.stdout:write("[状态] 请求完成，但未返回可显示内容。\n")
      return
    end

    local output = tostring(resp)
    local cfg = cfg_mod.load_config(agent_manager.current_agent)
    local is_stream = cfg and cfg.stream or false

    if output == "" then
      io.stdout:write("[状态] 请求完成，但未返回可显示内容。\n")
      return
    end

    if not is_stream then
      io.stdout:write(output .. "\n")
    end

    local okm2, errm2 = pcall(gateway.append_memory, agent_manager.current_agent, "assistant", output)
    if not okm2 and errm2 then
      io.stdout:write("[Gateway Memory Error] " .. tostring(errm2) .. "\n")
    end
  end

  local function handle_input_line(line)
    if line == "" then
      return true
    end

    local cmd = parse_command(line)
    if cmd then
      local okc, flag = handle_command(cmd)
      if okc == false and flag == "exit" then
        return false
      end
      return true
    end

    handle_chat_line(line)
    return true
  end

  return {
    trim = trim,
    complete_command = complete_command,
    handle_input_line = handle_input_line,
    print_help = repl_help,
  }
end

return M