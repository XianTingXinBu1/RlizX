-- RlizX Scheduler (per-agent persisted jobs)

local M = {}

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local U = dofile(get_script_dir() .. "/utils.lua")
local JsonEncoder = dofile(get_script_dir() .. "/../Tool/json_encoder.lua")

local function trim(s)
  return (tostring(s or ""):match("^%s*(.-)%s*$") or "")
end

local function shell_quote(s)
  return string.format("%q", tostring(s or ""))
end

local function ensure_dir(path)
  local ok = os.execute("mkdir -p " .. shell_quote(path))
  return ok == true or ok == 0
end

local function normalize_abs(path)
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

local function is_valid_agent_name(name)
  return type(name) == "string" and name:match("^[%w%-%_]+$") ~= nil
end

local function now_ts()
  return os.time()
end

local function minute_of_day(hour, minute)
  return (tonumber(hour) or 0) * 60 + (tonumber(minute) or 0)
end

local function parse_hhmm(text)
  local h, m = text:match("^(%d%d?):(%d%d)$")
  if not h then
    h = text:match("^(%d%d?)点$")
    if h then
      m = "00"
    end
  end
  h = tonumber(h)
  m = tonumber(m)
  if not h or not m then
    return nil
  end
  if h < 0 or h > 23 or m < 0 or m > 59 then
    return nil
  end
  return h, m
end

local function parse_natural_schedule(text)
  local t = trim(text)
  if t == "" then
    return nil, "natural_language 不能为空"
  end

  local n

  n = tonumber(t:match("(%d+)%s*秒后"))
  if n and n > 0 then
    return { mode = "once", run_at = now_ts() + n }, nil
  end

  n = tonumber(t:match("(%d+)%s*分钟后"))
  if n and n > 0 then
    return { mode = "once", run_at = now_ts() + n * 60 }, nil
  end

  n = tonumber(t:match("(%d+)%s*小时后"))
  if n and n > 0 then
    return { mode = "once", run_at = now_ts() + n * 3600 }, nil
  end

  local h, m = t:match("每天%s*(%d%d?)%s*[:点时]%s*(%d?%d?)")
  if h then
    h = tonumber(h)
    if m == "" then m = "0" end
    m = tonumber(m)
    if h and m and h >= 0 and h <= 23 and m >= 0 and m <= 59 then
      return { mode = "daily", minute_of_day = minute_of_day(h, m) }, nil
    end
  end

  local only_h = tonumber(t:match("每天%s*(%d%d?)点"))
  if only_h and only_h >= 0 and only_h <= 23 then
    return { mode = "daily", minute_of_day = minute_of_day(only_h, 0) }, nil
  end

  local i, unit = t:match("每隔%s*(%d+)%s*(秒|分钟|小时)")
  i = tonumber(i)
  if i and i > 0 and unit then
    if unit == "秒" then
      return { mode = "interval", interval_seconds = i }, nil
    elseif unit == "分钟" then
      return { mode = "interval", interval_seconds = i * 60 }, nil
    elseif unit == "小时" then
      return { mode = "interval", interval_seconds = i * 3600 }, nil
    end
  end

  local dh, dm = t:match("明天%s*(%d%d?)%s*[:点时]%s*(%d?%d?)")
  if dh then
    dh = tonumber(dh)
    if dm == "" then dm = "0" end
    dm = tonumber(dm)
    if dh and dm and dh >= 0 and dh <= 23 and dm >= 0 and dm <= 59 then
      local now = os.date("*t")
      local run = {
        year = now.year,
        month = now.month,
        day = now.day + 1,
        hour = dh,
        min = dm,
        sec = 0,
      }
      return { mode = "once", run_at = os.time(run) }, nil
    end
  end

  local hhmm = t:match("在%s*(%d%d?:%d%d)")
  if hhmm then
    local ph, pm = parse_hhmm(hhmm)
    if ph then
      local now = os.date("*t")
      local run = {
        year = now.year,
        month = now.month,
        day = now.day,
        hour = ph,
        min = pm,
        sec = 0,
      }
      local ts = os.time(run)
      if ts <= now_ts() then
        ts = ts + 24 * 3600
      end
      return { mode = "once", run_at = ts }, nil
    end
  end

  return nil, "暂不支持该自然语言时间表达，请使用：X分钟后 / 每天9点 / 每隔10分钟 / 明天9点"
end

local function infer_prompt_from_text(text)
  local t = trim(text)
  local p = t

  p = p:gsub("^%s*请?在[%S%s]-提醒我", "")
  p = p:gsub("^%s*请?每[%S%s]-提醒我", "")
  p = p:gsub("^%s*提醒我", "")
  p = trim(p)

  if p == "" then
    return "请执行预定任务并汇报结果。"
  end
  return p
end

local function build_paths(project_root, agent_name)
  local root = normalize_abs(project_root)
  local agent_root = normalize_abs(root .. "/agents/" .. tostring(agent_name))
  local rlizx_dir = agent_root .. "/.rlizx"
  return {
    project_root = root,
    agent_root = agent_root,
    rlizx_dir = rlizx_dir,
    store = rlizx_dir .. "/schedules.json",
  }
end

local function load_store(path)
  local raw = U.read_file(path)
  if not raw or raw == "" then
    return { seq = 0, jobs = {} }
  end
  local ok, data = pcall(U.json_parse, raw)
  if not ok or type(data) ~= "table" then
    return { seq = 0, jobs = {} }
  end
  if type(data.seq) ~= "number" then
    data.seq = 0
  end
  if type(data.jobs) ~= "table" then
    data.jobs = {}
  end
  return data
end

local function save_store(path, store)
  local encoded = JsonEncoder.encode_json(store or { seq = 0, jobs = {} })
  return U.write_file(path, encoded)
end

local function compute_next_run(job, now)
  now = tonumber(now) or now_ts()
  if job.status == "paused" or job.status == "deleted" then
    return nil
  end

  if job.mode == "once" then
    return tonumber(job.run_at)
  elseif job.mode == "interval" then
    local last = tonumber(job.last_run_at)
    local iv = tonumber(job.interval_seconds) or 0
    if iv <= 0 then
      return nil
    end
    if not last then
      return tonumber(job.created_at) + iv
    end
    return last + iv
  elseif job.mode == "daily" then
    local moday = tonumber(job.minute_of_day)
    if not moday or moday < 0 or moday >= 24 * 60 then
      return nil
    end
    local dt = os.date("*t", now)
    local target = {
      year = dt.year,
      month = dt.month,
      day = dt.day,
      hour = math.floor(moday / 60),
      min = moday % 60,
      sec = 0,
    }
    local ts = os.time(target)
    if ts <= now then
      ts = ts + 24 * 3600
    end
    return ts
  end
  return nil
end

local function create_job_from_spec(agent_name, spec)
  local now = now_ts()
  local job = {
    id = "",
    agent = agent_name,
    prompt = tostring(spec.prompt or ""),
    mode = tostring(spec.mode or ""),
    run_at = tonumber(spec.run_at),
    interval_seconds = tonumber(spec.interval_seconds),
    minute_of_day = tonumber(spec.minute_of_day),
    status = "active",
    created_at = now,
    last_run_at = nil,
    next_run_at = nil,
    run_count = 0,
    last_error = nil,
  }

  if job.prompt == "" then
    return nil, "prompt 不能为空"
  end

  if job.mode ~= "once" and job.mode ~= "interval" and job.mode ~= "daily" then
    return nil, "mode 必须为 once / interval / daily"
  end

  if job.mode == "once" then
    if not job.run_at or job.run_at <= now then
      return nil, "run_at 必须是未来时间戳"
    end
  elseif job.mode == "interval" then
    if not job.interval_seconds or job.interval_seconds <= 0 then
      return nil, "interval_seconds 必须大于 0"
    end
  elseif job.mode == "daily" then
    if not job.minute_of_day or job.minute_of_day < 0 or job.minute_of_day >= 24 * 60 then
      return nil, "minute_of_day 需在 0..1439"
    end
  end

  job.next_run_at = compute_next_run(job, now)
  return job
end

local function find_job(store, job_id)
  if type(store) ~= "table" or type(store.jobs) ~= "table" then
    return nil, nil
  end
  for i, job in ipairs(store.jobs) do
    if tostring(job.id or "") == tostring(job_id or "") then
      return job, i
    end
  end
  return nil, nil
end

function M.create_manager(project_root)
  local manager = {}

  local function load_agent_store(agent_name)
    if not is_valid_agent_name(agent_name) then
      return nil, "非法 agent 名称"
    end

    local paths = build_paths(project_root, agent_name)
    if not ensure_dir(paths.rlizx_dir) then
      return nil, "无法创建目录: " .. paths.rlizx_dir
    end

    local store = load_store(paths.store)
    return {
      paths = paths,
      store = store,
    }
  end

  local function save_agent_store(state)
    return save_store(state.paths.store, state.store)
  end

  function manager.create_job(agent_name, spec)
    local state, err = load_agent_store(agent_name)
    if not state then
      return nil, err
    end

    local job, err2 = create_job_from_spec(agent_name, spec)
    if not job then
      return nil, err2
    end

    state.store.seq = tonumber(state.store.seq or 0) + 1
    local seq = tonumber(state.store.seq)
    job.id = string.format("job_%d_%03d", now_ts(), seq)

    state.store.jobs[#state.store.jobs + 1] = job
    if not save_agent_store(state) then
      return nil, "保存任务失败"
    end

    return job
  end

  function manager.create_job_from_nl(agent_name, natural_language, prompt)
    local parsed, err = parse_natural_schedule(natural_language)
    if not parsed then
      return nil, err
    end

    local final_prompt = trim(prompt or "")
    if final_prompt == "" then
      final_prompt = infer_prompt_from_text(natural_language)
    end

    local spec = {
      prompt = final_prompt,
      mode = parsed.mode,
      run_at = parsed.run_at,
      interval_seconds = parsed.interval_seconds,
      minute_of_day = parsed.minute_of_day,
    }

    return manager.create_job(agent_name, spec)
  end

  function manager.list_jobs(agent_name)
    local state, err = load_agent_store(agent_name)
    if not state then
      return nil, err
    end

    local now = now_ts()
    for _, job in ipairs(state.store.jobs) do
      job.next_run_at = compute_next_run(job, now)
    end
    save_agent_store(state)

    return state.store.jobs
  end

  function manager.delete_job(agent_name, job_id)
    local state, err = load_agent_store(agent_name)
    if not state then
      return false, err
    end

    local _, idx = find_job(state.store, job_id)
    if not idx then
      return false, "任务不存在"
    end

    table.remove(state.store.jobs, idx)
    if not save_agent_store(state) then
      return false, "保存任务失败"
    end
    return true
  end

  function manager.pause_job(agent_name, job_id)
    local state, err = load_agent_store(agent_name)
    if not state then
      return false, err
    end

    local job = find_job(state.store, job_id)
    if not job then
      return false, "任务不存在"
    end

    job.status = "paused"
    job.next_run_at = nil

    if not save_agent_store(state) then
      return false, "保存任务失败"
    end
    return true
  end

  function manager.resume_job(agent_name, job_id)
    local state, err = load_agent_store(agent_name)
    if not state then
      return false, err
    end

    local job = find_job(state.store, job_id)
    if not job then
      return false, "任务不存在"
    end

    job.status = "active"
    job.next_run_at = compute_next_run(job, now_ts())

    if not save_agent_store(state) then
      return false, "保存任务失败"
    end
    return true
  end

  function manager.run_job_now(agent_name, job_id, runner)
    if type(runner) ~= "function" then
      return nil, "runner 必须是函数"
    end

    local state, err = load_agent_store(agent_name)
    if not state then
      return nil, err
    end

    local job = find_job(state.store, job_id)
    if not job then
      return nil, "任务不存在"
    end

    local ok, resp = pcall(runner, agent_name, job.prompt, job)
    local now = now_ts()
    job.last_run_at = now
    job.run_count = tonumber(job.run_count or 0) + 1

    if ok then
      job.last_error = nil
      if job.mode == "once" then
        job.status = "done"
        job.next_run_at = nil
      else
        job.next_run_at = compute_next_run(job, now)
      end
    else
      job.last_error = tostring(resp)
      job.next_run_at = compute_next_run(job, now)
    end

    save_agent_store(state)

    return {
      ok = ok,
      response = resp,
      job = job,
    }
  end

  function manager.run_due_jobs(agent_name, runner)
    if type(runner) ~= "function" then
      return nil, "runner 必须是函数"
    end

    local state, err = load_agent_store(agent_name)
    if not state then
      return nil, err
    end

    local now = now_ts()
    local executed = {}

    for _, job in ipairs(state.store.jobs) do
      local next_run = compute_next_run(job, now)
      job.next_run_at = next_run

      if job.status == "active" and next_run and next_run <= now then
        local ok, resp = pcall(runner, agent_name, job.prompt, job)
        local run_now = now_ts()

        job.last_run_at = run_now
        job.run_count = tonumber(job.run_count or 0) + 1

        if ok then
          job.last_error = nil
          if job.mode == "once" then
            job.status = "done"
            job.next_run_at = nil
          else
            job.next_run_at = compute_next_run(job, run_now)
          end
        else
          job.last_error = tostring(resp)
          job.next_run_at = compute_next_run(job, run_now)
        end

        executed[#executed + 1] = {
          job_id = job.id,
          ok = ok,
          response = resp,
        }
      end
    end

    save_agent_store(state)
    return executed
  end

  return manager
end

return M