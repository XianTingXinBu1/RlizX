-- RlizX Worker Pool Manager
-- 管理 Worker 进程池，实现进程复用以提升并发性能

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local M = package.loaded["rlizx.worker_pool"]

if not M then
  M = {}

  local BASE_DIR = get_script_dir()
  local U = dofile(BASE_DIR .. "/utils.lua")

  -- Worker池配置
  local POOL_CONFIG = {
    min_workers = 5,        -- 最小Worker数
    max_workers = 10,       -- 最大Worker数
    idle_timeout = 300,     -- 空闲超时（秒）
    max_tasks_per_worker = 100,  -- 每个Worker最大任务数
    worker_timeout = 30,    -- Worker超时（秒）
    socket_dir = "/tmp/rlizx_workers",  -- Socket目录
  }

  -- Worker状态
  M.workers = {}  -- worker_id -> worker_info

  -- 任务队列
  M.task_queue = {}

  -- 全局并发控制
  M.semaphore = 40

  -- 统计信息
  local stats = {
    tasks_submitted = 0,
    tasks_completed = 0,
    tasks_failed = 0,
    workers_created = 0,
    workers_recycled = 0,
    workers_killed = 0
  }

  -- 确保socket目录存在
  local function ensure_socket_dir()
    os.execute("mkdir -p " .. POOL_CONFIG.socket_dir .. " 2>/dev/null")
  end

  -- 生成Worker ID
  local function generate_worker_id()
    return string.format("worker_%d_%04d", os.time(), math.random(1000, 9999))
  }

  -- 生成任务ID
  local function generate_task_id()
    return string.format("task_%d_%04d", os.time(), math.random(10000, 99999))
  }

  -- 创建Worker进程
  function M.spawn_worker()
    local worker_id = generate_worker_id()
    local socket_path = string.format("%s/%s.sock", POOL_CONFIG.socket_dir, worker_id)
    local worker_script = BASE_DIR .. "/worker.lua"

    ensure_socket_dir()

    -- 启动Worker进程
    local cmd = string.format(
      'RLIZX_WORKER_ID="%s" lua "%s" "%s" & echo $!',
      worker_id,
      worker_script,
      socket_path
    )

    local handle = io.popen(cmd)
    if not handle then
      return nil, "无法启动Worker进程"
    end

    local pid = handle:read("*l")
    handle:close()

    if not pid or pid == "" then
      return nil, "Worker进程启动失败"
    end

    -- 等待socket文件创建
    local max_wait = 5
    local waited = 0
    while waited < max_wait do
      if M.file_exists(socket_path) then
        break
      end
      os.execute("sleep 0.1")
      waited = waited + 0.1
    end

    M.workers[worker_id] = {
      id = worker_id,
      pid = pid,
      socket_path = socket_path,
      tasks = 0,
      status = "idle",
      created_at = os.time(),
      last_active = os.time(),
      last_task_at = nil
    }

    stats.workers_created = stats.workers_created + 1

    return worker_id
  end

  -- 检查文件是否存在
  function M.file_exists(path)
    local f = io.open(path, "r")
    if f then
      f:close()
      return true
    end
    return false
  end

  -- 检查进程是否存活
  function M.is_process_alive(pid)
    if not pid or pid == "" then
      return false
    end
    local result = os.execute("kill -0 " .. pid .. " 2>/dev/null")
    return result == true or result == 0
  end

  -- 查找空闲Worker
  function M.find_idle_worker()
    local now = os.time()

    for worker_id, worker in pairs(M.workers) do
      -- 检查Worker是否空闲
      if worker.status == "idle" then
        -- 检查Worker是否存活
        if M.is_process_alive(worker.pid) then
          -- 检查是否达到最大任务数
          if worker.tasks < POOL_CONFIG.max_tasks_per_worker then
            -- 检查是否超时
            if (now - worker.last_active) < POOL_CONFIG.idle_timeout then
              return worker_id
            end
          end
        else
          -- 进程已死，清理
          M.kill_worker(worker_id)
        end
      end
    end

    return nil
  end

  -- 通过socket发送任务
  function M.send_task_via_socket(worker_id, task)
    local worker = M.workers[worker_id]
    if not worker then
      return false, "Worker不存在"
    end

    local socket_path = worker.socket_path

    -- 使用socat或netcat发送数据
    local task_json = U.json_encode(task)
    local cmd = string.format('echo "%s" | socat - UNIX-CONNECT:%s 2>/dev/null', task_json, socket_path)

    local handle = io.popen(cmd)
    if not handle then
      return false, "无法发送任务"
    end

    local response = handle:read("*a")
    handle:close()

    if response and response ~= "" then
      local ok, result = pcall(U.json_parse, response)
      if ok then
        return true, result
      end
    end

    return false, "任务发送失败"
  end

  -- 提交任务
  function M.submit_task(task)
    -- 等待信号量
    while M.semaphore <= 0 do
      os.execute("sleep 0.01")
    end
    M.semaphore = M.semaphore - 1

    -- 生成任务ID
    local task_id = generate_task_id()
    task.id = task_id
    task.submitted_at = os.time()

    -- 找到空闲Worker
    local worker_id = M.find_idle_worker()
    if not worker_id then
      -- 检查是否可以创建新Worker
      local current_workers = 0
      for _ in pairs(M.workers) do
        current_workers = current_workers + 1
      end

      if current_workers < POOL_CONFIG.max_workers then
        worker_id = M.spawn_worker()
        if not worker_id then
          M.semaphore = M.semaphore + 1
          return nil, "无法创建新Worker"
        end
      else
        -- 等待Worker释放
        worker_id = M.wait_for_worker()
        if not worker_id then
          M.semaphore = M.semaphore + 1
          return nil, "等待Worker超时"
        end
      end
    end

    -- 发送任务
    local success, err = M.send_task_via_socket(worker_id, task)
    if not success then
      M.semaphore = M.semaphore + 1
      return nil, err
    end

    -- 更新Worker状态
    local worker = M.workers[worker_id]
    worker.tasks = worker.tasks + 1
    worker.status = "busy"
    worker.last_active = os.time()
    worker.last_task_at = os.time()

    stats.tasks_submitted = stats.tasks_submitted + 1

    return {
      task_id = task_id,
      worker_id = worker_id
    }
  end

  -- 等待Worker释放
  function M.wait_for_worker(timeout)
    timeout = timeout or POOL_CONFIG.worker_timeout
    local start = os.time()

    while (os.time() - start) < timeout do
      local worker_id = M.find_idle_worker()
      if worker_id then
        return worker_id
      end
      os.execute("sleep 0.1")
    end

    return nil
  end

  -- 接收任务结果
  function M.receive_result(task_id, worker_id, timeout)
    timeout = timeout or POOL_CONFIG.worker_timeout
    local start = os.time()

    while (os.time() - start) < timeout do
      -- 这里需要实现从socket读取结果的逻辑
      -- 简化版本：假设任务已经完成

      -- 释放信号量
      M.semaphore = M.semaphore + 1

      -- 更新Worker状态
      if worker_id and M.workers[worker_id] then
        M.workers[worker_id].status = "idle"
        M.workers[worker_id].last_active = os.time()

        -- 检查是否需要回收Worker
        if M.workers[worker_id].tasks >= POOL_CONFIG.max_tasks_per_worker then
          M.recycle_worker(worker_id)
        end
      end

      stats.tasks_completed = stats.tasks_completed + 1

      return { success = true }
    end

    -- 超时
    if worker_id and M.workers[worker_id] then
      M.workers[worker_id].status = "idle"
    end
    M.semaphore = M.semaphore + 1
    stats.tasks_failed = stats.tasks_failed + 1

    return nil, "任务超时"
  }

  -- 回收Worker
  function M.recycle_worker(worker_id)
    local worker = M.workers[worker_id]
    if not worker then
      return false
    end

    M.kill_worker(worker_id)
    stats.workers_recycled = stats.workers_recycled + 1

    return true
  end

  -- 杀死Worker
  function M.kill_worker(worker_id)
    local worker = M.workers[worker_id]
    if not worker then
      return false
    end

    -- 杀死进程
    if M.is_process_alive(worker.pid) then
      os.execute("kill " .. worker.pid .. " 2>/dev/null")
    end

    -- 删除socket文件
    if M.file_exists(worker.socket_path) then
      os.execute("rm -f " .. worker.socket_path .. " 2>/dev/null")
    end

    -- 从池中移除
    M.workers[worker_id] = nil
    stats.workers_killed = stats.workers_killed + 1

    return true
  }

  -- 清理过期Worker
  function M.cleanup()
    local now = os.time()
    local cleaned = 0

    for worker_id, worker in pairs(M.workers) do
      -- 检查是否空闲超时
      if worker.status == "idle" and
         (now - worker.last_active) > POOL_CONFIG.idle_timeout then

        -- 如果超过最小Worker数，可以回收
        local current_workers = 0
        for _ in pairs(M.workers) do
          current_workers = current_workers + 1
        end

        if current_workers > POOL_CONFIG.min_workers then
          M.kill_worker(worker_id)
          cleaned = cleaned + 1
        end
      end

      -- 检查进程是否存活
      if not M.is_process_alive(worker.pid) then
        M.kill_worker(worker_id)
        cleaned = cleaned + 1
      end
    end

    return cleaned
  end

  -- 启动Worker池
  function M.start()
    ensure_socket_dir()

    -- 启动最小Worker数
    for i = 1, POOL_CONFIG.min_workers do
      local worker_id = M.spawn_worker()
      if not worker_id then
        print("[WorkerPool] 警告: 无法启动Worker " .. i)
      end
    end

    print("[WorkerPool] 启动完成，Worker数: " .. #M.workers)
  end

  -- 停止Worker池
  function M.stop()
    for worker_id, worker in pairs(M.workers) do
      M.kill_worker(worker_id)
    end

    -- 删除socket目录
    os.execute("rm -rf " .. POOL_CONFIG.socket_dir .. " 2>/dev/null")

    print("[WorkerPool] 停止完成")
  end

  -- 获取统计信息
  function M.get_stats()
    local idle_workers = 0
    local busy_workers = 0
    local total_tasks = 0

    for _, worker in pairs(M.workers) do
      if worker.status == "idle" then
        idle_workers = idle_workers + 1
      elseif worker.status == "busy" then
        busy_workers = busy_workers + 1
      end
      total_tasks = total_tasks + worker.tasks
    end

    return {
      total_workers = #M.workers,
      idle_workers = idle_workers,
      busy_workers = busy_workers,
      semaphore = M.semaphore,
      total_tasks = total_tasks,
      tasks_submitted = stats.tasks_submitted,
      tasks_completed = stats.tasks_completed,
      tasks_failed = stats.tasks_failed,
      workers_created = stats.workers_created,
      workers_recycled = stats.workers_recycled,
      workers_killed = stats.workers_killed
    }
  end

  -- 获取配置
  function M.get_config()
    return {
      min_workers = POOL_CONFIG.min_workers,
      max_workers = POOL_CONFIG.max_workers,
      idle_timeout = POOL_CONFIG.idle_timeout,
      max_tasks_per_worker = POOL_CONFIG.max_tasks_per_worker,
      worker_timeout = POOL_CONFIG.worker_timeout,
      socket_dir = POOL_CONFIG.socket_dir
    }
  end

  -- 更新配置
  function M.update_config(new_config)
    if type(new_config) ~= "table" then
      return false, "配置必须是表格"
    end

    if new_config.min_workers then
      POOL_CONFIG.min_workers = new_config.min_workers
    end

    if new_config.max_workers then
      POOL_CONFIG.max_workers = new_config.max_workers
    end

    if new_config.idle_timeout then
      POOL_CONFIG.idle_timeout = new_config.idle_timeout
    end

    if new_config.max_tasks_per_worker then
      POOL_CONFIG.max_tasks_per_worker = new_config.max_tasks_per_worker
    end

    if new_config.worker_timeout then
      POOL_CONFIG.worker_timeout = new_config.worker_timeout
    end

    if new_config.socket_dir then
      POOL_CONFIG.socket_dir = new_config.socket_dir
    end

    return true
  end

  package.loaded["rlizx.worker_pool"] = M
end

return M