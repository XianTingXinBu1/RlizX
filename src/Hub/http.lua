local U = dofile(require("debug").getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/utils.lua")

local M = {}

-- 加载连接池模块
local ConnectionPool = dofile(require("debug").getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/connection_pool.lua")

local function make_request_text(host, path, api_key, payload, keep_alive)
  local connection_header = keep_alive and "keep-alive" or "close"
  return table.concat({
    "POST ", path, " HTTP/1.1\r\n",
    "Host: ", host, "\r\n",
    "Content-Type: application/json\r\n",
    "Authorization: Bearer ", api_key, "\r\n",
    "Content-Length: ", tostring(#payload), "\r\n",
    "Connection: ", connection_header, "\r\n\r\n",
    payload,
  })
end

local function load_tls_module()
  local base = U.script_dir()
  local tls = package.loadlib(base .. "/../TLS/tls.so", "luaopen_tls")
  if not tls then
    return nil, "TLS 模块未编译: 请先在 src/TLS 目录下执行 make"
  end
  return tls()
end

-- 获取当前 worker ID（用于连接池分组）
local function get_worker_id()
  return os.getenv("RLIZX_WORKER_ID") or "default"
end

local function split_header_and_body(buffer)
  local idx = buffer:find("\r\n\r\n", 1, true)
  local sep_len = 4
  if not idx then
    idx = buffer:find("\n\n", 1, true)
    sep_len = 2
  end
  if not idx then
    return nil, nil
  end
  return buffer:sub(1, idx + sep_len - 1), buffer:sub(idx + sep_len)
end

local function parse_chunk_json(line)
  local ok, obj = pcall(U.json_parse, line)
  if not ok or type(obj) ~= "table" then
    return nil, "SSE 数据不是合法 JSON"
  end
  return obj
end

local function ensure_tool_slot(tool_map, idx)
  local slot = tool_map[idx]
  if slot then
    return slot
  end
  slot = {
    id = nil,
    ["function"] = {
      name = "",
      arguments = "",
    },
  }
  tool_map[idx] = slot
  return slot
end

local function stream_write_utf8(content)
  for ch in tostring(content):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    io.stdout:write(ch)
    io.stdout:flush()
  end
end

local function apply_delta_to_state(state, delta)
  if type(delta) ~= "table" then
    return
  end

  local content = delta.content
  if type(content) == "string" and content ~= "" then
    state.content_parts[#state.content_parts + 1] = content
    state.has_content = true
    if not state.stream_prefix_printed then
      io.stdout:write("AI> ")
      state.stream_prefix_printed = true
    end
    stream_write_utf8(content)
  end

  local tool_calls = delta.tool_calls
  if type(tool_calls) == "table" then
    for i, item in ipairs(tool_calls) do
      if type(item) == "table" then
        local idx = item.index
        if type(idx) ~= "number" then
          idx = i
        else
          idx = math.floor(idx) + 1
        end

        local slot = ensure_tool_slot(state.tool_calls_by_index, idx)

        if type(item.id) == "string" and item.id ~= "" then
          slot.id = item.id
        end

        local f = item["function"]
        if type(f) == "table" then
          if type(f.name) == "string" and f.name ~= "" then
            slot["function"].name = slot["function"].name .. f.name
          end
          if type(f.arguments) == "string" and f.arguments ~= "" then
            slot["function"].arguments = slot["function"].arguments .. f.arguments
          end
        end
      end
    end
  end
end

local function finalize_stream_message(state)
  local message = {
    role = "assistant",
    content = table.concat(state.content_parts),
  }

  local keys = {}
  for k, _ in pairs(state.tool_calls_by_index) do
    keys[#keys + 1] = k
  end
  table.sort(keys)

  local calls = {}
  for _, idx in ipairs(keys) do
    local item = state.tool_calls_by_index[idx]
    if type(item) == "table" then
      local f = item["function"] or {}
      local name = tostring(f.name or "")
      if name ~= "" then
        calls[#calls + 1] = {
          id = tostring(item.id or ("tool_call_" .. tostring(idx))),
          name = name,
          arguments = tostring(f.arguments or "{}"),
        }
      end
    end
  end

  if #calls > 0 then
    message.tool_calls = calls
  end

  return message
end

function M.parse_url(url)
  local scheme, rest = url:match("^(https?)://(.+)$")
  if not scheme then
    return nil, nil, nil, "endpoint 必须以 http:// 或 https:// 开头"
  end
  local host, port, path = rest:match("^([^:/]+):?(%d*)(/.*)$")
  if not host then
    host, port = rest:match("^([^:/]+):?(%d*)")
    path = "/"
  end
  port = (port and port ~= "") and tonumber(port) or (scheme == "https" and 443 or 80)
  return scheme, host, port, path
end

function M.http_request(cfg, payload)
  local scheme, host, port, path, perr = M.parse_url(cfg.endpoint)
  if not scheme then
    return nil, perr
  end

  -- 检查是否启用连接池
  local use_pool = cfg.use_connection_pool ~= false
  local worker_id = get_worker_id()
  local conn = nil

  -- 尝试从连接池获取连接
  if use_pool and scheme == "https" then
    conn, perr = ConnectionPool.acquire(worker_id, host, port, {
      scheme = scheme,
      ca_file = cfg.ca_file,
      timeout = cfg.timeout,
      verify_tls = cfg.verify_tls
    })
  end

  -- 如果没有从池中获取到连接，或者不使用连接池，则创建新连接
  local req = make_request_text(host, path, cfg.api_key, payload, conn ~= nil)

  local tls, tls_err = load_tls_module()
  if not tls then
    -- 释放连接（如果已获取）
    if conn then
      ConnectionPool.release(worker_id, host, port, conn)
    end
    return nil, tls_err
  end

  local resp, err

  if conn and conn.tls_handle then
    -- 使用池中的连接
    local ok, result = pcall(tls.request_with_connection, conn.tls_handle, req, cfg.timeout)
    if not ok then
      err = result
      -- 连接可能已失效，关闭它
      ConnectionPool.release(worker_id, host, port, conn)
      conn = nil
    else
      resp = result
    end
  end

  -- 如果池连接失败或不使用连接池，使用传统方式
  if not resp then
    if scheme == "https" then
      resp, err = tls.request(host, port, req, cfg.ca_file, cfg.timeout, cfg.verify_tls)
    else
      resp, err = tls.tcp_request(host, port, req, cfg.timeout)
    end

    if not resp then
      -- 释放连接（如果已获取）
      if conn then
        ConnectionPool.release(worker_id, host, port, conn)
      end
      return nil, err
    end
  end

  -- 释放连接回池
  if conn then
    ConnectionPool.release(worker_id, host, port, conn)
  end

  return resp
end

function M.stream_chat(cfg, payload)
  local scheme, host, port, path, perr = M.parse_url(cfg.endpoint)
  if not scheme then
    return nil, perr
  end

  local req = make_request_text(host, path, cfg.api_key, payload)

  local tls, tls_err = load_tls_module()
  if not tls then
    return nil, tls_err
  end

  local state = {
    raw_buffer = "",
    body_buffer = "",
    in_body = false,
    event_data_lines = {},
    content_parts = {},
    tool_calls_by_index = {},
    finish_reason = nil,
    has_content = false,
  }

  local function dispatch_event_data(data_line)
    if not data_line or data_line == "" then
      return true
    end

    local function dispatch_one(raw)
      local line = tostring(raw or ""):match("^%s*(.-)%s*$")
      if line == "" then
        return true
      end

      if line == "[DONE]" then
        return false
      end

      local obj = parse_chunk_json(line)
      if not obj then
        -- 某些网关会夹杂非 JSON 的 SSE 数据帧，不能因此中断整段流式输出。
        -- 这里选择忽略异常帧，继续读取后续分片。
        return true
      end

      if type(obj.error) == "table" and obj.error.message then
        return nil, tostring(obj.error.message)
      end

      local choices = obj.choices
      if type(choices) ~= "table" or #choices == 0 then
        return true
      end

      local c1 = choices[1]
      if type(c1) ~= "table" then
        return true
      end

      if c1.finish_reason ~= nil then
        state.finish_reason = c1.finish_reason
      end

      local delta = c1.delta
      apply_delta_to_state(state, delta)

      return true
    end

    for part in tostring(data_line):gmatch("[^\n]+") do
      local ok, err = dispatch_one(part)
      if ok ~= true then
        return ok, err
      end
    end

    return true
  end

  local function flush_event_if_ready(line)
    local s = tostring(line or "")
    if not s:match("^%s*$") then
      return true, nil
    end

    if #state.event_data_lines == 0 then
      return true, nil
    end

    local data_line = table.concat(state.event_data_lines, "\n")
    state.event_data_lines = {}

    local ok, err = dispatch_event_data(data_line)
    return ok, err
  end

  local function process_body_lines()
    while true do
      local line_end = state.body_buffer:find("\r\n", 1, true)
      local sep_len = 2
      if not line_end then
        line_end = state.body_buffer:find("\n", 1, true)
        sep_len = 1
      end
      if not line_end then
        break
      end

      local raw_line = state.body_buffer:sub(1, line_end - 1)
      state.body_buffer = state.body_buffer:sub(line_end + sep_len)

      local line = raw_line:gsub("\r$", "")

      if line:sub(1, 5) == "data:" then
        state.event_data_lines[#state.event_data_lines + 1] = line:sub(6):match("^%s*(.-)%s*$")
      end

      local ok, err = flush_event_if_ready(line)
      if ok == false then
        return false, nil
      end
      if ok == nil then
        return nil, err
      end
    end

    return true, nil
  end

  local function on_chunk(chunk)
    if not state.in_body then
      state.raw_buffer = state.raw_buffer .. chunk
      local _, body = split_header_and_body(state.raw_buffer)
      if not body then
        return true
      end
      state.body_buffer = body
      state.raw_buffer = ""
      state.in_body = true
    else
      state.body_buffer = state.body_buffer .. chunk
    end

    local ok, err = process_body_lines()
    if ok == false then
      return false
    end
    if ok == nil then
      state.stream_error = err
      return false
    end

    return true
  end

  local ok, err
  if scheme == "https" then
    ok, err = tls.request_stream(host, port, req, cfg.ca_file, cfg.timeout, cfg.verify_tls, on_chunk)
  else
    ok, err = tls.tcp_request_stream(host, port, req, cfg.timeout, on_chunk)
  end

  if not ok then
    if state.stream_error then
      return nil, state.stream_error
    end
    return nil, err
  end

  local final_ok, final_err = flush_event_if_ready("")
  if final_ok == nil then
    return nil, final_err
  end

  if state.has_content then
    io.stdout:write("\n")
  end

  return finalize_stream_message(state)
end

function M.stream_request(cfg, payload)
  local msg, err = M.stream_chat(cfg, payload)
  if not msg then
    return nil, err
  end
  return tostring(msg.content or "")
end

function M.parse_http_body(resp)
  local body = resp:match("\r\n\r\n(.*)")
  return body or ""
end

function M.parse_response(json)
  local content = json:match('"content"%s*:%s*"(.-)"')
  if content then
    return content:gsub("\\n", "\n"):gsub("\\r", "\r"):gsub("\\t", "\t")
  end
  local err = json:match('"message"%s*:%s*"(.-)"')
  if err then
    return nil, err
  end
  return nil, "无法解析响应"
end

return M