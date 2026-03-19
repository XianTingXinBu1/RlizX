-- RlizX Tool Loop Handler

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local M = package.loaded["rlizx.tool_loop"]

if not M then
  M = {}

  local U = dofile(get_script_dir() .. "/../Hub/utils.lua")
  local JsonEncoder = dofile(get_script_dir() .. "/json_encoder.lua")
  local ToolCallParser = dofile(get_script_dir() .. "/tool_call_parser.lua")
  local MessageHandler = dofile(get_script_dir() .. "/message_handler.lua")
  local ConcurrentExecutor = dofile(get_script_dir() .. "/concurrent_executor.lua")

  local function trim(s)
    return (tostring(s or ""):match("^%s*(.-)%s*$"))
  end

  local function make_error(code, message, detail)
    return {
      ok = false,
      code = tostring(code or "UNKNOWN"),
      message = tostring(message or "unknown error"),
      detail = detail,
    }
  end

  local function make_ok(data)
    return {
      ok = true,
      data = data,
    }
  end

  function M.value_to_text(v)
    local tv = type(v)
    if tv == "nil" then
      return ""
    elseif tv == "string" then
      return v
    elseif tv == "number" or tv == "boolean" then
      return tostring(v)
    elseif tv == "table" then
      return JsonEncoder.encode_json(v)
    end
    return tostring(v)
  end

  function M.parse_arguments(raw)
    if type(raw) == "table" then
      return raw
    end

    if type(raw) ~= "string" then
      return {}
    end

    local s = trim(raw)
    if s == "" then
      return {}
    end

    local ok, obj = pcall(U.json_parse, s)
    if ok and type(obj) == "table" then
      return obj
    end

    return nil, "arguments 不是合法 JSON 对象"
  end

  function M.execute_single_tool(tool_call, on_progress, context)
    if on_progress then
      on_progress(string.format("\n[Tool] 调用: %s", tostring(tool_call.name)))
      on_progress(string.format("[Tool] 参数: %s", tostring(tool_call.arguments or "{}")))
    end

    local Registry = dofile(get_script_dir() .. "/tool_registry.lua")

    local parsed_args, parse_err = M.parse_arguments(tool_call.arguments)
    local result

    if not parsed_args then
      result = { error = "Invalid tool arguments: " .. tostring(parse_err) }
    else
      local ok, call_result = pcall(Registry.execute_tool, tool_call.name, parsed_args, context or {})
      if not ok then
        result = { error = "Tool execution error: " .. tostring(call_result) }
      else
        if type(call_result) == "table" then
          result = call_result
        else
          result = { result = call_result }
        end
      end
    end

    local is_error = result.error ~= nil
    local payload_text

    if is_error then
      payload_text = M.value_to_text(result.error)
      if payload_text == "" then
        payload_text = "unknown tool error"
      end
    else
      payload_text = M.value_to_text(result.result)
    end

    if on_progress then
      if is_error then
        on_progress(string.format("[Tool] 错误: %s", payload_text))
      else
        on_progress(string.format("[Tool] 结果: %s", payload_text))
      end
    end

    return {
      tool_call_id = tostring(tool_call.id or ""),
      role = "tool",
      content = payload_text,
    }
  end

  local function get_round_message(messages, cfg, http_request_fn)
    local payload = MessageHandler.build_payload_with_tools(messages, cfg)
    local Http = dofile(get_script_dir() .. "/../Hub/http.lua")

    if cfg.stream then
      local message, err = Http.stream_chat(cfg, payload)
      if not message then
        return nil, err
      end
      return message
    end

    local raw_response, err = http_request_fn(cfg, payload)
    if not raw_response then
      return nil, err
    end

    local body = Http.parse_http_body(raw_response)
    local message, msg_err = ToolCallParser.get_assistant_message_from_body(body)
    if not message then
      return nil, msg_err
    end
    return message
  end

  function M.handle_tool_loop_result(initial_messages, http_request_fn, cfg, on_progress)
    local messages = {}
    for i, msg in ipairs(initial_messages or {}) do
      messages[i] = msg
    end

    local context = {
      workspace_root = cfg and cfg.workspace_root,
      agent_name = cfg and cfg.agent_name,
    }

    local max_iterations = 5
    local iteration = 0

    while iteration < max_iterations do
      iteration = iteration + 1

      local assistant_message, err = get_round_message(messages, cfg, http_request_fn)
      if not assistant_message then
        return make_error("ROUND_REQUEST_FAILED", "请求模型失败", err)
      end

      local tool_calls = ToolCallParser.normalize_tool_calls(assistant_message.tool_calls)
      if #tool_calls == 0 then
        return make_ok(MessageHandler.message_to_text(assistant_message))
      end

      if on_progress then
        on_progress(string.format("\n[Tool] 检测到 %d 个工具调用", #tool_calls))
      end

      messages[#messages + 1] = {
        role = "assistant",
        tool_calls = tool_calls,
      }

      -- 使用并发执行器处理工具调用
      local tool_responses = ConcurrentExecutor.execute_tools_concurrent(tool_calls, context, on_progress)

      for _, tool_response in ipairs(tool_responses) do
        messages[#messages + 1] = tool_response
      end
    end

    return make_error("TOOL_LOOP_MAX_ITERATIONS", "工具调用循环超过最大迭代次数", max_iterations)
  end

  function M.handle_tool_loop(initial_messages, http_request_fn, cfg, on_progress)
    local result = M.handle_tool_loop_result(initial_messages, http_request_fn, cfg, on_progress)
    if result.ok then
      return result.data
    end
    if result.detail ~= nil then
      return nil, string.format("[%s] %s: %s", tostring(result.code), tostring(result.message), tostring(result.detail))
    end
    return nil, string.format("[%s] %s", tostring(result.code), tostring(result.message))
  end

  package.loaded["rlizx.tool_loop"] = M
end

return M