#include <lua.h>
#include <lauxlib.h>

#include <stdio.h>
#include <string.h>

#include <mbedtls/net_sockets.h>
#include <mbedtls/ssl.h>
#include <mbedtls/ctr_drbg.h>
#include <mbedtls/entropy.h>
#include <mbedtls/error.h>
#include <mbedtls/x509_crt.h>

static void push_mbedtls_error(lua_State *L, const char *prefix, int err) {
    char buf[256];
    mbedtls_strerror(err, buf, sizeof(buf));
    lua_pushnil(L);
    lua_pushfstring(L, "%s: %s", prefix, buf);
}

static int l_request(lua_State *L) {
    const char *host = luaL_checkstring(L, 1);
    int port = luaL_optinteger(L, 2, 443);
    size_t req_len = 0;
    const char *req = luaL_checklstring(L, 3, &req_len);
    const char *ca_file = luaL_optstring(L, 4, NULL);
    int timeout = luaL_optinteger(L, 5, 60);
    int verify = lua_isnoneornil(L, 6) ? 1 : lua_toboolean(L, 6);

    mbedtls_net_context server_fd;
    mbedtls_ssl_context ssl;
    mbedtls_ssl_config conf;
    mbedtls_x509_crt cacert;
    mbedtls_ctr_drbg_context ctr_drbg;
    mbedtls_entropy_context entropy;

    mbedtls_net_init(&server_fd);
    mbedtls_ssl_init(&ssl);
    mbedtls_ssl_config_init(&conf);
    mbedtls_x509_crt_init(&cacert);
    mbedtls_ctr_drbg_init(&ctr_drbg);
    mbedtls_entropy_init(&entropy);

    const char *pers = "rlizx_tls";
    int ret = mbedtls_ctr_drbg_seed(&ctr_drbg, mbedtls_entropy_func, &entropy,
                                   (const unsigned char *)pers, strlen(pers));
    if (ret != 0) {
        push_mbedtls_error(L, "DRBG seed failed", ret);
        goto cleanup;
    }

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", port);
    ret = mbedtls_net_connect(&server_fd, host, port_str, MBEDTLS_NET_PROTO_TCP);
    if (ret != 0) {
        push_mbedtls_error(L, "TCP connect failed", ret);
        goto cleanup;
    }

    if (verify) {
        if (!ca_file || ca_file[0] == '\0') {
            lua_pushnil(L);
            lua_pushstring(L, "CA file required for verification");
            goto cleanup;
        }
        ret = mbedtls_x509_crt_parse_file(&cacert, ca_file);
        if (ret < 0) {
            push_mbedtls_error(L, "CA parse failed", ret);
            goto cleanup;
        }
    }

    ret = mbedtls_ssl_config_defaults(&conf,
                                      MBEDTLS_SSL_IS_CLIENT,
                                      MBEDTLS_SSL_TRANSPORT_STREAM,
                                      MBEDTLS_SSL_PRESET_DEFAULT);
    if (ret != 0) {
        push_mbedtls_error(L, "SSL config failed", ret);
        goto cleanup;
    }

    mbedtls_ssl_conf_rng(&conf, mbedtls_ctr_drbg_random, &ctr_drbg);
    mbedtls_ssl_conf_read_timeout(&conf, timeout * 1000);

    if (verify) {
        mbedtls_ssl_conf_authmode(&conf, MBEDTLS_SSL_VERIFY_REQUIRED);
        mbedtls_ssl_conf_ca_chain(&conf, &cacert, NULL);
    } else {
        mbedtls_ssl_conf_authmode(&conf, MBEDTLS_SSL_VERIFY_NONE);
    }

    ret = mbedtls_ssl_setup(&ssl, &conf);
    if (ret != 0) {
        push_mbedtls_error(L, "SSL setup failed", ret);
        goto cleanup;
    }

    ret = mbedtls_ssl_set_hostname(&ssl, host);
    if (ret != 0) {
        push_mbedtls_error(L, "SNI set failed", ret);
        goto cleanup;
    }

    mbedtls_ssl_set_bio(&ssl, &server_fd, mbedtls_net_send, mbedtls_net_recv, mbedtls_net_recv_timeout);

    while ((ret = mbedtls_ssl_handshake(&ssl)) != 0) {
        if (ret != MBEDTLS_ERR_SSL_WANT_READ && ret != MBEDTLS_ERR_SSL_WANT_WRITE) {
            push_mbedtls_error(L, "TLS handshake failed", ret);
            goto cleanup;
        }
    }

    size_t written = 0;
    while (written < req_len) {
        ret = mbedtls_ssl_write(&ssl, (const unsigned char *)req + written, req_len - written);
        if (ret > 0) {
            written += (size_t)ret;
            continue;
        }
        if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) {
            continue;
        }
        push_mbedtls_error(L, "TLS write failed", ret);
        goto cleanup;
    }

    luaL_Buffer b;
    luaL_buffinit(L, &b);
    unsigned char buf[4096];
    while (1) {
        ret = mbedtls_ssl_read(&ssl, buf, sizeof(buf));
        if (ret > 0) {
            luaL_addlstring(&b, (const char *)buf, ret);
            continue;
        }
        if (ret == 0) {
            break;
        }
        if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) {
            continue;
        }
        push_mbedtls_error(L, "TLS read failed", ret);
        goto cleanup;
    }

    mbedtls_ssl_close_notify(&ssl);
    luaL_pushresult(&b);

    mbedtls_net_free(&server_fd);
    mbedtls_ssl_free(&ssl);
    mbedtls_ssl_config_free(&conf);
    mbedtls_x509_crt_free(&cacert);
    mbedtls_ctr_drbg_free(&ctr_drbg);
    mbedtls_entropy_free(&entropy);
    return 1;

cleanup:
    mbedtls_net_free(&server_fd);
    mbedtls_ssl_free(&ssl);
    mbedtls_ssl_config_free(&conf);
    mbedtls_x509_crt_free(&cacert);
    mbedtls_ctr_drbg_free(&ctr_drbg);
    mbedtls_entropy_free(&entropy);
    return 2;
}

static int l_tcp_request(lua_State *L) {
    const char *host = luaL_checkstring(L, 1);
    int port = luaL_optinteger(L, 2, 80);
    size_t req_len = 0;
    const char *req = luaL_checklstring(L, 3, &req_len);
    int timeout = luaL_optinteger(L, 4, 60);

    mbedtls_net_context server_fd;
    mbedtls_net_init(&server_fd);

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", port);
    int ret = mbedtls_net_connect(&server_fd, host, port_str, MBEDTLS_NET_PROTO_TCP);
    if (ret != 0) {
        push_mbedtls_error(L, "TCP connect failed", ret);
        mbedtls_net_free(&server_fd);
        return 2;
    }

    size_t written = 0;
    while (written < req_len) {
        ret = mbedtls_net_send(&server_fd, (const unsigned char *)req + written, req_len - written);
        if (ret > 0) {
            written += (size_t)ret;
            continue;
        }
        push_mbedtls_error(L, "TCP write failed", ret);
        mbedtls_net_free(&server_fd);
        return 2;
    }

    luaL_Buffer b;
    luaL_buffinit(L, &b);
    unsigned char buf[4096];
    while (1) {
        ret = mbedtls_net_recv_timeout(&server_fd, buf, sizeof(buf), timeout * 1000);
        if (ret > 0) {
            luaL_addlstring(&b, (const char *)buf, ret);
            continue;
        }
        if (ret == 0) {
            break;
        }
        if (ret == MBEDTLS_ERR_SSL_TIMEOUT) {
            break;
        }
        push_mbedtls_error(L, "TCP read failed", ret);
        mbedtls_net_free(&server_fd);
        return 2;
    }

    luaL_pushresult(&b);
    mbedtls_net_free(&server_fd);
    return 1;
}

static int l_request_stream(lua_State *L) {
    const char *host = luaL_checkstring(L, 1);
    int port = luaL_optinteger(L, 2, 443);
    size_t req_len = 0;
    const char *req = luaL_checklstring(L, 3, &req_len);
    const char *ca_file = luaL_optstring(L, 4, NULL);
    int timeout = luaL_optinteger(L, 5, 60);
    int verify = lua_isnoneornil(L, 6) ? 1 : lua_toboolean(L, 6);
    luaL_checktype(L, 7, LUA_TFUNCTION);

    mbedtls_net_context server_fd;
    mbedtls_ssl_context ssl;
    mbedtls_ssl_config conf;
    mbedtls_x509_crt cacert;
    mbedtls_ctr_drbg_context ctr_drbg;
    mbedtls_entropy_context entropy;

    mbedtls_net_init(&server_fd);
    mbedtls_ssl_init(&ssl);
    mbedtls_ssl_config_init(&conf);
    mbedtls_x509_crt_init(&cacert);
    mbedtls_ctr_drbg_init(&ctr_drbg);
    mbedtls_entropy_init(&entropy);

    const char *pers = "rlizx_tls";
    int ret = mbedtls_ctr_drbg_seed(&ctr_drbg, mbedtls_entropy_func, &entropy,
                                   (const unsigned char *)pers, strlen(pers));
    if (ret != 0) {
        push_mbedtls_error(L, "DRBG seed failed", ret);
        goto cleanup;
    }

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", port);
    ret = mbedtls_net_connect(&server_fd, host, port_str, MBEDTLS_NET_PROTO_TCP);
    if (ret != 0) {
        push_mbedtls_error(L, "TCP connect failed", ret);
        goto cleanup;
    }

    if (verify) {
        if (!ca_file || ca_file[0] == '\0') {
            lua_pushnil(L);
            lua_pushstring(L, "CA file required for verification");
            goto cleanup;
        }
        ret = mbedtls_x509_crt_parse_file(&cacert, ca_file);
        if (ret < 0) {
            push_mbedtls_error(L, "CA parse failed", ret);
            goto cleanup;
        }
    }

    ret = mbedtls_ssl_config_defaults(&conf,
                                      MBEDTLS_SSL_IS_CLIENT,
                                      MBEDTLS_SSL_TRANSPORT_STREAM,
                                      MBEDTLS_SSL_PRESET_DEFAULT);
    if (ret != 0) {
        push_mbedtls_error(L, "SSL config failed", ret);
        goto cleanup;
    }

    mbedtls_ssl_conf_rng(&conf, mbedtls_ctr_drbg_random, &ctr_drbg);
    mbedtls_ssl_conf_read_timeout(&conf, timeout * 1000);

    if (verify) {
        mbedtls_ssl_conf_authmode(&conf, MBEDTLS_SSL_VERIFY_REQUIRED);
        mbedtls_ssl_conf_ca_chain(&conf, &cacert, NULL);
    } else {
        mbedtls_ssl_conf_authmode(&conf, MBEDTLS_SSL_VERIFY_NONE);
    }

    ret = mbedtls_ssl_setup(&ssl, &conf);
    if (ret != 0) {
        push_mbedtls_error(L, "SSL setup failed", ret);
        goto cleanup;
    }

    ret = mbedtls_ssl_set_hostname(&ssl, host);
    if (ret != 0) {
        push_mbedtls_error(L, "SNI set failed", ret);
        goto cleanup;
    }

    mbedtls_ssl_set_bio(&ssl, &server_fd, mbedtls_net_send, mbedtls_net_recv, mbedtls_net_recv_timeout);

    while ((ret = mbedtls_ssl_handshake(&ssl)) != 0) {
        if (ret != MBEDTLS_ERR_SSL_WANT_READ && ret != MBEDTLS_ERR_SSL_WANT_WRITE) {
            push_mbedtls_error(L, "TLS handshake failed", ret);
            goto cleanup;
        }
    }

    size_t written = 0;
    while (written < req_len) {
        ret = mbedtls_ssl_write(&ssl, (const unsigned char *)req + written, req_len - written);
        if (ret > 0) {
            written += (size_t)ret;
            continue;
        }
        if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) {
            continue;
        }
        push_mbedtls_error(L, "TLS write failed", ret);
        goto cleanup;
    }

    unsigned char buf[4096];
    while (1) {
        ret = mbedtls_ssl_read(&ssl, buf, sizeof(buf));
        if (ret > 0) {
            lua_pushvalue(L, 7);
            lua_pushlstring(L, (const char *)buf, ret);
            if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
                lua_pushnil(L);
                lua_pushfstring(L, "stream callback error: %s", lua_tostring(L, -1));
                goto cleanup;
            }
            if (!lua_isnoneornil(L, -1) && lua_toboolean(L, -1) == 0) {
                lua_pop(L, 1);
                break;
            }
            lua_pop(L, 1);
            continue;
        }
        if (ret == 0) {
            break;
        }
        if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) {
            continue;
        }
        push_mbedtls_error(L, "TLS read failed", ret);
        goto cleanup;
    }

    mbedtls_ssl_close_notify(&ssl);

    mbedtls_net_free(&server_fd);
    mbedtls_ssl_free(&ssl);
    mbedtls_ssl_config_free(&conf);
    mbedtls_x509_crt_free(&cacert);
    mbedtls_ctr_drbg_free(&ctr_drbg);
    mbedtls_entropy_free(&entropy);
    lua_pushboolean(L, 1);
    return 1;

cleanup:
    mbedtls_net_free(&server_fd);
    mbedtls_ssl_free(&ssl);
    mbedtls_ssl_config_free(&conf);
    mbedtls_x509_crt_free(&cacert);
    mbedtls_ctr_drbg_free(&ctr_drbg);
    mbedtls_entropy_free(&entropy);
    return 2;
}

static int l_tcp_request_stream(lua_State *L) {
    const char *host = luaL_checkstring(L, 1);
    int port = luaL_optinteger(L, 2, 80);
    size_t req_len = 0;
    const char *req = luaL_checklstring(L, 3, &req_len);
    int timeout = luaL_optinteger(L, 4, 60);
    luaL_checktype(L, 5, LUA_TFUNCTION);

    mbedtls_net_context server_fd;
    mbedtls_net_init(&server_fd);

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", port);
    int ret = mbedtls_net_connect(&server_fd, host, port_str, MBEDTLS_NET_PROTO_TCP);
    if (ret != 0) {
        push_mbedtls_error(L, "TCP connect failed", ret);
        mbedtls_net_free(&server_fd);
        return 2;
    }

    size_t written = 0;
    while (written < req_len) {
        ret = mbedtls_net_send(&server_fd, (const unsigned char *)req + written, req_len - written);
        if (ret > 0) {
            written += (size_t)ret;
            continue;
        }
        push_mbedtls_error(L, "TCP write failed", ret);
        mbedtls_net_free(&server_fd);
        return 2;
    }

    unsigned char buf[4096];
    while (1) {
        ret = mbedtls_net_recv_timeout(&server_fd, buf, sizeof(buf), timeout * 1000);
        if (ret > 0) {
            lua_pushvalue(L, 5);
            lua_pushlstring(L, (const char *)buf, ret);
            if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
                lua_pushnil(L);
                lua_pushfstring(L, "stream callback error: %s", lua_tostring(L, -1));
                mbedtls_net_free(&server_fd);
                return 2;
            }
            if (!lua_isnoneornil(L, -1) && lua_toboolean(L, -1) == 0) {
                lua_pop(L, 1);
                break;
            }
            lua_pop(L, 1);
            continue;
        }
        if (ret == 0 || ret == MBEDTLS_ERR_SSL_TIMEOUT) {
            break;
        }
        push_mbedtls_error(L, "TCP read failed", ret);
        mbedtls_net_free(&server_fd);
        return 2;
    }

    mbedtls_net_free(&server_fd);
    lua_pushboolean(L, 1);
    return 1;
}

// 连接句柄结构
typedef struct {
    mbedtls_net_context server_fd;
    mbedtls_ssl_context ssl;
    mbedtls_ssl_config conf;
    mbedtls_x509_crt cacert;
    mbedtls_ctr_drbg_context ctr_drbg;
    mbedtls_entropy_context entropy;
    int is_initialized;
} tls_connection_t;

// 连接元方法：关闭连接
static int connection_gc(lua_State *L) {
    tls_connection_t *conn = (tls_connection_t *)luaL_checkudata(L, 1, "tls.connection");
    if (conn && conn->is_initialized) {
        mbedtls_ssl_free(&conn->ssl);
        mbedtls_ssl_config_free(&conn->conf);
        mbedtls_x509_crt_free(&conn->cacert);
        mbedtls_ctr_drbg_free(&conn->ctr_drbg);
        mbedtls_entropy_free(&conn->entropy);
        mbedtls_net_free(&conn->server_fd);
        conn->is_initialized = 0;
    }
    return 0;
}

// 创建新连接
static int l_create_connection(lua_State *L) {
    const char *host = luaL_checkstring(L, 1);
    int port = luaL_optinteger(L, 2, 443);
    const char *ca_file = luaL_optstring(L, 3, NULL);
    int timeout = luaL_optinteger(L, 4, 60);
    int verify = lua_isnoneornil(L, 5) ? 1 : lua_toboolean(L, 5);

    // 创建连接句柄
    tls_connection_t *conn = (tls_connection_t *)lua_newuserdata(L, sizeof(tls_connection_t));
    conn->is_initialized = 0;

    // 设置元表
    luaL_getmetatable(L, "tls.connection");
    lua_setmetatable(L, -2);

    // 初始化 mbedtls 结构
    mbedtls_net_init(&conn->server_fd);
    mbedtls_ssl_init(&conn->ssl);
    mbedtls_ssl_config_init(&conn->conf);
    mbedtls_x509_crt_init(&conn->cacert);
    mbedtls_ctr_drbg_init(&conn->ctr_drbg);
    mbedtls_entropy_init(&conn->entropy);

    const char *pers = "rlizx_tls_pool";
    int ret = mbedtls_ctr_drbg_seed(&conn->ctr_drbg, mbedtls_entropy_func, &conn->entropy,
                                   (const unsigned char *)pers, strlen(pers));
    if (ret != 0) {
        push_mbedtls_error(L, "DRBG seed failed", ret);
        goto cleanup_fail;
    }

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", port);
    ret = mbedtls_net_connect(&conn->server_fd, host, port_str, MBEDTLS_NET_PROTO_TCP);
    if (ret != 0) {
        push_mbedtls_error(L, "TCP connect failed", ret);
        goto cleanup_fail;
    }

    if (verify) {
        if (!ca_file || ca_file[0] == '\0') {
            lua_pushnil(L);
            lua_pushstring(L, "CA file required for verification");
            goto cleanup_fail;
        }
        ret = mbedtls_x509_crt_parse_file(&conn->cacert, ca_file);
        if (ret < 0) {
            push_mbedtls_error(L, "CA parse failed", ret);
            goto cleanup_fail;
        }
    }

    ret = mbedtls_ssl_config_defaults(&conn->conf,
                                      MBEDTLS_SSL_IS_CLIENT,
                                      MBEDTLS_SSL_TRANSPORT_STREAM,
                                      MBEDTLS_SSL_PRESET_DEFAULT);
    if (ret != 0) {
        push_mbedtls_error(L, "SSL config failed", ret);
        goto cleanup_fail;
    }

    mbedtls_ssl_conf_rng(&conn->conf, mbedtls_ctr_drbg_random, &conn->ctr_drbg);
    mbedtls_ssl_conf_read_timeout(&conn->conf, timeout * 1000);

    if (verify) {
        mbedtls_ssl_conf_authmode(&conn->conf, MBEDTLS_SSL_VERIFY_REQUIRED);
        mbedtls_ssl_conf_ca_chain(&conn->conf, &conn->cacert, NULL);
    } else {
        mbedtls_ssl_conf_authmode(&conn->conf, MBEDTLS_SSL_VERIFY_NONE);
    }

    ret = mbedtls_ssl_setup(&conn->ssl, &conn->conf);
    if (ret != 0) {
        push_mbedtls_error(L, "SSL setup failed", ret);
        goto cleanup_fail;
    }

    ret = mbedtls_ssl_set_hostname(&conn->ssl, host);
    if (ret != 0) {
        push_mbedtls_error(L, "SNI set failed", ret);
        goto cleanup_fail;
    }

    mbedtls_ssl_set_bio(&conn->ssl, &conn->server_fd, mbedtls_net_send, mbedtls_net_recv, mbedtls_net_recv_timeout);

    while ((ret = mbedtls_ssl_handshake(&conn->ssl)) != 0) {
        if (ret != MBEDTLS_ERR_SSL_WANT_READ && ret != MBEDTLS_ERR_SSL_WANT_WRITE) {
            push_mbedtls_error(L, "TLS handshake failed", ret);
            goto cleanup_fail;
        }
    }

    conn->is_initialized = 1;
    return 1;  // 返回连接句柄

cleanup_fail:
    mbedtls_ssl_free(&conn->ssl);
    mbedtls_ssl_config_free(&conn->conf);
    mbedtls_x509_crt_free(&conn->cacert);
    mbedtls_ctr_drbg_free(&conn->ctr_drbg);
    mbedtls_entropy_free(&conn->entropy);
    mbedtls_net_free(&conn->server_fd);
    return 2;
}

// 关闭连接
static int l_close_connection(lua_State *L) {
    tls_connection_t *conn = (tls_connection_t *)luaL_checkudata(L, 1, "tls.connection");
    if (!conn || !conn->is_initialized) {
        lua_pushboolean(L, 0);
        return 1;
    }

    mbedtls_ssl_close_notify(&conn->ssl);
    mbedtls_ssl_free(&conn->ssl);
    mbedtls_ssl_config_free(&conn->conf);
    mbedtls_x509_crt_free(&conn->cacert);
    mbedtls_ctr_drbg_free(&conn->ctr_drbg);
    mbedtls_entropy_free(&conn->entropy);
    mbedtls_net_free(&conn->server_fd);
    conn->is_initialized = 0;

    lua_pushboolean(L, 1);
    return 1;
}

// 使用现有连接发送请求
static int l_request_with_connection(lua_State *L) {
    tls_connection_t *conn = (tls_connection_t *)luaL_checkudata(L, 1, "tls.connection");
    if (!conn || !conn->is_initialized) {
        lua_pushnil(L);
        lua_pushstring(L, "Invalid connection handle");
        return 2;
    }

    size_t req_len = 0;
    const char *req = luaL_checklstring(L, 2, &req_len);
    int timeout = luaL_optinteger(L, 3, 60);

    // 更新超时
    mbedtls_ssl_conf_read_timeout(&conn->conf, timeout * 1000);

    size_t written = 0;
    int ret;
    while (written < req_len) {
        ret = mbedtls_ssl_write(&conn->ssl, (const unsigned char *)req + written, req_len - written);
        if (ret > 0) {
            written += (size_t)ret;
            continue;
        }
        if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) {
            continue;
        }
        push_mbedtls_error(L, "TLS write failed", ret);
        return 2;
    }

    luaL_Buffer b;
    luaL_buffinit(L, &b);
    unsigned char buf[4096];
    while (1) {
        ret = mbedtls_ssl_read(&conn->ssl, buf, sizeof(buf));
        if (ret > 0) {
            luaL_addlstring(&b, (const char *)buf, ret);
            continue;
        }
        if (ret == 0) {
            break;
        }
        if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) {
            continue;
        }
        push_mbedtls_error(L, "TLS read failed", ret);
        return 2;
    }

    luaL_pushresult(&b);
    return 1;
}

static const luaL_Reg tlslib[] = {
    {"request", l_request},
    {"tcp_request", l_tcp_request},
    {"request_stream", l_request_stream},
    {"tcp_request_stream", l_tcp_request_stream},
    {"create_connection", l_create_connection},
    {"close_connection", l_close_connection},
    {"request_with_connection", l_request_with_connection},
    {NULL, NULL}
};

int luaopen_tls(lua_State *L) {
    luaL_newlib(L, tlslib);

    // 创建连接元表
    luaL_newmetatable(L, "tls.connection");
    lua_pushcfunction(L, connection_gc);
    lua_setfield(L, -2, "__gc");
    lua_pushcfunction(L, l_close_connection);
    lua_setfield(L, -2, "close");
    lua_pop(L, 1);

    return 1;
}
