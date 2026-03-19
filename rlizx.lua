-- RlizX CLI (entry)
local VERSION = "0.1.0"

local function printf(fmt, ...)
  io.stdout:write(string.format(fmt, ...))
end

local function trim(s)
  return (tostring(s or ""):match("^%s*(.-)%s*$") or "")
end

local function shell_quote(s)
  return string.format("%q", tostring(s or ""))
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
  f:write(content or "")
  f:close()
  return true
end

local function ensure_dir(path)
  local ok = os.execute("mkdir -p " .. shell_quote(path))
  return ok == true or ok == 0
end

local function script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local function load_json_helpers(base)
  local U = dofile(base .. "/src/Hub/utils.lua")
  local JsonEncoder = dofile(base .. "/src/Tool/json_encoder.lua")
  return U, JsonEncoder
end

local function print_help()
  io.stdout:write([[
RlizX - 命令行 AI 编程助手（纯 Lua）

用法:
  lua rlizx.lua                                 直接进入 REPL
  lua rlizx.lua [command] [options]

命令:
  help                                          显示帮助
  version                                       显示版本
  repl                                          进入交互模式
  check                                         运行非交互式检查
  request <agent> <input...>                    单次请求指定 agent
  parallel <a,b,...> <input...>                 并发请求多个 agent
  queue submit <a,b,...> <input...>             提交后台并发任务
  queue list                                    列出任务
  queue status <task_id>                        查看任务状态与输出
  queue cancel <task_id>                        取消任务
  schedule create <agent> <自然语言时间> [prompt] 创建定时任务
  schedule list <agent>                         列出 agent 的定时任务
  schedule delete <agent> <job_id>              删除任务
  schedule pause <agent> <job_id>               暂停任务
  schedule resume <agent> <job_id>              恢复任务
  schedule run <agent> <job_id>                 立即执行任务一次
  schedule daemon <agent> [interval_sec]        轮询并执行到期任务

选项:
  -h, --help                                    显示帮助
  -v, --version                                 显示版本
]])
end

local function print_version()
  printf("RlizX v%s\n", VERSION)
end

local function run_repl()
  local base = script_dir()
  local repl = dofile(base .. "/src/REPL/repl.lua")
  repl.start({ version = VERSION, prompt = "> " })
end

local function run_check()
  local base = script_dir()
  local check = dofile(base .. "/src/Check/check.lua")
  local ok = check.run_all()
  if not ok then
    os.exit(1)
  end
end

local function run_request(agent_name, input)
  agent_name = trim(agent_name)
  if agent_name == "" then
    io.stderr:write("用法: lua rlizx.lua request <agent> <input...>\n")
    os.exit(2)
  end

  local content = tostring(input or "")
  if content == "" then
    io.stderr:write("用法: lua rlizx.lua request <agent> <input...>\n")
    os.exit(2)
  end

  local base = script_dir()
  local hub = dofile(base .. "/src/Hub/hub.lua")

  local okm1, errm1 = pcall(hub.append_memory, agent_name, "user", content)
  if not okm1 and errm1 then
    io.stderr:write("[Gateway Memory Error] " .. tostring(errm1) .. "\n")
  end

  local ok, resp = pcall(hub.handle_request, content, agent_name, nil)
  if not ok then
    io.stderr:write("[Gateway Error] " .. tostring(resp) .. "\n")
    os.exit(1)
  end

  local output = tostring(resp or "")
  if output ~= "" then
    io.stdout:write(output .. "\n")
  end

  local okm2, errm2 = pcall(hub.append_memory, agent_name, "assistant", output)
  if not okm2 and errm2 then
    io.stderr:write("[Gateway Memory Error] " .. tostring(errm2) .. "\n")
  end
end

local function run_request_file(agent_name, input_path)
  local content = read_file(input_path)
  if content == nil then
    io.stderr:write("无法读取输入文件: " .. tostring(input_path) .. "\n")
    os.exit(2)
  end
  run_request(agent_name, content)
end

local function pid_alive(pid)
  local cmd = "kill -0 " .. tostring(pid) .. " >/dev/null 2>&1"
  local ok = os.execute(cmd)
  return ok == true or ok == 0
end

local function run_parallel(agents_csv, input)
  local csv = trim(agents_csv)
  local content = tostring(input or "")

  if csv == "" or content == "" then
    io.stderr:write("用法: lua rlizx.lua parallel <a,b,...> <input...>\n")
    os.exit(2)
  end

  local agents = {}
  for raw in csv:gmatch("[^,]+") do
    local name = trim(raw)
    if name ~= "" then
      agents[#agents + 1] = name
    end
  end

  if #agents == 0 then
    io.stderr:write("parallel: 未提供有效 agent 列表\n")
    os.exit(2)
  end

  local base = script_dir()
  math.randomseed(os.time())
  local job_dir = string.format("%s/temp/parallel_%d_%04d", base, os.time(), math.random(0, 9999))

  local mk = os.execute("mkdir -p " .. shell_quote(job_dir))
  if not (mk == true or mk == 0) then
    io.stderr:write("无法创建并发任务目录: " .. job_dir .. "\n")
    os.exit(1)
  end

  local input_path = job_dir .. "/input.txt"
  if not write_file(input_path, content) then
    io.stderr:write("无法写入输入文件: " .. input_path .. "\n")
    os.exit(1)
  end

  local jobs = {}

  for _, agent in ipairs(agents) do
    local safe_name = agent:gsub("[^%w%-%._]", "_")
    local out_path = string.format("%s/%s.out", job_dir, safe_name)
    local err_path = string.format("%s/%s.err", job_dir, safe_name)

    local spawn_cmd = table.concat({
      "cd", shell_quote(base), "&&",
      "lua rlizx.lua request-file", shell_quote(agent), shell_quote(input_path),
      ">", shell_quote(out_path), "2>", shell_quote(err_path),
      "& echo $!",
    }, " ")

    local p = io.popen(spawn_cmd)
    if not p then
      jobs[#jobs + 1] = {
        agent = agent,
        pid = nil,
        out_path = out_path,
        err_path = err_path,
        spawn_error = "无法启动子进程",
      }
    else
      local pid = trim(p:read("*l") or "")
      p:close()
      jobs[#jobs + 1] = {
        agent = agent,
        pid = pid,
        out_path = out_path,
        err_path = err_path,
      }
    end
  end

  local pending = 0
  for _, job in ipairs(jobs) do
    if job.pid and job.pid ~= "" then
      pending = pending + 1
    end
  end

  while pending > 0 do
    pending = 0
    for _, job in ipairs(jobs) do
      if job.pid and job.pid ~= "" and pid_alive(job.pid) then
        pending = pending + 1
      end
    end
    if pending > 0 then
      os.execute("sleep 0.1")
    end
  end

  io.stdout:write(string.format("[parallel] 完成，agents=%d\n", #agents))

  for _, job in ipairs(jobs) do
    io.stdout:write(string.format("\n=== agent: %s ===\n", tostring(job.agent)))

    if job.spawn_error then
      io.stdout:write("[spawn error] " .. tostring(job.spawn_error) .. "\n")
    end

    local out = read_file(job.out_path) or ""
    local err = read_file(job.err_path) or ""

    if out ~= "" then
      io.stdout:write(out)
      if out:sub(-1) ~= "\n" then
        io.stdout:write("\n")
      end
    else
      io.stdout:write("(empty output)\n")
    end

    if err ~= "" then
      io.stdout:write("[stderr]\n" .. err)
      if err:sub(-1) ~= "\n" then
        io.stdout:write("\n")
      end
    end
  end
end

local function queue_store_path(base)
  return base .. "/temp/task_queue.json"
end

local function load_queue(base)
  local U = load_json_helpers(base)
  local path = queue_store_path(base)
  local raw = read_file(path)
  if not raw or raw == "" then
    return { tasks = {} }
  end

  local ok, data = pcall(U.json_parse, raw)
  if not ok or type(data) ~= "table" then
    return { tasks = {} }
  end

  if type(data.tasks) ~= "table" then
    data.tasks = {}
  end
  return data
end

local function save_queue(base, queue)
  local _, JsonEncoder = load_json_helpers(base)
  local path = queue_store_path(base)
  local ok_mk = ensure_dir(base .. "/temp")
  if not ok_mk then
    return false
  end
  return write_file(path, JsonEncoder.encode_json(queue or { tasks = {} }))
end

local function find_task(queue, task_id)
  if type(queue) ~= "table" or type(queue.tasks) ~= "table" then
    return nil
  end
  for i, t in ipairs(queue.tasks) do
    if tostring(t.id or "") == tostring(task_id or "") then
      return t, i
    end
  end
  return nil
end

local function refresh_queue(base, queue)
  local changed = false
  for _, t in ipairs(queue.tasks or {}) do
    local status = tostring(t.status or "")
    if status == "running" or status == "cancelling" then
      local pid = trim(t.pid or "")
      local alive = (pid ~= "") and pid_alive(pid)
      if not alive then
        local exit_raw = read_file(t.exit_path or "")
        local exit_code = tonumber(trim(exit_raw or ""))
        t.exit_code = exit_code
        t.finished_at = t.finished_at or os.time()
        if t.cancel_requested == true then
          t.status = "cancelled"
        elseif exit_code == 0 then
          t.status = "done"
        else
          t.status = "failed"
        end
        changed = true
      end
    end
  end

  if changed then
    save_queue(base, queue)
  end
end

local function next_task_id(queue)
  local idx = 0
  for _, t in ipairs(queue.tasks or {}) do
    local n = tonumber(t.seq or 0) or 0
    if n > idx then idx = n end
  end
  idx = idx + 1
  local now = os.time()
  return string.format("task_%d_%03d", now, idx), idx
end

local function queue_submit(agents_csv, input)
  local base = script_dir()
  local csv = trim(agents_csv)
  local content = tostring(input or "")

  if csv == "" or content == "" then
    io.stderr:write("用法: lua rlizx.lua queue submit <a,b,...> <input...>\n")
    os.exit(2)
  end

  local queue = load_queue(base)
  refresh_queue(base, queue)

  local task_id, seq = next_task_id(queue)
  local task_dir = string.format("%s/temp/tasks/%s", base, task_id)
  if not ensure_dir(task_dir) then
    io.stderr:write("无法创建任务目录: " .. task_dir .. "\n")
    os.exit(1)
  end

  local input_path = task_dir .. "/input.txt"
  local stdout_path = task_dir .. "/stdout.log"
  local stderr_path = task_dir .. "/stderr.log"
  local exit_path = task_dir .. "/exit.code"

  if not write_file(input_path, content) then
    io.stderr:write("无法写入任务输入: " .. input_path .. "\n")
    os.exit(1)
  end

  local spawn_cmd = table.concat({
    "cd", shell_quote(base), "&&",
    "(",
      "lua rlizx.lua queue-worker", shell_quote(task_id), shell_quote(csv), shell_quote(input_path),
      "; echo $? >", shell_quote(exit_path),
    ")",
    ">", shell_quote(stdout_path),
    "2>", shell_quote(stderr_path),
    "& echo $!",
  }, " ")

  local p = io.popen(spawn_cmd)
  if not p then
    io.stderr:write("无法启动后台任务\n")
    os.exit(1)
  end

  local pid = trim(p:read("*l") or "")
  p:close()
  if pid == "" then
    io.stderr:write("后台任务启动失败（未获得 PID）\n")
    os.exit(1)
  end

  local task = {
    id = task_id,
    seq = seq,
    agents = csv,
    status = "running",
    pid = pid,
    created_at = os.time(),
    started_at = os.time(),
    finished_at = nil,
    cancel_requested = false,
    input_path = input_path,
    stdout_path = stdout_path,
    stderr_path = stderr_path,
    exit_path = exit_path,
    exit_code = nil,
  }

  queue.tasks[#queue.tasks + 1] = task
  if not save_queue(base, queue) then
    io.stderr:write("任务已启动，但写入队列失败\n")
    os.exit(1)
  end

  io.stdout:write(string.format("[queue] submitted id=%s pid=%s agents=%s\n", task_id, pid, csv))
end

local function queue_list()
  local base = script_dir()
  local queue = load_queue(base)
  refresh_queue(base, queue)

  if type(queue.tasks) ~= "table" or #queue.tasks == 0 then
    io.stdout:write("[queue] empty\n")
    return
  end

  io.stdout:write("id | status | pid | agents\n")
  for _, t in ipairs(queue.tasks) do
    io.stdout:write(string.format("%s | %s | %s | %s\n",
      tostring(t.id or ""),
      tostring(t.status or ""),
      tostring(t.pid or "-"),
      tostring(t.agents or "")
    ))
  end
end

local function queue_status(task_id)
  local id = trim(task_id)
  if id == "" then
    io.stderr:write("用法: lua rlizx.lua queue status <task_id>\n")
    os.exit(2)
  end

  local base = script_dir()
  local queue = load_queue(base)
  refresh_queue(base, queue)

  local task = find_task(queue, id)
  if not task then
    io.stderr:write("任务不存在: " .. id .. "\n")
    os.exit(2)
  end

  io.stdout:write(string.format("id: %s\n", tostring(task.id)))
  io.stdout:write(string.format("status: %s\n", tostring(task.status or "")))
  io.stdout:write(string.format("pid: %s\n", tostring(task.pid or "")))
  io.stdout:write(string.format("agents: %s\n", tostring(task.agents or "")))
  io.stdout:write(string.format("created_at: %s\n", tostring(task.created_at or "")))
  io.stdout:write(string.format("started_at: %s\n", tostring(task.started_at or "")))
  io.stdout:write(string.format("finished_at: %s\n", tostring(task.finished_at or "")))
  io.stdout:write(string.format("exit_code: %s\n", tostring(task.exit_code or "")))

  local out = read_file(task.stdout_path or "") or ""
  local err = read_file(task.stderr_path or "") or ""

  io.stdout:write("--- stdout ---\n")
  if out == "" then
    io.stdout:write("(empty)\n")
  else
    io.stdout:write(out)
    if out:sub(-1) ~= "\n" then io.stdout:write("\n") end
  end

  io.stdout:write("--- stderr ---\n")
  if err == "" then
    io.stdout:write("(empty)\n")
  else
    io.stdout:write(err)
    if err:sub(-1) ~= "\n" then io.stdout:write("\n") end
  end
end

local function queue_cancel(task_id)
  local id = trim(task_id)
  if id == "" then
    io.stderr:write("用法: lua rlizx.lua queue cancel <task_id>\n")
    os.exit(2)
  end

  local base = script_dir()
  local queue = load_queue(base)
  refresh_queue(base, queue)

  local task = find_task(queue, id)
  if not task then
    io.stderr:write("任务不存在: " .. id .. "\n")
    os.exit(2)
  end

  local status = tostring(task.status or "")
  if status ~= "running" and status ~= "cancelling" then
    io.stdout:write(string.format("[queue] task=%s 当前状态=%s，无需取消\n", id, status))
    return
  end

  local pid = trim(task.pid or "")
  if pid == "" then
    io.stdout:write(string.format("[queue] task=%s 无 PID，标记取消\n", id))
    task.cancel_requested = true
    task.status = "cancelled"
    task.finished_at = os.time()
    save_queue(base, queue)
    return
  end

  os.execute("kill " .. shell_quote(pid) .. " >/dev/null 2>&1")
  task.cancel_requested = true
  task.status = "cancelling"
  save_queue(base, queue)
  io.stdout:write(string.format("[queue] cancel requested id=%s pid=%s\n", id, pid))
end

local function run_queue_worker(task_id, agents_csv, input_path)
  local id = trim(task_id)
  if id == "" then
    io.stderr:write("queue-worker: task_id 不能为空\n")
    os.exit(2)
  end

  local content = read_file(input_path)
  if content == nil then
    io.stderr:write("queue-worker: 无法读取输入文件: " .. tostring(input_path) .. "\n")
    os.exit(2)
  end

  run_parallel(agents_csv, content)
end

local function current_abs_dir()
  local p = io.popen("pwd 2>/dev/null")
  if not p then return "." end
  local line = p:read("*l")
  p:close()
  return line and line ~= "" and line or "."
end

local function get_schedule_manager()
  local base = script_dir()
  local Scheduler = dofile(base .. "/src/Hub/scheduler.lua")
  return Scheduler.create_manager(current_abs_dir())
end

local function schedule_runner(agent_name, prompt)
  local base = script_dir()
  local hub = dofile(base .. "/src/Hub/hub.lua")

  local okm1, errm1 = pcall(hub.append_memory, agent_name, "user", prompt)
  if not okm1 and errm1 then
    io.stderr:write("[Scheduler Memory Error] " .. tostring(errm1) .. "\n")
  end

  local ok, resp = pcall(hub.handle_request, prompt, agent_name, nil)
  if not ok then
    error(tostring(resp))
  end

  local output = tostring(resp or "")
  local okm2, errm2 = pcall(hub.append_memory, agent_name, "assistant", output)
  if not okm2 and errm2 then
    io.stderr:write("[Scheduler Memory Error] " .. tostring(errm2) .. "\n")
  end

  return output
end

local function schedule_create(agent_name, natural_language, prompt)
  local agent = trim(agent_name)
  local nl = trim(natural_language)
  local p = tostring(prompt or "")

  if agent == "" or nl == "" then
    io.stderr:write("用法: lua rlizx.lua schedule create <agent> <自然语言时间> [prompt]\n")
    os.exit(2)
  end

  local manager = get_schedule_manager()
  local job, err = manager.create_job_from_nl(agent, nl, p)
  if not job then
    io.stderr:write("创建任务失败: " .. tostring(err) .. "\n")
    os.exit(1)
  end

  io.stdout:write(string.format("[schedule] created id=%s mode=%s next=%s\n",
    tostring(job.id),
    tostring(job.mode),
    tostring(job.next_run_at or "")
  ))
end

local function schedule_list(agent_name)
  local agent = trim(agent_name)
  if agent == "" then
    io.stderr:write("用法: lua rlizx.lua schedule list <agent>\n")
    os.exit(2)
  end

  local manager = get_schedule_manager()
  local jobs, err = manager.list_jobs(agent)
  if not jobs then
    io.stderr:write("读取任务失败: " .. tostring(err) .. "\n")
    os.exit(1)
  end

  if #jobs == 0 then
    io.stdout:write("[schedule] empty\n")
    return
  end

  io.stdout:write("id | status | mode | next_run_at | prompt\n")
  for _, job in ipairs(jobs) do
    io.stdout:write(string.format("%s | %s | %s | %s | %s\n",
      tostring(job.id or ""),
      tostring(job.status or ""),
      tostring(job.mode or ""),
      tostring(job.next_run_at or ""),
      tostring(job.prompt or "")
    ))
  end
end

local function schedule_delete(agent_name, job_id)
  local agent = trim(agent_name)
  local id = trim(job_id)
  if agent == "" or id == "" then
    io.stderr:write("用法: lua rlizx.lua schedule delete <agent> <job_id>\n")
    os.exit(2)
  end

  local manager = get_schedule_manager()
  local ok, err = manager.delete_job(agent, id)
  if not ok then
    io.stderr:write("删除任务失败: " .. tostring(err) .. "\n")
    os.exit(1)
  end

  io.stdout:write("[schedule] deleted\n")
end

local function schedule_pause(agent_name, job_id)
  local agent = trim(agent_name)
  local id = trim(job_id)
  if agent == "" or id == "" then
    io.stderr:write("用法: lua rlizx.lua schedule pause <agent> <job_id>\n")
    os.exit(2)
  end

  local manager = get_schedule_manager()
  local ok, err = manager.pause_job(agent, id)
  if not ok then
    io.stderr:write("暂停任务失败: " .. tostring(err) .. "\n")
    os.exit(1)
  end

  io.stdout:write("[schedule] paused\n")
end

local function schedule_resume(agent_name, job_id)
  local agent = trim(agent_name)
  local id = trim(job_id)
  if agent == "" or id == "" then
    io.stderr:write("用法: lua rlizx.lua schedule resume <agent> <job_id>\n")
    os.exit(2)
  end

  local manager = get_schedule_manager()
  local ok, err = manager.resume_job(agent, id)
  if not ok then
    io.stderr:write("恢复任务失败: " .. tostring(err) .. "\n")
    os.exit(1)
  end

  io.stdout:write("[schedule] resumed\n")
end

local function schedule_run(agent_name, job_id)
  local agent = trim(agent_name)
  local id = trim(job_id)
  if agent == "" or id == "" then
    io.stderr:write("用法: lua rlizx.lua schedule run <agent> <job_id>\n")
    os.exit(2)
  end

  local manager = get_schedule_manager()
  local result, err = manager.run_job_now(agent, id, function(a, prompt)
    return schedule_runner(a, prompt)
  end)

  if not result then
    io.stderr:write("执行任务失败: " .. tostring(err) .. "\n")
    os.exit(1)
  end

  io.stdout:write(string.format("[schedule] run id=%s ok=%s\n",
    tostring(result.job and result.job.id or id),
    tostring(result.ok)
  ))

  if result.ok and result.response ~= nil then
    io.stdout:write(tostring(result.response) .. "\n")
  elseif not result.ok then
    io.stderr:write(tostring(result.response) .. "\n")
  end
end

local function schedule_daemon(agent_name, interval_sec)
  local agent = trim(agent_name)
  local interval = tonumber(interval_sec) or 30
  if agent == "" then
    io.stderr:write("用法: lua rlizx.lua schedule daemon <agent> [interval_sec]\n")
    os.exit(2)
  end
  if interval < 1 then
    interval = 1
  end

  local manager = get_schedule_manager()
  io.stdout:write(string.format("[schedule] daemon started agent=%s interval=%d\n", agent, interval))

  while true do
    local executed, err = manager.run_due_jobs(agent, function(a, prompt)
      return schedule_runner(a, prompt)
    end)

    if not executed then
      io.stderr:write("[schedule] daemon error: " .. tostring(err) .. "\n")
    else
      for _, item in ipairs(executed) do
        io.stdout:write(string.format("[schedule] fired id=%s ok=%s\n",
          tostring(item.job_id),
          tostring(item.ok)
        ))
        if item.ok and item.response ~= nil then
          io.stdout:write(tostring(item.response) .. "\n")
        elseif not item.ok then
          io.stderr:write(tostring(item.response) .. "\n")
        end
      end
    end

    os.execute("sleep " .. tostring(interval))
  end
end

local function main(argv)
  if #argv == 0 then
    run_repl()
    return
  end

  local cmd = argv[1]
  if cmd == "help" or cmd == "-h" or cmd == "--help" then
    print_help()
  elseif cmd == "version" or cmd == "-v" or cmd == "--version" then
    print_version()
  elseif cmd == "repl" then
    run_repl()
  elseif cmd == "check" then
    run_check()
  elseif cmd == "request" then
    local agent_name = argv[2]
    local input = table.concat(argv, " ", 3)
    run_request(agent_name, input)
  elseif cmd == "request-file" then
    local agent_name = argv[2]
    local input_path = argv[3]
    if not agent_name or not input_path then
      io.stderr:write("用法: lua rlizx.lua request-file <agent> <input_file>\n")
      os.exit(2)
    end
    run_request_file(agent_name, input_path)
  elseif cmd == "parallel" then
    local agents_csv = argv[2]
    local input = table.concat(argv, " ", 3)
    run_parallel(agents_csv, input)
  elseif cmd == "queue-worker" then
    local task_id = argv[2]
    local agents_csv = argv[3]
    local input_path = argv[4]
    if not task_id or not agents_csv or not input_path then
      io.stderr:write("用法: lua rlizx.lua queue-worker <task_id> <a,b,...> <input_file>\n")
      os.exit(2)
    end
    run_queue_worker(task_id, agents_csv, input_path)
  elseif cmd == "queue" then
    local sub = argv[2]
    if sub == "submit" then
      local agents_csv = argv[3]
      local input = table.concat(argv, " ", 4)
      queue_submit(agents_csv, input)
    elseif sub == "list" then
      queue_list()
    elseif sub == "status" then
      queue_status(argv[3])
    elseif sub == "cancel" then
      queue_cancel(argv[3])
    else
      io.stderr:write("用法: lua rlizx.lua queue submit <a,b,...> <input...> | list | status <id> | cancel <id>\n")
      os.exit(2)
    end
  elseif cmd == "schedule" then
    local sub = argv[2]
    if sub == "create" then
      local agent = argv[3]
      local natural_language = argv[4]
      local prompt = table.concat(argv, " ", 5)
      schedule_create(agent, natural_language, prompt)
    elseif sub == "list" then
      schedule_list(argv[3])
    elseif sub == "delete" then
      schedule_delete(argv[3], argv[4])
    elseif sub == "pause" then
      schedule_pause(argv[3], argv[4])
    elseif sub == "resume" then
      schedule_resume(argv[3], argv[4])
    elseif sub == "run" then
      schedule_run(argv[3], argv[4])
    elseif sub == "daemon" then
      schedule_daemon(argv[3], argv[4])
    else
      io.stderr:write("用法: lua rlizx.lua schedule create <agent> <自然语言时间> [prompt] | list <agent> | delete <agent> <job_id> | pause <agent> <job_id> | resume <agent> <job_id> | run <agent> <job_id> | daemon <agent> [interval_sec]\n")
      os.exit(2)
    end
  else
    io.stderr:write("未知命令: " .. cmd .. "\n")
    print_help()
  end
end

main(arg)
