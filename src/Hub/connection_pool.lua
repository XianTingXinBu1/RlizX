-- RlizX Connection Pool Manager
-- 管理 TLS 连接池，实现连接复用以提升性能

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local M = package.loaded["rlizx.connection_pool"]

if not M then
  M = {}

  local U = dofile(get_script_dir() .. "/utils.lua")

  -- 连接池配置
  local POOL_CONFIG = {
    max_connections_per_host = 5,   -- 每个主机最大连接数
    connection_ttl = 300,           -- 连接最大存活时间（秒）
    idle_timeout = 60,              -- 空闲超时（秒）
    max_pool_size = 50,             -- 每个Worker最大连接池大小
    cleanup_interval = 60,          -- 清理间隔（秒）
  }

  -- 全局连接池（按 worker_id 分组）
  M.pools = {}

  -- TLS 模块缓存
  local tls_module = nil

  -- 加载 TLS 模块
  local function load_tls()
    if tls_module then
      return tls_module
    end

    local base = get_script_dir()
    local tls = package.loadlib(base .. "/../TLS/tls.so", "luaopen_tls")
    if not tls then
      return nil, "TLS 模块未编译: 请先在 src/TLS 目录下执行 make"
    end

    tls_module = tls()
    return tls_module
  end

  -- 创建新的 TLS 连接
  local function create_connection(host, port, cfg)
    local tls, err = load_tls()
    if not tls then
      return nil, err
    end

    local conn = {
      host = host,
      port = port,
      scheme = cfg.scheme or "https",
      created_at = os.time(),
      last_used = os.time(),
      in_use = false,
      tls_handle = nil,
      cfg = {
        ca_file = cfg.ca_file,
        timeout = cfg.timeout,
        verify_tls = cfg.verify_tls
      }
    }

    -- 尝试建立连接
    local ok, handle = pcall(tls.create_connection, host, port, conn.cfg)
    if not ok or not handle then
      return nil, handle or "连接创建失败"
    end

    conn.tls_handle = handle
    return conn
  }

  -- 关闭连接
  local function close_connection(conn)
    if conn and conn.tls_handle then
      local tls, _ = load_tls()
      if tls and tls.close_connection then
        pcall(tls.close_connection, conn.tls_handle)
      end
      conn.tls_handle = nil
    end
  end

  -- 获取或创建连接池
  function M.get_pool(worker_id)
    if not worker_id or worker_id == "" then
      worker_id = "default"
    end

    if not M.pools[worker_id] then
      M.pools[worker_id] = {
        connections = {},      -- host:port -> list of connections
        stats = {
          hits = 0,
          misses = 0,
          created = 0,
          reused = 0,
          closed = 0,
          errors = 0
        },
        last_cleanup = os.time(),
        total_connections = 0
      }
    end

    return M.pools[worker_id]
  end

  -- 生成连接键
  local function make_connection_key(host, port)
    return string.format("%s:%d", host or "", port or 443)
  end

  -- 查找可用连接
  local function find_available_connection(pool, key)
    local conns = pool.connections[key]
    if not conns or #conns == 0 then
      return nil
    end

    local now = os.time()

    -- 从后往前查找，优先使用最近使用的连接
    for i = #conns, 1, -1 do
      local conn = conns[i]

      -- 检查连接是否可用
      if not conn.in_use then
        -- 检查是否过期
        if (now - conn.last_used) <= POOL_CONFIG.idle_timeout and
           (now - conn.created_at) <= POOL_CONFIG.connection_ttl then
          -- 检查连接是否仍然有效
          if conn.tls_handle then
            return conn
          end
        end

        -- 连接过期或无效，移除
        close_connection(conn)
        table.remove(conns, i)
        pool.stats.closed = pool.stats.closed + 1
        pool.total_connections = pool.total_connections - 1
      end
    end

    return nil
  end

  -- 检查是否可以创建新连接
  local function can_create_connection(pool)
    -- 检查总连接数
    if pool.total_connections >= POOL_CONFIG.max_pool_size then
      return false, "连接池已满"
    end

    return true
  end

  -- 获取连接
  function M.acquire(worker_id, host, port, cfg)
    local pool = M.get_pool(worker_id)
    local key = make_connection_key(host, port)

    -- 确保有该主机的连接列表
    if not pool.connections[key] then
      pool.connections[key] = {}
    end

    -- 尝试从池中获取可用连接
    local conn = find_available_connection(pool, key)
    if conn then
      pool.stats.hits = pool.stats.hits + 1
      pool.stats.reused = pool.stats.reused + 1
      conn.in_use = true
      conn.last_used = os.time()
      return conn
    end

    -- 检查是否可以创建新连接
    local can_create, err = can_create_connection(pool)
    if not can_create then
      -- 尝试清理过期连接后重试
      M.cleanup(worker_id)
      can_create, err = can_create_connection(pool)
      if not can_create then
        return nil, err
      end
    end

    -- 创建新连接
    pool.stats.misses = pool.stats.misses + 1

    local new_conn, create_err = create_connection(host, port, cfg)
    if not new_conn then
      pool.stats.errors = pool.stats.errors + 1
      return nil, create_err
    end

    new_conn.in_use = true
    new_conn.created_at = os.time()
    new_conn.last_used = os.time()

    table.insert(pool.connections[key], new_conn)
    pool.stats.created = pool.stats.created + 1
    pool.total_connections = pool.total_connections + 1

    return new_conn
  end

  -- 释放连接
  function M.release(worker_id, host, port, conn)
    if not conn then
      return
    end

    local pool = M.get_pool(worker_id)
    local key = make_connection_key(host, port)

    conn.in_use = false
    conn.last_used = os.time()

    -- 检查连接是否需要关闭
    local now = os.time()
    if (now - conn.last_used) > POOL_CONFIG.idle_timeout or
       (now - conn.created_at) > POOL_CONFIG.connection_ttl or
       not conn.tls_handle then
      -- 关闭连接
      close_connection(conn)

      -- 从池中移除
      local conns = pool.connections[key]
      if conns then
        for i, c in ipairs(conns) do
          if c == conn then
            table.remove(conns, i)
            pool.stats.closed = pool.stats.closed + 1
            pool.total_connections = pool.total_connections - 1
            break
          end
        end
      end
    end
  end

  -- 清理过期连接
  function M.cleanup(worker_id)
    local pool = M.get_pool(worker_id)
    local now = os.time()

    -- 检查是否需要清理
    if (now - pool.last_cleanup) < POOL_CONFIG.cleanup_interval then
      return
    end

    local cleaned = 0

    for key, conns in pairs(pool.connections) do
      for i = #conns, 1, -1 do
        local conn = conns[i]

        if not conn.in_use then
          -- 检查是否过期
          if (now - conn.last_used) > POOL_CONFIG.idle_timeout or
             (now - conn.created_at) > POOL_CONFIG.connection_ttl or
             not conn.tls_handle then

            close_connection(conn)
            table.remove(conns, i)
            pool.stats.closed = pool.stats.closed + 1
            pool.total_connections = pool.total_connections - 1
            cleaned = cleaned + 1
          end
        end
      end
    end

    pool.last_cleanup = now

    return cleaned
  end

  -- 清空连接池
  function M.clear(worker_id)
    local pool = M.get_pool(worker_id)

    for key, conns in pairs(pool.connections) do
      for _, conn in ipairs(conns) do
        close_connection(conn)
      end
      pool.connections[key] = {}
    end

    pool.total_connections = 0
    pool.stats.closed = pool.stats.closed + pool.total_connections
  end

  -- 获取连接池统计信息
  function M.get_stats(worker_id)
    local pool = M.get_pool(worker_id)

    local total_connections = 0
    local in_use_connections = 0
    local idle_connections = 0

    for _, conns in pairs(pool.connections) do
      for _, conn in ipairs(conns) do
        total_connections = total_connections + 1
        if conn.in_use then
          in_use_connections = in_use_connections + 1
        else
          idle_connections = idle_connections + 1
        end
      end
    end

    local stats = {
      total_connections = total_connections,
      in_use_connections = in_use_connections,
      idle_connections = idle_connections,
      host_count = 0,
      pool_utilization = 0,
      cache_hit_rate = 0,
      raw_stats = {}
    }

    -- 计算主机数量
    for _, conns in pairs(pool.connections) do
      if #conns > 0 then
        stats.host_count = stats.host_count + 1
      end
    end

    -- 计算池利用率
    if POOL_CONFIG.max_pool_size > 0 then
      stats.pool_utilization = total_connections / POOL_CONFIG.max_pool_size
    end

    -- 计算缓存命中率
    local total_requests = pool.stats.hits + pool.stats.misses
    if total_requests > 0 then
      stats.cache_hit_rate = pool.stats.hits / total_requests
    end

    -- 原始统计信息
    stats.raw_stats = {
      hits = pool.stats.hits,
      misses = pool.stats.misses,
      created = pool.stats.created,
      reused = pool.stats.reused,
      closed = pool.stats.closed,
      errors = pool.stats.errors
    }

    return stats
  end

  -- 获取配置
  function M.get_config()
    return {
      max_connections_per_host = POOL_CONFIG.max_connections_per_host,
      connection_ttl = POOL_CONFIG.connection_ttl,
      idle_timeout = POOL_CONFIG.idle_timeout,
      max_pool_size = POOL_CONFIG.max_pool_size,
      cleanup_interval = POOL_CONFIG.cleanup_interval
    }
  end

  -- 更新配置
  function M.update_config(new_config)
    if type(new_config) ~= "table" then
      return false, "配置必须是表格"
    end

    if new_config.max_connections_per_host then
      POOL_CONFIG.max_connections_per_host = new_config.max_connections_per_host
    end

    if new_config.connection_ttl then
      POOL_CONFIG.connection_ttl = new_config.connection_ttl
    end

    if new_config.idle_timeout then
      POOL_CONFIG.idle_timeout = new_config.idle_timeout
    end

    if new_config.max_pool_size then
      POOL_CONFIG.max_pool_size = new_config.max_pool_size
    end

    if new_config.cleanup_interval then
      POOL_CONFIG.cleanup_interval = new_config.cleanup_interval
    end

    return true
  end

  package.loaded["rlizx.connection_pool"] = M
end

return M