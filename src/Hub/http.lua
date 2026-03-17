local U = dofile(require("debug").getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/utils.lua")

local M = {}

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

  local req = table.concat({
    "POST ", path, " HTTP/1.1\r\n",
    "Host: ", host, "\r\n",
    "Content-Type: application/json\r\n",
    "Authorization: Bearer ", cfg.api_key, "\r\n",
    "Content-Length: ", tostring(#payload), "\r\n",
    "Connection: close\r\n\r\n",
    payload
  })

  local base = U.script_dir()
  local tls = package.loadlib(base .. "/../TLS/tls.so", "luaopen_tls")
  if not tls then
    return nil, "TLS 模块未编译: 请先在 src/TLS 目录下执行 make"
  end
  tls = tls()

  if scheme == "https" then
    local resp, err = tls.request(host, port, req, cfg.ca_file, cfg.timeout, cfg.verify_tls)
    if not resp then
      return nil, err
    end
    return resp
  end

  local resp, err = tls.tcp_request(host, port, req, cfg.timeout)
  if not resp then
    return nil, err
  end
  return resp
end

function M.stream_request(cfg, payload)
  local scheme, host, port, path, perr = M.parse_url(cfg.endpoint)
  if not scheme then
    return nil, perr
  end

  local req = table.concat({
    "POST ", path, " HTTP/1.1\r\n",
    "Host: ", host, "\r\n",
    "Content-Type: application/json\r\n",
    "Authorization: Bearer ", cfg.api_key, "\r\n",
    "Content-Length: ", tostring(#payload), "\r\n",
    "Connection: close\r\n\r\n",
    payload
  })

  local base = U.script_dir()
  local tls = package.loadlib(base .. "/../TLS/tls.so", "luaopen_tls")
  if not tls then
    return nil, "TLS 模块未编译: 请先在 src/TLS 目录下执行 make"
  end
  tls = tls()

  local buffer = ""
  local in_body = false

  local function on_chunk(chunk)
    buffer = buffer .. chunk
    if not in_body then
      local idx = buffer:find("\r\n\r\n", 1, true)
      if not idx then
        return true
      end
      buffer = buffer:sub(idx + 4)
      in_body = true
    end

    while true do
      local s, e, line = buffer:find("data:%s*(.-)\r\n")
      if not s then
        break
      end
      buffer = buffer:sub(e + 1)
      if line == "[DONE]" then
        return false
      end
      local delta = line:match('"delta"%s*:%s*%{.-"content"%s*:%s*"(.-)"')
      if delta then
        local text = delta:gsub("\\n", "\n"):gsub("\\r", "\r"):gsub("\\t", "\t")
        text = text:gsub("\\u0000", ""):gsub("%z", "")
        io.stdout:write(text)
        io.stdout:flush()
      end
    end

    return true
  end

  if scheme == "https" then
    local ok, err = tls.request_stream(host, port, req, cfg.ca_file, cfg.timeout, cfg.verify_tls, on_chunk)
    if not ok then
      return nil, err
    end
  else
    local ok, err = tls.tcp_request_stream(host, port, req, cfg.timeout, on_chunk)
    if not ok then
      return nil, err
    end
  end

  io.stdout:write("\n")
  return ""
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
