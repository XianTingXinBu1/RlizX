-- RlizX Concurrent Tool Executor
-- 实现工具并发执行，提升工具调用性能

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local M = package.loaded["rlizx.concurrent_executor"]

if not M then
  M = {}

  local U = dofile(get_script_dir() .. "/../Hub/utils.lua")
  local JsonEncoder = dofile(get_script_dir() .. "/json_encoder.lua")

  -- 延迟加载 ToolLoop 以避免循环依赖
  local ToolLoop = nil
  local function get_tool_loop()
    if not ToolLoop then
      ToolLoop = dofile(get_script_dir() .. "/tool_loop.lua")
    end
    return ToolLoop
  end

  -- 配置
  local CONFIG = {
    max_concurrent_tools = 5,      -- 最大并发工具数
    tool_timeout = 30,             -- 单个工具超时（秒）
    enable_dependency_analysis = true  -- 启用依赖分析
  }

  -- 统计信息
  local stats = {
    total_executions = 0,
    parallel_executions = 0,
    serial_executions = 0,
    errors = 0
  }

  -- 分析工具依赖关系
  function M.analyze_dependencies(tool_calls)
    if not CONFIG.enable_dependency_analysis then
      return {}
    end

    local dependency_graph = {}
    local tool_names = {}

    -- 收集所有工具名称
    for _, call in ipairs(tool_calls) do
      tool_names[call.name] = true
    end

    -- 分析每个工具的依赖
    for _, call in ipairs(tool_calls) do
      local deps = {}

      -- 检查参数中是否引用了其他工具的输出
      for param_name, param_value in pairs(call.arguments) do
        if type(param_value) == "string" then
          -- 检查是否包含引用模式，如 {{tool_name}}
          for tool_name in pairs(tool_names) do
            if param_value:match("{{" .. tool_name .. "}}") or
               param_value:match("%$" .. tool_name) then
              deps[#deps + 1] = tool_name
            end
          end
        end
      end

      dependency_graph[call.name] = deps
    end

    return dependency_graph
  end

  -- 拓扑排序
  function M.topological_sort(tool_calls, dependency_graph)
    local sorted = {}
    local visited = {}
    local visiting = {}
    local temp_sorted = {}

    local function visit(call)
      if visiting[call.name] then
        -- 检测到循环依赖，使用名称作为标识
        return false, "循环依赖检测: " .. call.name
      end

      if visited[call.name] then
        return true
      end

      visiting[call.name] = true

      local deps = dependency_graph[call.name] or {}

      for _, dep_name in ipairs(deps) do
        local dep_call = nil
        for _, c in ipairs(tool_calls) do
          if c.name == dep_name then
            dep_call = c
            break
          end
        end

        if dep_call then
          local ok, err = visit(dep_call)
          if not ok then
            return false, err
          end
        end
      end

      visiting[call.name] = false
      visited[call.name] = true

      table.insert(temp_sorted, 1, call)  -- 逆序插入

      return true
    end

    -- 对每个工具进行访问
    for _, call in ipairs(tool_calls) do
      if not visited[call.name] then
        local ok, err = visit(call)
        if not ok then
          return nil, err
        end
      end
    end

    -- 返回正序
    for i = #temp_sorted, 1, -1 do
      sorted[#sorted + 1] = temp_sorted[i]
    end

    return sorted
  end

  -- 按层级分组
  function M.group_by_level(sorted_calls, dependency_graph)
    local levels = {}
    local tool_to_level = {}

    local function get_level(call)
      if tool_to_level[call.name] then
        return tool_to_level[call.name]
      end

      local deps = dependency_graph[call.name] or {}
      local max_dep_level = 0

      for _, dep_name in ipairs(deps) do
        for _, c in ipairs(sorted_calls) do
          if c.name == dep_name then
            local dep_level = get_level(c)
            if dep_level > max_dep_level then
              max_dep_level = dep_level
            end
            break
          end
        end
      end

      local level = max_dep_level + 1
      tool_to_level[call.name] = level

      if not levels[level] then
        levels[level] = {}
      end

      table.insert(levels[level], call)

      return level
    end

    for _, call in ipairs(sorted_calls) do
      get_level(call)
    end

    return levels
  end

  -- 执行单个工具（使用ToolLoop的函数）
  function M.execute_single_tool(call, context, on_progress)
    local tl = get_tool_loop()
    return tl.execute_single_tool(call, on_progress, context)
  end

  -- 执行一个层级的工具（并发）
  function M.execute_level(calls, context, on_progress)
    if #calls == 0 then
      return {}
    end

    if #calls == 1 then
      -- 单个工具，直接执行
      local result = M.execute_single_tool(calls[1], context, on_progress)
      stats.serial_executions = stats.serial_executions + 1
      return { result }
    end

    -- 多个工具，限制并发数
    local max_concurrent = math.min(CONFIG.max_concurrent_tools, #calls)
    stats.parallel_executions = stats.parallel_executions + 1

    -- 创建执行队列
    local execution_queue = {}
    for i, call in ipairs(calls) do
      execution_queue[i] = {
        call = call,
        index = i,
        status = "pending",
        result = nil,
        error = nil
      }
    end

    -- 创建协程
    local coroutines = {}
    for i = 1, #calls do
      local exec = execution_queue[i]
      coroutines[i] = coroutine.create(function()
        exec.status = "running"
        local result, err = pcall(M.execute_single_tool, exec.call, context, on_progress)

        if result then
          exec.result = result
          exec.status = "completed"
        else
          exec.error = err or "执行失败"
          exec.status = "failed"
          stats.errors = stats.errors + 1
        end

        stats.total_executions = stats.total_executions + 1
      end)
    end

    -- 调度协程
    local active_coroutines = {}
    local next_to_start = 1

    while next_to_start <= #calls or #active_coroutines > 0 do
      -- 启动新的协程（直到达到最大并发数）
      while #active_coroutines < max_concurrent and next_to_start <= #calls do
        table.insert(active_coroutines, {
          coroutine = coroutines[next_to_start],
          index = next_to_start
        })
        next_to_start = next_to_start + 1
      end

      -- 执行活跃的协程
      local next_active = {}

      for _, active in ipairs(active_coroutines) do
        local co = active.coroutine
        local success, err = coroutine.resume(co)

        if success then
          if coroutine.status(co) ~= "dead" then
            -- 协程仍在运行
            table.insert(next_active, active)
          end
        else
          -- 协程出错
          execution_queue[active.index].error = err
          execution_queue[active.index].status = "failed"
          stats.errors = stats.errors + 1
        end
      end

      active_coroutines = next_active

      -- 避免忙等待
      if #active_coroutines > 0 then
        os.execute("sleep 0.001")
      end
    end

    -- 收集结果
    local results = {}
    for i = 1, #calls do
      if execution_queue[i].result then
        results[i] = execution_queue[i].result
      else
        results[i] = {
          tool_call_id = execution_queue[i].call.id or "",
          role = "tool",
          content = "执行失败: " .. tostring(execution_queue[i].error)
        }
      end
    end

    return results
  end

  -- 主执行函数
  function M.execute_tools_concurrent(tool_calls, context, on_progress)
    if not tool_calls or #tool_calls == 0 then
      return {}
    end

    if #tool_calls == 1 then
      -- 单个工具，直接执行
      local result = M.execute_single_tool(tool_calls[1], context, on_progress)
      stats.total_executions = stats.total_executions + 1
      return { result }
    end

    -- 分析依赖关系
    local dependency_graph = M.analyze_dependencies(tool_calls)

    -- 检查是否有依赖
    local has_dependencies = false
    for _, deps in pairs(dependency_graph) do
      if #deps > 0 then
        has_dependencies = true
        break
      end
    end

    if not has_dependencies then
      -- 无依赖，所有工具可以并发执行
      local results = M.execute_level(tool_calls, context, on_progress)
      return results
    end

    -- 有依赖，需要按层级执行
    local sorted, err = M.topological_sort(tool_calls, dependency_graph)
    if not sorted then
      -- 拓扑排序失败，回退到串行执行
      if on_progress then
        on_progress("[Concurrent] 依赖分析失败，使用串行执行: " .. tostring(err))
      end

      local results = {}
      for _, call in ipairs(tool_calls) do
        local result = M.execute_single_tool(call, context, on_progress)
        results[#results + 1] = result
        stats.serial_executions = stats.serial_executions + 1
      end
      return results
    end

    -- 按层级分组
    local levels = M.group_by_level(sorted, dependency_graph)

    -- 按层级执行
    local all_results = {}

    for level, calls in ipairs(levels) do
      if on_progress then
        on_progress(string.format("[Concurrent] 执行层级 %d，工具数: %d", level, #calls))
      end

      local results = M.execute_level(calls, context, on_progress)

      for _, result in ipairs(results) do
        table.insert(all_results, result)
      end
    end

    return all_results
  end

  -- 获取统计信息
  function M.get_stats()
    return {
      total_executions = stats.total_executions,
      parallel_executions = stats.parallel_executions,
      serial_executions = stats.serial_executions,
      errors = stats.errors
    }
  end

  -- 获取配置
  function M.get_config()
    return {
      max_concurrent_tools = CONFIG.max_concurrent_tools,
      tool_timeout = CONFIG.tool_timeout,
      enable_dependency_analysis = CONFIG.enable_dependency_analysis
    }
  end

  -- 更新配置
  function M.update_config(new_config)
    if type(new_config) ~= "table" then
      return false, "配置必须是表格"
    end

    if new_config.max_concurrent_tools then
      CONFIG.max_concurrent_tools = new_config.max_concurrent_tools
    end

    if new_config.tool_timeout then
      CONFIG.tool_timeout = new_config.tool_timeout
    end

    if new_config.enable_dependency_analysis ~= nil then
      CONFIG.enable_dependency_analysis = new_config.enable_dependency_analysis
    end

    return true
  end

  package.loaded["rlizx.concurrent_executor"] = M
end

return M