-- RlizX Worker Process
-- Worker进程，接收并执行任务

local worker_id = os.getenv("RLIZX_WORKER_ID") or "unknown"
local socket_path = arg[1]

if not socket_path then
  io.stderr:write("Usage: lua worker.lua <socket_path>\n")
  os.exit(1)
end

-- 设置工作目录
local BASE_DIR = (debug.getinfo(1, "S").source:sub(2):match("^(.*)/") or ".")
package.path = BASE_DIR .. "/?.lua;" .. package.path

-- 加载必要模块
local U = dofile(BASE_DIR .. "/utils.lua")
local Hub = dofile(BASE_DIR .. "/hub.lua")

-- Worker状态
local worker_state = {
  id = worker_id,
  socket_path = socket_path,
  status = "idle",
  tasks_processed = 0,
  started_at = os.time(),
  last_active = os.time()
}

-- 日志函数
local function log(level, message)
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  io.stderr:write(string.format("[%s] [Worker:%s] [%s] %s\n",
    timestamp, worker_id, level, message))
  io.stderr:flush()
end

-- 处理任务
local function process_task(task)
  log("INFO", "开始处理任务: " .. (task.id or "unknown"))

  worker_state.status = "busy"
  worker_state.last_active = os.time()

  local result = {
    task_id = task.id,
    worker_id = worker_id,
    status = "processing",
    started_at = os.time()
  }

  -- 验证任务
  if not task.agent_name or task.agent_name == "" then
    result.status = "error"
    result.error = "缺少 agent_name"
    result.completed_at = os.time()
    return result
  end

  if not task.input or task.input == "" then
    result.status = "error"
    result.error = "缺少 input"
    result.completed_at = os.time()
    return result
  end

  -- 执行请求
  local ok, response = pcall(Hub.handle_request, task.input, task.agent_name, nil)

  if ok then
    result.status = "success"
    result.response = response
    log("INFO", "任务完成: " .. task.id)
  else
    result.status = "error"
    result.error = tostring(response)
    log("ERROR", "任务失败: " .. task.id .. " - " .. tostring(response))
  end

  result.completed_at = os.time()

  worker_state.status = "idle"
  worker_state.tasks_processed = worker_state.tasks_processed + 1
  worker_state.last_active = os.time()

  return result
end

-- 通过socket接收任务
local function receive_task_via_socket()
  -- 使用socat或netcat监听socket
  -- 简化版本：使用nc监听

  local cmd = string.format('nc -U -l "%s" 2>/dev/null', socket_path)
  local handle = io.popen(cmd, "r")

  if not handle then
    log("ERROR", "无法监听socket: " .. socket_path)
    return nil
  end

  -- 读取数据（带超时）
  local data = handle:read("*a")
  handle:close()

  if data and data ~= "" then
    local ok, task = pcall(U.json_parse, data)
    if ok and type(task) == "table" then
      return task
    else
      log("ERROR", "无法解析任务数据: " .. tostring(data))
    end
  end

  return nil
end

-- 通过socket发送结果
local function send_result_via_socket(result)
  local result_json = U.json_encode(result)

  -- 简化版本：直接返回到标准输出
  io.stdout:write(result_json .. "\n")
  io.stdout:flush()

  return true
end

-- 主循环
local function main_loop()
  log("INFO", "Worker启动，Socket: " .. socket_path)

  -- 设置信号处理
  -- (Lua标准库不支持信号处理，这里简化处理)

  while true do
    -- 检查socket文件是否存在
    local f = io.open(socket_path, "r")
    if not f then
      log("ERROR", "Socket文件不存在，退出")
      break
    end
    f:close()

    -- 接收任务
    local task = receive_task_via_socket()

    if task then
      -- 处理任务
      local result = process_task(task)

      -- 发送结果
      send_result_via_socket(result)
    else
      -- 没有任务，短暂休眠
      os.execute("sleep 0.1")
    end

    -- 检查是否应该退出（空闲超时）
    local now = os.time()
    if worker_state.status == "idle" and
       (now - worker_state.last_active) > 300 then  -- 5分钟空闲

      log("INFO", "Worker空闲超时，退出")
      break
    end
  end

  log("INFO", "Worker退出，共处理任务: " .. worker_state.tasks_processed)
end

-- 启动
local ok, err = pcall(main_loop)

if not ok then
  log("ERROR", "Worker异常退出: " .. tostring(err))
  os.exit(1)
end

os.exit(0)