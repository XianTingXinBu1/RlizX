local U = dofile(require("debug").getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/utils.lua")
local H = dofile(require("debug").getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/http.lua")
local Mem = dofile(require("debug").getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/memory.lua")

local M = {}

local function utf8_chars(s)
  local t = {}
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    t[#t + 1] = ch
  end
  return t
end

local function split_text_chunks(text, max_len, overlap)
  local chars = utf8_chars(text or "")
  if #chars == 0 then return {} end

  local chunks = {}
  local i = 1
  max_len = max_len or 400
  overlap = overlap or 20

  while i <= #chars do
    local j = math.min(i + max_len - 1, #chars)
    local chunk = table.concat(chars, "", i, j)
    chunks[#chunks + 1] = chunk
    if j == #chars then break end
    i = math.max(j - overlap + 1, i + 1)
  end

  return chunks
end

local function split_plain(s, sep)
  if not s or s == "" then return {} end
  local t = {}
  local start = 1
  while true do
    local i = s:find(sep, start, true)
    if not i then
      t[#t + 1] = s:sub(start)
      break
    end
    t[#t + 1] = s:sub(start, i - 1)
    start = i + #sep
  end
  if #t == 1 and t[1] == "" then return {} end
  return t
end

local function join_vectors(vectors)
  local items = {}
  for _, vec in ipairs(vectors or {}) do
    items[#items + 1] = table.concat(vec, ",")
  end
  return table.concat(items, ";")
end

local function parse_vectors(raw)
  local list = {}
  local rows = split_plain(raw, ";")
  for _, row in ipairs(rows) do
    local vec = {}
    for num in row:gmatch("[-%d%.eE]+") do
      vec[#vec + 1] = tonumber(num)
    end
    if #vec > 0 then
      list[#list + 1] = vec
    end
  end
  return list
end

local function build_vector_payload(model, inputs)
  local parts = {}
  for _, input in ipairs(inputs or {}) do
    parts[#parts + 1] = string.format('"%s"', U.json_escape(tostring(input)))
  end
  return string.format('{"model":"%s","input":[%s]}', U.json_escape(model or ""), table.concat(parts, ","))
end

local function parse_embeddings(body)
  local err = body:match('"message"%s*:%s*"(.-)"')
  if err and err ~= "" then
    return nil, err
  end

  local vectors = {}
  for embed in body:gmatch('"embedding"%s*:%s*%[(.-)%]') do
    local vec = {}
    for num in embed:gmatch("[-%d%.eE]+") do
      vec[#vec + 1] = tonumber(num)
    end
    if #vec > 0 then
      vectors[#vectors + 1] = vec
    end
  end

  if #vectors == 0 then
    return nil, "无法解析 embeddings"
  end
  return vectors
end

local function embed_inputs(cfg, inputs)
  if not cfg or not cfg.endpoint or cfg.endpoint == "" then
    return nil, "vector endpoint 未配置"
  end
  if not cfg.api_key or cfg.api_key == "" then
    return nil, "vector api_key 未配置"
  end
  if not cfg.model or cfg.model == "" then
    return nil, "vector model 未配置"
  end
  if not inputs or #inputs == 0 then
    return nil, "inputs 为空"
  end

  local payload = build_vector_payload(cfg.model, inputs)
  local resp, err = H.http_request(cfg, payload)
  if not resp then
    return nil, err
  end
  local body = H.parse_http_body(resp)
  return parse_embeddings(body)
end

function M.ensure_longterm_vectors(cfg, base, agent_name, list)
  if not list or #list == 0 then return list, false end
  if not cfg or not cfg.vector or not cfg.vector.endpoint or cfg.vector.endpoint == "" then
    return list, false
  end

  local changed = false
  for _, entry in ipairs(list) do
    if entry.text and entry.text ~= "" and (entry.segments == "" or entry.vectors == "") then
      local segments = split_text_chunks(entry.text, 400, 20)
      local vectors, err = embed_inputs(cfg.vector, segments)
      if vectors then
        entry.segments = table.concat(segments, "\n---\n")
        entry.vectors = join_vectors(vectors)
        changed = true
      else
        io.stdout:write("[Vector Warning] " .. tostring(err) .. "\n")
      end
    end
  end

  if changed then
    Mem.save_longterm_list(base, agent_name, list)
  end
  return list, changed
end

local function cosine_similarity(a, b)
  if not a or not b then return 0 end
  local n = math.min(#a, #b)
  if n == 0 then return 0 end
  local dot, na, nb = 0, 0, 0
  for i = 1, n do
    local x = a[i] or 0
    local y = b[i] or 0
    dot = dot + x * y
    na = na + x * x
    nb = nb + y * y
  end
  if na == 0 or nb == 0 then return 0 end
  return dot / (math.sqrt(na) * math.sqrt(nb))
end

local function build_keywords(text)
  local set = {}
  for w in tostring(text):lower():gmatch("[%w_]+") do
    set[w] = true
  end
  for ch in tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if #ch > 1 then
      set[ch] = true
    end
  end
  return set
end

local function keyword_score(keywords, text)
  local total = 0
  local hit = 0
  for k in pairs(keywords) do
    total = total + 1
    if tostring(text):find(k, 1, true) then
      hit = hit + 1
    end
  end
  if total == 0 then return 0 end
  return (hit / total) * 2
end

local function vector_score(input_vecs, entry)
  if not input_vecs or #input_vecs == 0 then return 0 end
  if not entry.vectors or entry.vectors == "" then return 0 end

  local entry_vecs = parse_vectors(entry.vectors)
  if #entry_vecs == 0 then return 0 end

  local best = 0
  for _, iv in ipairs(input_vecs) do
    for _, ev in ipairs(entry_vecs) do
      local sim = cosine_similarity(iv, ev)
      if sim > best then best = sim end
    end
  end
  return best * 7
end

local function time_score(rank, total)
  if total <= 1 then return 1 end
  return (total - rank) / (total - 1)
end

function M.get_longterm_hits(cfg, base, agent_name, input)
  local list = Mem.read_longterm_list(base, agent_name)
  if #list == 0 then return {} end

  list = M.ensure_longterm_vectors(cfg, base, agent_name, list)

  local keywords = build_keywords(input)
  local input_vecs = nil
  if cfg and cfg.vector and cfg.vector.endpoint and cfg.vector.endpoint ~= "" then
    local input_segments = split_text_chunks(tostring(input or ""), 400, 20)
    local vectors, err = embed_inputs(cfg.vector, input_segments)
    if vectors then
      input_vecs = vectors
    else
      io.stdout:write("[Vector Warning] " .. tostring(err) .. "\n")
    end
  end

  table.sort(list, function(a, b)
    return (a.ts or 0) > (b.ts or 0)
  end)

  local scored = {}
  local total = #list
  for i, entry in ipairs(list) do
    local score = 0
    score = score + vector_score(input_vecs, entry)
    score = score + keyword_score(keywords, entry.text or "")
    score = score + time_score(i, total)
    scored[#scored + 1] = { entry = entry, score = score }
  end

  table.sort(scored, function(a, b)
    if a.score == b.score then
      return (a.entry.ts or 0) > (b.entry.ts or 0)
    end
    return a.score > b.score
  end)

  local results = {}
  for i = 1, math.min(5, #scored) do
    results[#results + 1] = scored[i].entry
  end

  return results
end

return M
