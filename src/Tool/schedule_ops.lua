-- RlizX Schedule Operations

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local M = package.loaded["rlizx.schedule_ops"]

if not M then
  M = {}

  local Scheduler = dofile(get_script_dir() .. "/../Hub/scheduler.lua")

  local function trim(s)
    return (tostring(s or ""):match("^%s*(.-)%s*$") or "")
  end

  local function collapse_path(path)
    local p = tostring(path or ""):gsub("\\", "/")
    local parts = {}
    for seg in p:gmatch("[^/]+") do
      if seg == ".." then
        if #parts > 0 then
          table.remove(parts)
        end
      elseif seg ~= "." and seg ~= "" then
        parts[#parts + 1] = seg
      end
    end
    return "/" .. table.concat(parts, "/")
  end

  local function get_cwd()
    local p = io.popen("pwd 2>/dev/null")
    if not p then
      return "/"
    end
    local line = p:read("*l")
    p:close()
    if not line or line == "" then
      return "/"
    end
    return line
  end

  local function project_root()
    local base = get_script_dir()
    if base:sub(1, 1) ~= "/" then
      base = get_cwd() .. "/" .. base
    end
    return collapse_path(base .. "/../..")
  end

  local manager = Scheduler.create_manager(project_root())

  local function pick_agent(args, context)
    local by_arg = trim(args and args.agent)
    if by_arg ~= "" then
      return by_arg
    end
    local by_ctx = trim(context and context.agent_name)
    if by_ctx ~= "" then
      return by_ctx
    end
    return ""
  end

  local function shape_job(job)
    return {
      id = job.id,
      agent = job.agent,
      mode = job.mode,
      prompt = job.prompt,
      status = job.status,
      run_at = job.run_at,
      interval_seconds = job.interval_seconds,
      minute_of_day = job.minute_of_day,
      next_run_at = job.next_run_at,
      last_run_at = job.last_run_at,
      run_count = job.run_count,
      last_error = job.last_error,
    }
  end

  function M.schedule_create_nl(args, context)
    local agent = pick_agent(args, context)
    if agent == "" then
      return { error = "缺少 agent（可通过参数 agent 或当前会话 agent 提供）" }
    end

    local natural_language = trim(args and args.natural_language)
    if natural_language == "" then
      return { error = "缺少必需参数: natural_language" }
    end

    local prompt = trim(args and args.prompt)
    local job, err = manager.create_job_from_nl(agent, natural_language, prompt)
    if not job then
      return { error = tostring(err or "创建任务失败") }
    end

    return { result = shape_job(job) }
  end

  function M.schedule_list(args, context)
    local agent = pick_agent(args, context)
    if agent == "" then
      return { error = "缺少 agent（可通过参数 agent 或当前会话 agent 提供）" }
    end

    local jobs, err = manager.list_jobs(agent)
    if not jobs then
      return { error = tostring(err or "读取任务失败") }
    end

    local out = {}
    for _, job in ipairs(jobs) do
      out[#out + 1] = shape_job(job)
    end
    return { result = out }
  end

  function M.schedule_delete(args, context)
    local agent = pick_agent(args, context)
    local job_id = trim(args and args.job_id)
    if agent == "" then
      return { error = "缺少 agent（可通过参数 agent 或当前会话 agent 提供）" }
    end
    if job_id == "" then
      return { error = "缺少必需参数: job_id" }
    end

    local ok, err = manager.delete_job(agent, job_id)
    if not ok then
      return { error = tostring(err or "删除任务失败") }
    end

    return { result = "任务已删除" }
  end

  function M.schedule_pause(args, context)
    local agent = pick_agent(args, context)
    local job_id = trim(args and args.job_id)
    if agent == "" then
      return { error = "缺少 agent（可通过参数 agent 或当前会话 agent 提供）" }
    end
    if job_id == "" then
      return { error = "缺少必需参数: job_id" }
    end

    local ok, err = manager.pause_job(agent, job_id)
    if not ok then
      return { error = tostring(err or "暂停任务失败") }
    end

    return { result = "任务已暂停" }
  end

  function M.schedule_resume(args, context)
    local agent = pick_agent(args, context)
    local job_id = trim(args and args.job_id)
    if agent == "" then
      return { error = "缺少 agent（可通过参数 agent 或当前会话 agent 提供）" }
    end
    if job_id == "" then
      return { error = "缺少必需参数: job_id" }
    end

    local ok, err = manager.resume_job(agent, job_id)
    if not ok then
      return { error = tostring(err or "恢复任务失败") }
    end

    return { result = "任务已恢复" }
  end

  package.loaded["rlizx.schedule_ops"] = M
end

return M