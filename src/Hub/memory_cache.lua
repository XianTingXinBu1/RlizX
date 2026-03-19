-- RlizX Memory Cache System
-- 实现高效的内存缓存，支持 LRU 和 TTL

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local M = package.loaded["rlizx.memory_cache"]

if not M then
  M = {}

  -- 缓存配置
  local CACHE_CONFIG = {
    max_size = 1000,        -- 最大缓存条目数
    default_ttl = 300,      -- 默认过期时间（秒）
    cleanup_interval = 300, -- 清理间隔（秒）
    stats_enabled = true
  }

  -- 缓存存储
  local cache = {}

  -- LRU 双向链表
  local lru_head = nil
  local lru_tail = nil

  -- 统计信息
  local stats = {
    hits = 0,
    misses = 0,
    evictions = 0,
    sets = 0,
    deletes = 0,
    cleanups = 0
  }

  -- LRU 节点
  local function lru_node(key)
    return {
      key = key,
      prev = nil,
      next = nil
    }
  end

  -- 移动节点到链表头部（最近使用）
  local function lru_move_to_front(key)
    local entry = cache[key]
    if not entry or not entry.lru_node then
      return
    end

    local node = entry.lru_node

    -- 如果已经在头部，无需移动
    if node == lru_head then
      return
    end

    -- 从当前位置移除
    if node.prev then
      node.prev.next = node.next
    end
    if node.next then
      node.next.prev = node.prev
    end

    -- 如果是尾部节点，更新尾部
    if node == lru_tail then
      lru_tail = node.prev
    end

    -- 移动到头部
    node.prev = nil
    node.next = lru_head

    if lru_head then
      lru_head.prev = node
    end

    lru_head = node

    -- 如果是第一个节点，也是尾部
    if not lru_tail then
      lru_tail = node
    end
  end

  -- 从链表中移除节点
  local function lru_remove(node)
    if not node then
      return
    end

    if node.prev then
      node.prev.next = node.next
    end

    if node.next then
      node.next.prev = node.prev
    end

    if node == lru_head then
      lru_head = node.next
    end

    if node == lru_tail then
      lru_tail = node.prev
    end
  end

  -- 淘汰最少使用的条目
  local function evict_lru()
    if not lru_tail then
      return nil
    end

    local key = lru_tail.key
    local entry = cache[key]

    if entry then
      -- 从链表移除
      lru_remove(lru_tail)

      -- 从缓存移除
      cache[key] = nil

      -- 更新统计
      stats.evictions = stats.evictions + 1

      return key
    end

    return nil
  end

  -- 检查是否需要淘汰
  local function should_evict()
    local count = 0
    for _ in pairs(cache) do
      count = count + 1
    end
    return count >= CACHE_CONFIG.max_size
  end

  -- 检查条目是否过期
  local function is_expired(entry)
    if not entry.expires_at then
      return false
    end
    return os.time() > entry.expires_at
  end

  -- 获取缓存值
  function M.get(key)
    if not key or key == "" then
      return nil
    end

    local entry = cache[key]

    if not entry then
      if CACHE_CONFIG.stats_enabled then
        stats.misses = stats.misses + 1
      end
      return nil
    end

    -- 检查是否过期
    if is_expired(entry) then
      M.delete(key)
      if CACHE_CONFIG.stats_enabled then
        stats.misses = stats.misses + 1
      end
      return nil
    end

    -- 更新访问时间和 LRU
    entry.last_accessed = os.time()
    lru_move_to_front(key)

    if CACHE_CONFIG.stats_enabled then
      stats.hits = stats.hits + 1
    end

    return entry.value
  end

  -- 设置缓存值
  function M.set(key, value, ttl)
    if not key or key == "" then
      return false, "无效的键"
    end

    ttl = ttl or CACHE_CONFIG.default_ttl

    -- 如果键已存在，先删除
    if cache[key] then
      M.delete(key)
    end

    -- 检查是否需要淘汰
    while should_evict() do
      evict_lru()
    end

    -- 创建 LRU 节点
    local node = lru_node(key)

    -- 将节点添加到头部
    node.next = lru_head
    if lru_head then
      lru_head.prev = node
    end
    lru_head = node

    if not lru_tail then
      lru_tail = node
    end

    -- 创建缓存条目
    cache[key] = {
      value = value,
      created_at = os.time(),
      last_accessed = os.time(),
      expires_at = os.time() + ttl,
      ttl = ttl,
      lru_node = node
    }

    if CACHE_CONFIG.stats_enabled then
      stats.sets = stats.sets + 1
    end

    return true
  end

  -- 获取或计算缓存值
  function M.get_or_compute(key, compute_fn, ttl)
    if not key or key == "" then
      return nil, "无效的键"
    end

    if type(compute_fn) ~= "function" then
      return nil, "compute_fn 必须是函数"
    end

    local cached = M.get(key)
    if cached ~= nil then
      return cached
    end

    local ok, value = pcall(compute_fn)
    if not ok then
      return nil, "计算失败: " .. tostring(value)
    end

    M.set(key, value, ttl)
    return value
  end

  -- 删除缓存值
  function M.delete(key)
    if not key or key == "" then
      return false
    end

    local entry = cache[key]
    if entry then
      -- 从链表移除
      if entry.lru_node then
        lru_remove(entry.lru_node)
      end

      -- 从缓存移除
      cache[key] = nil

      if CACHE_CONFIG.stats_enabled then
        stats.deletes = stats.deletes + 1
      end

      return true
    end

    return false
  end

  -- 清空缓存
  function M.clear()
    cache = {}
    lru_head = nil
    lru_tail = nil

    if CACHE_CONFIG.stats_enabled then
      stats.hits = 0
      stats.misses = 0
      stats.evictions = 0
      stats.sets = 0
      stats.deletes = 0
    end

    return true
  end

  -- 清理过期条目
  function M.cleanup()
    local now = os.time()
    local cleaned = 0

    for key, entry in pairs(cache) do
      if is_expired(entry) then
        M.delete(key)
        cleaned = cleaned + 1
      end
    end

    if CACHE_CONFIG.stats_enabled then
      stats.cleanups = stats.cleanups + 1
    end

    return cleaned
  end

  -- 获取缓存大小
  function M.size()
    local count = 0
    for _ in pairs(cache) do
      count = count + 1
    end
    return count
  end

  -- 检查键是否存在
  function M.has(key)
    if not key or key == "" then
      return false
    end

    local entry = cache[key]
    if not entry then
      return false
    end

    if is_expired(entry) then
      M.delete(key)
      return false
    end

    return true
  end

  -- 获取缓存命中率
  function M.hit_rate()
    if not CACHE_CONFIG.stats_enabled then
      return nil, "统计未启用"
    end

    local total = stats.hits + stats.misses
    if total == 0 then
      return 0
    end

    return stats.hits / total
  end

  -- 获取统计信息
  function M.get_stats()
    if not CACHE_CONFIG.stats_enabled then
      return nil, "统计未启用"
    end

    local total = stats.hits + stats.misses
    local hit_rate = 0
    if total > 0 then
      hit_rate = stats.hits / total
    end

    return {
      size = M.size(),
      max_size = CACHE_CONFIG.max_size,
      hits = stats.hits,
      misses = stats.misses,
      evictions = stats.evictions,
      sets = stats.sets,
      deletes = stats.deletes,
      cleanups = stats.cleanups,
      hit_rate = hit_rate,
      utilization = M.size() / CACHE_CONFIG.max_size
    }
  end

  -- 获取配置
  function M.get_config()
    return {
      max_size = CACHE_CONFIG.max_size,
      default_ttl = CACHE_CONFIG.default_ttl,
      cleanup_interval = CACHE_CONFIG.cleanup_interval,
      stats_enabled = CACHE_CONFIG.stats_enabled
    }
  end

  -- 更新配置
  function M.update_config(new_config)
    if type(new_config) ~= "table" then
      return false, "配置必须是表格"
    end

    if new_config.max_size then
      CACHE_CONFIG.max_size = new_config.max_size
      -- 如果新大小小于当前大小，需要淘汰
      while should_evict() do
        evict_lru()
      end
    end

    if new_config.default_ttl then
      CACHE_CONFIG.default_ttl = new_config.default_ttl
    end

    if new_config.cleanup_interval then
      CACHE_CONFIG.cleanup_interval = new_config.cleanup_interval
    end

    if new_config.stats_enabled ~= nil then
      CACHE_CONFIG.stats_enabled = new_config.stats_enabled
    end

    return true
  end

  -- 批量获取
  function M.get_multi(keys)
    local results = {}
    for _, key in ipairs(keys) do
      results[key] = M.get(key)
    end
    return results
  end

  -- 批量设置
  function M.set_multi(items, ttl)
    for key, value in pairs(items) do
      M.set(key, value, ttl)
    end
    return true
  end

  -- 获取所有键
  function M.keys()
    local keys = {}
    for key, entry in pairs(cache) do
      if not is_expired(entry) then
        keys[#keys + 1] = key
      end
    end
    return keys
  end

  package.loaded["rlizx.memory_cache"] = M
end

return M