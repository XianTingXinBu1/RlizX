-- RlizX Tool Executor

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local M = package.loaded["rlizx.tool_executor"]

if not M then
  M = {}

  local U = dofile(get_script_dir() .. "/../Hub/utils.lua")

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

  local function is_array(t)
    if type(t) ~= "table" then
      return false
    end
    local max = 0
    local count = 0
    for k, _ in pairs(t) do
      if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
        return false
      end
      if k > max then
        max = k
      end
      count = count + 1
    end
    return max == count
  end

  local function encode_json(v)
    local tv = type(v)
    if tv == "nil" then
      return "null"
    elseif tv == "boolean" then
      return v and "true" or "false"
    elseif tv == "number" then
      return tostring(v)
    elseif tv == "string" then
      return '"' .. U.json_escape(v) .. '"'
    elseif tv == "table" then
      if is_array(v) then
        local parts = {}
        for i = 1, #v do
          parts[#parts + 1] = encode_json(v[i])
        end
        return "[" .. table.concat(parts, ",") .. "]"
      end

      local keys = {}
      for k, _ in pairs(v) do
        keys[#keys + 1] = tostring(k)
      end
      table.sort(keys)

      local parts = {}
      for _, k in ipairs(keys) do
        parts[#parts + 1] = string.format('"%s":%s', U.json_escape(k), encode_json(v[k]))
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end

    return '""'
  end

  local function parse_response_json(response_body)
    local ok, data = pcall(U.json_parse, response_body)
    if not ok or type(data) ~= "table" then
      return nil, "响应不是合法 JSON"
    end
    return data
  end

  local function get_assistant_message_from_body(response_body)
    local data, err = parse_response_json(response_body)
    if not data then
      return nil, err
    end

    local choices = data.choices
    if type(choices) ~= "table" or #choices == 0 then
      return nil, "响应缺少 choices"
    end

    local first = choices[1]
    if type(first) ~= "table" then
      return nil, "响应 choices[1] 非对象"
    end

    local message = first.message
    if type(message) ~= "table" then
      return nil, "响应缺少 message"
    end

    return message
  end

  local function message_to_text(message)
    if not message then
      return ""
    end

    local content = message.content
    if type(content) == "string" then
      return content
    end

    if type(content) == "table" then
      local parts = {}
      for _, item in ipairs(content) do
        if type(item) == "table" then
          if type(item.text) == "string" then
            parts[#parts + 1] = item.text
          elseif type(item.output_text) == "string" then
            parts[#parts + 1] = item.output_text
          end
        elseif type(item) == "string" then
          parts[#parts + 1] = item
        end
      end
      return table.concat(parts, "")
    end

    return ""
  end

  local function parse_arguments(raw)
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

  local function normalize_tool_calls(calls)
    if type(calls) ~= "table" then
      return {}
    end

    local tool_calls = {}
    for i, item in ipairs(calls) do
      if type(item) == "table" then
        if item.name and item.arguments ~= nil then
          tool_calls[#tool_calls + 1] = {
            id = tostring(item.id or ("tool_call_" .. tostring(i))),
            name = tostring(item.name),
            arguments = tostring(item.arguments),
          }
        else
          local id = tostring(item.id or ("tool_call_" .. tostring(i)))
          local func = item["function"]
          if type(func) == "table" then
            local name = func.name
            if type(name) == "string" and name ~= "" then
              local raw_args = func.arguments
              local args_str
              if type(raw_args) == "string" then
                args_str = raw_args
              elseif type(raw_args) == "table" then
                args_str = encode_json(raw_args)
              else
                args_str = "{}"
              end

              tool_calls[#tool_calls + 1] = {
                id = id,
                name = name,
                arguments = args_str,
              }
            end
          end
        end
      end
    end

    return tool_calls
  end

  function M.parse_tool_calls(response_body)
    local message = get_assistant_message_from_body(response_body)
    if not message then
      return {}
    end
    return normalize_tool_calls(message.tool_calls)
  end

  function M.detect_tool_calls(response_body)
    local message = get_assistant_message_from_body(response_body)
    if not message then
      return false
    end

    local calls = normalize_tool_calls(message.tool_calls)
    return #calls > 0
  end

  local function value_to_text(v)
    local tv = type(v)
    if tv == "nil" then
      return ""
    elseif tv == "string" then
      return v
    elseif tv == "number" or tv == "boolean" then
      return tostring(v)
    elseif tv == "table" then
      return encode_json(v)
    end
    return tostring(v)
  end

  function M.execute_single_tool(tool_call, on_progress, context)
    if on_progress then
      on_progress(string.format("\n[Tool] 调用: %s", tostring(tool_call.name)))
      on_progress(string.format("[Tool] 参数: %s", tostring(tool_call.arguments or "{}")))
    end

    local Registry = dofile(get_script_dir() .. "/tool_registry.lua")

    local parsed_args, parse_err = parse_arguments(tool_call.arguments)
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
      payload_text = value_to_text(result.error)
      if payload_text == "" then
        payload_text = "unknown tool error"
      end
    else
      payload_text = value_to_text(result.result)
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
    local payload = M.build_payload_with_tools(messages, cfg)
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
    local message, msg_err = get_assistant_message_from_body(body)
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
    }

    local max_iterations = 5
    local iteration = 0

    while iteration < max_iterations do
      iteration = iteration + 1

      local assistant_message, err = get_round_message(messages, cfg, http_request_fn)
      if not assistant_message then
        return make_error("ROUND_REQUEST_FAILED", "请求模型失败", err)
      end

      local tool_calls = normalize_tool_calls(assistant_message.tool_calls)
      if #tool_calls == 0 then
        return make_ok(message_to_text(assistant_message))
      end

      if on_progress then
        on_progress(string.format("\n[Tool] 检测到 %d 个工具调用", #tool_calls))
      end

      messages[#messages + 1] = {
        role = "assistant",
        tool_calls = tool_calls,
      }

      for _, tool_call in ipairs(tool_calls) do
        local tool_response = M.execute_single_tool(tool_call, on_progress, context)
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

  function M.build_payload_with_tools(messages, cfg)
    local Registry = dofile(get_script_dir() .. "/tool_registry.lua")

    local enabled_tools = Registry.get_enabled_tools(cfg)
    local all_defs = Registry.get_all_tools_definitions()

    local enabled_set = {}
    for _, name in ipairs(enabled_tools) do
      enabled_set[name] = true
    end

    local active_tools = {}
    for _, def in ipairs(all_defs) do
      local f = def and def["function"]
      local name = f and f.name
      if enabled_set[name] then
        active_tools[#active_tools + 1] = def
      end
    end

    local msg_parts = {}
    for _, msg in ipairs(messages or {}) do
      if msg.tool_calls then
        local call_parts = {}
        for _, tc in ipairs(msg.tool_calls) do
          call_parts[#call_parts + 1] = string.format(
            '{"id":"%s","type":"function","function":{"name":"%s","arguments":"%s"}}',
            U.json_escape(tostring(tc.id or "")),
            U.json_escape(tostring(tc.name or "")),
            U.json_escape(tostring(tc.arguments or "{}"))
          )
        end
        msg_parts[#msg_parts + 1] = string.format(
          '{"role":"assistant","tool_calls":[%s]}',
          table.concat(call_parts, ",")
        )
      elseif msg.role == "tool" then
        msg_parts[#msg_parts + 1] = string.format(
          '{"tool_call_id":"%s","role":"tool","content":"%s"}',
          U.json_escape(tostring(msg.tool_call_id or "")),
          U.json_escape(tostring(msg.content or ""))
        )
      else
        msg_parts[#msg_parts + 1] = string.format(
          '{"role":"%s","content":"%s"}',
          U.json_escape(tostring(msg.role or "user")),
          U.json_escape(tostring(msg.content or ""))
        )
      end
    end

    local tool_parts = {}
    for _, def in ipairs(active_tools) do
      local f = def["function"] or {}
      local params = f.parameters or { type = "object", properties = {}, required = {} }
      local properties = params.properties or {}
      local required = params.required or {}

      local prop_keys = {}
      for k, _ in pairs(properties) do
        prop_keys[#prop_keys + 1] = k
      end
      table.sort(prop_keys)

      local prop_parts = {}
      for _, key in ipairs(prop_keys) do
        local p = properties[key] or {}
        prop_parts[#prop_parts + 1] = string.format(
          '"%s":{"type":"%s","description":"%s"}',
          U.json_escape(tostring(key)),
          U.json_escape(tostring(p.type or "string")),
          U.json_escape(tostring(p.description or ""))
        )
      end

      local req_parts = {}
      for _, name in ipairs(required) do
        req_parts[#req_parts + 1] = string.format('"%s"', U.json_escape(tostring(name)))
      end

      local params_json = string.format(
        '{"type":"%s","properties":{%s},"required":[%s]}',
        U.json_escape(tostring(params.type or "object")),
        table.concat(prop_parts, ","),
        table.concat(req_parts, ",")
      )

      tool_parts[#tool_parts + 1] = string.format(
        '{"type":"function","function":{"name":"%s","description":"%s","parameters":%s}}',
        U.json_escape(tostring(f.name or "")),
        U.json_escape(tostring(f.description or "")),
        params_json
      )
    end

    local tools_json = "[" .. table.concat(tool_parts, ",") .. "]"

    return string.format(
      '{"model":"%s","temperature":%s,"stream":%s,"messages":[%s],"tools":%s}',
      U.json_escape(tostring(cfg.model or "")),
      tostring(cfg.temperature or 0),
      (cfg.stream and "true" or "false"),
      table.concat(msg_parts, ","),
      tools_json
    )
  end

  package.loaded["rlizx.tool_executor"] = M
end

return M
