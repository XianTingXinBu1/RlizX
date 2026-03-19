-- RlizX Search Operations

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local M = package.loaded["rlizx.search_ops"]

if not M then
  M = {}

  local U = dofile(get_script_dir() .. "/../Hub/utils.lua")
  local Http = dofile(get_script_dir() .. "/../Hub/http.lua")

  local function shell_quote(s)
    return string.format("%q", tostring(s or ""))
  end

  local function run_capture(cmd)
    local p = io.popen(cmd .. " 2>&1")
    if not p then
      return nil, "命令执行失败"
    end
    local out = p:read("*a") or ""
    p:close()
    return out
  end

  local function http_get_with_fallback(url, timeout)
    local cfg = {
      endpoint = url,
      api_key = "",
      timeout = timeout or 15,
      verify_tls = false,
    }

    local resp, err = Http.http_request(cfg, "")
    if resp then
      local body = Http.parse_http_body(resp)
      if body and body ~= "" then
        return body
      end
    end

    local cmd = table.concat({
      "curl -L --silent --show-error",
      "--max-time", tostring(timeout or 15),
      "--connect-timeout", tostring(timeout or 15),
      shell_quote(url),
    }, " ")

    local out, cerr = run_capture(cmd)
    if not out or out == "" then
      return nil, err or cerr or "请求失败"
    end

    return out
  end

  function M.web_search(args, context)
    local query = args and args.query
    local num_results = tonumber((args and (args.num_results or args.num))) or 10

    if not query or query == "" then
      return { error = "缺少必需参数: query" }
    end

    if num_results < 1 then num_results = 1 end
    if num_results > 30 then num_results = 30 end

    local encoded_query = U.url_encode(query)
    local url = string.format("https://api.duckduckgo.com/?q=%s&format=json&no_html=1&skip_disambig=0", encoded_query)

    local body, err = http_get_with_fallback(url, 10)
    if not body or body == "" then
      return { error = "搜索请求失败: " .. tostring(err or "响应为空") }
    end

    local ok, data = pcall(U.json_parse, body)
    if not ok or type(data) ~= "table" then
      return { error = "无法解析搜索结果" }
    end

    local results = {}

    if type(data.RelatedTopics) == "table" then
      local count = 0
      for _, topic in ipairs(data.RelatedTopics) do
        if count >= num_results then
          break
        end

        if type(topic) == "table" then
          local result = {}

          if type(topic.Text) == "string" then
            result.snippet = topic.Text
          elseif type(topic.FirstURL) == "string" then
            result.snippet = topic.FirstURL
          end

          if type(topic.FirstURL) == "string" then
            result.url = topic.FirstURL
          end

          if type(topic.Result) == "string" then
            local title = topic.Result:match("<a[^>]*>(.-)</a>")
            if title then
              result.title = title:gsub("%b<>", ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
            end
          end

          if type(topic.Icon) == "table" and type(topic.Icon.URL) == "string" then
            result.icon = topic.Icon.URL
          end

          if result.snippet or result.url then
            results[#results + 1] = result
            count = count + 1
          end
        end
      end
    end

    if type(data.Abstract) == "string" and data.Abstract ~= "" then
      table.insert(results, 1, {
        title = data.Heading or "概述",
        snippet = data.Abstract,
        url = data.AbstractURL or data.AbstractSource or "",
        is_abstract = true,
      })
    end

    if #results == 0 then
      return { result = "未找到相关结果" }
    end

    return { result = results }
  end

  function M.web_fetch(args, context)
    local url = args and args.url

    if not url or url == "" then
      return { error = "缺少必需参数: url" }
    end

    if not url:match("^https?://") then
      return { error = "URL 必须以 http:// 或 https:// 开头" }
    end

    local body, err = http_get_with_fallback(url, 15)
    if not body or body == "" then
      return { error = "网页获取失败: " .. tostring(err or "网页内容为空") }
    end

    local content = body:gsub("<script[^>]*>.-</script>", "")
                      :gsub("<style[^>]*>.-</style>", "")
                      :gsub("<noscript[^>]*>.-</noscript>", "")
                      :gsub("<[^>]+>", "")
                      :gsub("&nbsp;", " ")
                      :gsub("&lt;", "<")
                      :gsub("&gt;", ">")
                      :gsub("&amp;", "&")
                      :gsub("&quot;", '"')
                      :gsub("&#39;", "'")
                      :gsub("%s+", " ")
                      :match("^%s*(.-)%s*$")

    if not content or content == "" then
      return { error = "无法提取网页内容" }
    end

    return { result = content }
  end

  package.loaded["rlizx.search_ops"] = M
end

return M