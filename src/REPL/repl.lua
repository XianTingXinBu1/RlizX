-- RlizX REPL module (pure Lua)
local M = {}

function M.start(opts)
  opts = opts or {}
  local version = opts.version or "0.1.0"
  local default_prompt = opts.prompt or "> "

  local function script_dir()
    local info = debug.getinfo(1, "S")
    local src = info and info.source or ""
    if src:sub(1, 1) == "@" then
      src = src:sub(2)
    end
    return src:match("^(.*)/") or "."
  end

  local base = script_dir()
  local terminal = dofile(base .. "/terminal.lua")
  local runtime_mod = dofile(base .. "/command_chat.lua")
  local gateway = dofile(base .. "/../Gateway/gateway.lua")
  local agent_mod = dofile(base .. "/../Hub/agent.lua")
  local agent_manager = agent_mod.create_manager(base)

  local histories = {}

  local function print_version()
    terminal.printf("RlizX v%s\n", version)
  end

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

  local stty_state = terminal.get_stty_state()

  local runtime = runtime_mod.create_runtime({
    base = base,
    agent_manager = agent_manager,
    gateway = gateway,
    histories = histories,
    stty_state = stty_state,
    restore_mode = terminal.restore_mode,
    set_raw_mode = terminal.set_raw_mode,
    print_status = print_status,
    print_version = print_version,
  })

  io.stdout:write(string.format("RlizX REPL v%s\n", version))
  io.stdout:write("输入 '/help' 查看指令，'/exit' 退出。\n")
  print_status()

  terminal.set_raw_mode()

  local function get_history(agent)
    if not histories[agent] then
      histories[agent] = {}
    end
    return histories[agent]
  end

  local ok, err = pcall(function()
    while true do
      local active_agent = agent_manager.current_agent or "default"
      local history = get_history(active_agent)
      local line, reason = terminal.read_line(build_prompt(), history, runtime.complete_command)
      if not line then
        if reason == "interrupt" then
          break
        end
        break
      end

      line = runtime.trim(line)
      if line ~= "" then
        history[#history + 1] = line
      end

      local should_continue = runtime.handle_input_line(line)
      if should_continue == false then
        break
      end
    end
  end)

  terminal.restore_mode(stty_state)
  if not ok then
    error(err)
  end
end

return M