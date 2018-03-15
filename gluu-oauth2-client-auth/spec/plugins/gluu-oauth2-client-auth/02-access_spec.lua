local helpers = require "spec.helpers"
local oxd = require "oxdweb"
local cjson = require "cjson"
local auth_helper = require "kong.plugins.gluu-oauth2-client-auth.helper"

describe("gluu-oauth2-client-auth plugin", function()
    local proxy_client
    local admin_client
    local oauth2_consumer_oauth_mode
    local oauth2_consumer_with_uma_mode
    local oauth2_consumer_with_mix_mode
    local api
    local plugin
    local timeout = 6000
    local op_server = "https://gluu.local.org"
    local oxd_http = "http://localhost:8553"
    local OAUTH_CLIENT_ID = "OAUTH-CLIENT-ID"
    local OAUTH_EXPIRATION = "OAUTH-EXPIRATION"
    local OAUTH_SCOPES = "OAUTH_SCOPES"

    setup(function()
        helpers.run_migrations()
        api = assert(helpers.dao.apis:insert {
            name = "json",
            upstream_url = "https://jsonplaceholder.typicode.com",
            hosts = { "jsonplaceholder.typicode.com" }
        })

        print("----------- Api created ----------- ")
        for k, v in pairs(api) do
            print(k, ": ", v)
        end

        print("\n----------- Add consumer ----------- ")
        local consumer = assert(helpers.dao.consumers:insert {
            username = "foo"
        })

        -- start Kong with your testing Kong configuration (defined in "spec.helpers")
        assert(helpers.start_kong())
        print("Kong started")

        admin_client = helpers.admin_client(timeout)

        print("\n----------- Plugin configuration ----------- ")
        local res = assert(admin_client:send {
            method = "POST",
            path = "/apis/json/plugins",
            body = {
                name = "gluu-oauth2-client-auth",
                config = {
                    op_server = op_server,
                    oxd_http_url = oxd_http
                },
            },
            headers = {
                ["Content-Type"] = "application/json"
            }
        })
        assert.response(res).has.status(201)
        plugin = assert.response(res).has.jsonbody()

        for k, v in pairs(plugin) do
            print(k, ": ", v)
            if k == 'config' then
                for sk, sv in pairs(v) do
                    print(sk, ": ", sv)
                end
            end
        end

        print("\n----------- OAuth2 consumer oauth mode credential ----------- ")
        local res = assert(admin_client:send {
            method = "POST",
            path = "/consumers/foo/gluu-oauth2-client-auth",
            body = {
                name = "oauth2_credential_oauth_mode",
                op_host = "https://gluu.local.org",
                oxd_http_url = "http://localhost:8553"
            },
            headers = {
                ["Content-Type"] = "application/json"
            }
        })
        oauth2_consumer_oauth_mode = cjson.decode(assert.res_status(201, res))
        for k, v in pairs(oauth2_consumer_oauth_mode) do
            print(k, ": ", v)
        end

        print("\n----------- OAuth2 consumer credential with mix_mode = true ----------- ")
        local res = assert(admin_client:send {
            method = "POST",
            path = "/consumers/foo/gluu-oauth2-client-auth",
            body = {
                name = "oauth2_credential_mix_mode",
                op_host = "https://gluu.local.org",
                oxd_http_url = "http://localhost:8553",
                mix_mode = true
            },
            headers = {
                ["Content-Type"] = "application/json"
            }
        })
        oauth2_consumer_with_mix_mode = cjson.decode(assert.res_status(201, res))
        for k, v in pairs(oauth2_consumer_with_mix_mode) do
            print(k, ": ", v)
        end

        print("\n----------- OAuth2 consumer credential with uma_mode = true ----------- ")
        local res = assert(admin_client:send {
            method = "POST",
            path = "/consumers/foo/gluu-oauth2-client-auth",
            body = {
                name = "oauth2_credential_uma_mode",
                op_host = "https://gluu.local.org",
                oxd_http_url = "http://localhost:8553",
                uma_mode = true
            },
            headers = {
                ["Content-Type"] = "application/json"
            }
        })
        oauth2_consumer_with_uma_mode = cjson.decode(assert.res_status(201, res))
        for k, v in pairs(oauth2_consumer_with_uma_mode) do
            print(k, ": ", v)
        end
    end)

    teardown(function()
        if admin_client then
            admin_client:close()
        end

        helpers.stop_kong()
        print("Kong stopped")
    end)

    before_each(function()
        proxy_client = helpers.proxy_client(timeout)
    end)

    after_each(function()
        if proxy_client then
            proxy_client:close()
        end
    end)

    describe("oauth2-consumer flow without gluu_oauth2_rs plugin", function()
        describe("When oauth2-consumer is in oauth_mode = true", function()
            it("401 Unauthorized when token is not present in header", function()
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com"
                    }
                })
                assert.res_status(401, res)
            end)

            it("401 Unauthorized when token is invalid", function()
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer 39cd86e5-ca17-4936-a9b7-deac998431fb"
                    }
                })
                assert.res_status(401, res)
            end)

            it("200 Authorized when token active = true", function()
                -- ------------------GET Client Token-------------------------------
                local tokenRequest = {
                    oxd_host = oauth2_consumer_oauth_mode.oxd_http_url,
                    client_id = oauth2_consumer_oauth_mode.client_id,
                    client_secret = oauth2_consumer_oauth_mode.client_secret,
                    scope = { "openid", "uma_protection" },
                    op_host = oauth2_consumer_oauth_mode.op_host
                };

                local token = oxd.get_client_token(tokenRequest)
                local req_access_token = token.data.access_token

                -- 1st request, Cache is not exist
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer " .. req_access_token,
                    }
                })
                assert.res_status(200, res)
                assert.equal(true, not auth_helper.is_empty(res.headers[OAUTH_CLIENT_ID]))
                assert.equal(true, not auth_helper.is_empty(res.headers[OAUTH_EXPIRATION]))
                assert.equal(true, not auth_helper.is_empty(res.headers[OAUTH_SCOPES]))

                -- 2nd time request
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer " .. req_access_token,
                    }
                })

                assert.res_status(200, res)
                assert.equal(true, not auth_helper.is_empty(res.headers[OAUTH_CLIENT_ID]))
                assert.equal(true, not auth_helper.is_empty(res.headers[OAUTH_EXPIRATION]))
                assert.equal(true, not auth_helper.is_empty(res.headers[OAUTH_SCOPES]))

                -- 3rs time request
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer " .. req_access_token,
                    }
                })

                assert.res_status(200, res)
                assert.equal(true, not auth_helper.is_empty(res.headers[OAUTH_CLIENT_ID]))
                assert.equal(true, not auth_helper.is_empty(res.headers[OAUTH_EXPIRATION]))
                assert.equal(true, not auth_helper.is_empty(res.headers[OAUTH_SCOPES]))
            end)
        end)

        describe("When oauth2-consumer is in mix_mode = true", function()
            it("401 Unauthorized when token is not present in header", function()
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com"
                    }
                })
                assert.res_status(401, res)
            end)

            it("401 Unauthorized when token is invalid", function()
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer 39cd86e5-ca17-4936-a9b7-deac998431fb"
                    }
                })
                assert.res_status(401, res)
            end)

            it("Get 200 status when token is active = true", function()
                -- ------------------GET Client Token-------------------------------
                local tokenRequest = {
                    oxd_host = oauth2_consumer_with_mix_mode.oxd_http_url,
                    client_id = oauth2_consumer_with_mix_mode.client_id,
                    client_secret = oauth2_consumer_with_mix_mode.client_secret,
                    scope = { "openid", "uma_protection" },
                    op_host = oauth2_consumer_with_mix_mode.op_host
                };

                local token = oxd.get_client_token(tokenRequest)
                local req_access_token = token.data.access_token

                -- 1st time request, Cache is not exist
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer " .. req_access_token,
                    }
                })
                assert.res_status(200, res)

                -- 2nd time request, when cache exist
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer " .. req_access_token,
                    }
                })
                assert.res_status(200, res)

                -- 3rs time request, when cache exist
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer " .. req_access_token,
                    }
                })
                assert.res_status(200, res)
            end)
        end)

        describe("When oauth2-consumer is in uma_mode = true", function()
            it("401 Unauthorized when token is not present in header", function()
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com"
                    }
                })
                assert.res_status(401, res)
            end)

            it("401 Unauthorized when token is invalid", function()
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer 39cd86e5-ca17-4936-a9b7-deac998431fb"
                    }
                })
                assert.res_status(401, res)
            end)

            it("Get 200 status when token is active = true but token is oauth2 access token", function()
                -- ------------------GET Client Token-------------------------------
                local tokenRequest = {
                    oxd_host = oauth2_consumer_with_uma_mode.oxd_http_url,
                    client_id = oauth2_consumer_with_uma_mode.client_id,
                    client_secret = oauth2_consumer_with_uma_mode.client_secret,
                    scope = { "openid", "uma_protection" },
                    op_host = oauth2_consumer_with_uma_mode.op_host
                };
                local token = oxd.get_client_token(tokenRequest)
                local req_access_token = token.data.access_token
                -- 1st time request, Cache is not exist
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer " .. req_access_token,
                    }
                })
                assert.res_status(200, res)

                -- 2nd time request, when cache exist
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer " .. req_access_token,
                    }
                })
                assert.res_status(200, res)

                -- 3rd time request, when cache exist
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer " .. req_access_token,
                    }
                })
                assert.res_status(200, res)
            end)
        end)
    end)

    describe("oauth2-consumer flow with gluu_oauth2_rs plugin", function()
        local gluu_oauth2_rs_plugin
        setup(function()
            local res = assert(admin_client:send {
                method = "POST",
                path = "/apis/json/plugins",
                body = {
                    name = "gluu-oauth2-rs",
                    config = {
                        uma_server_host = op_server,
                        oxd_host = oxd_http,
                        protection_document = "[{\"path\":\"/posts\",\"conditions\":[{\"httpMethods\":[\"GET\",\"POST\"],\"scope_expression\":{\"rule\":{\"or\":[{\"var\":0}]},\"data\":[\"https://jsonplaceholder.typicode.com\"]}}]},{\"path\":\"/comments\",\"conditions\":[{\"httpMethods\":[\"GET\"],\"scope_expression\":{\"rule\":{\"and\":[{\"var\":0}]},\"data\":[\"https://jsonplaceholder.typicode.com\"]}}]}]"
                    },
                },
                headers = {
                    ["Content-Type"] = "application/json"
                }
            })
            assert.response(res).has.status(201)
            gluu_oauth2_rs_plugin = assert.response(res).has.jsonbody()
        end)

        -- oauth_mode
        describe("When oauth2-consumer is in oauth_mode = true", function()
            it("401 Unauthorized when token is not present in header", function()
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com"
                    }
                })
                assert.res_status(401, res)
            end)

            it("401 Unauthorized when token is invalid", function()
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer 39cd86e5-ca17-4936-a9b7-deac998431fb"
                    }
                })
                assert.res_status(401, res)
            end)

            it("401 status when UMA RPT token active = true but oauth_mode is active", function()
                -- ------------------GET Client Token-------------------------------
                local tokenRequest = {
                    oxd_host = gluu_oauth2_rs_plugin.config.oxd_host,
                    client_id = gluu_oauth2_rs_plugin.config.client_id,
                    client_secret = gluu_oauth2_rs_plugin.config.client_secret,
                    scope = { "openid", "uma_protection" },
                    op_host = gluu_oauth2_rs_plugin.config.uma_server_host
                };

                local token = oxd.get_client_token(tokenRequest)
                -- -----------------------------------------------------------------

                -- ------------------GET check_access-------------------------------
                local umaAccessRequest = {
                    oxd_host = gluu_oauth2_rs_plugin.config.oxd_host,
                    oxd_id = gluu_oauth2_rs_plugin.config.oxd_id,
                    rpt = "",
                    path = "/posts",
                    http_method = "GET"
                }
                local umaAccessResponse = oxd.uma_rs_check_access(umaAccessRequest, token.data.access_token)

                -- ------------------GET Client Token-------------------------------
                local tokenRequest = {
                    oxd_host = oauth2_consumer_oauth_mode.oxd_http_url,
                    client_id = oauth2_consumer_oauth_mode.client_id,
                    client_secret = oauth2_consumer_oauth_mode.client_secret,
                    scope = { "openid", "uma_protection" },
                    op_host = oauth2_consumer_oauth_mode.op_host
                };

                local token = oxd.get_client_token(tokenRequest)
                local req_access_token = token.data.access_token

                -- ------------------GET rpt-------------------------------
                local umaGetRPTRequest = {
                    oxd_host = oauth2_consumer_oauth_mode.oxd_http_url,
                    oxd_id = oauth2_consumer_oauth_mode.oxd_id,
                    ticket = umaAccessResponse.data.ticket
                }
                local umaGetRPTResponse = oxd.uma_rp_get_rpt(umaGetRPTRequest, req_access_token)

                -- -----------------------------------------------------------------
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer " .. umaGetRPTResponse.data.access_token,
                    }
                })
                local body = assert.res_status(401, res)
                local json = cjson.decode(body)
                assert.equal("Unauthorized", json.message)
            end)

            it("200 status when oauth token is active = true", function()
                -- ------------------GET Client Token-------------------------------
                local tokenRequest = {
                    oxd_host = oauth2_consumer_oauth_mode.oxd_http_url,
                    client_id = oauth2_consumer_oauth_mode.client_id,
                    client_secret = oauth2_consumer_oauth_mode.client_secret,
                    scope = { "openid", "uma_protection" },
                    op_host = oauth2_consumer_oauth_mode.op_host
                };

                local token = oxd.get_client_token(tokenRequest)
                local req_access_token = token.data.access_token

                -- 1st time request, Cache is not exist
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer " .. req_access_token,
                    }
                })
                assert.res_status(200, res)

                -- 2nd time request, when cache exist
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer " .. req_access_token,
                    }
                })
                assert.res_status(200, res)

                -- 3rs time request, when cache exist
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer " .. req_access_token,
                    }
                })
                assert.res_status(200, res)
            end)
        end)

        -- This is same case when token_type is OAuth
        describe("When oauth2-consumer is in mix_mode = true", function()
            it("401 Unauthorized when token is not present in header", function()
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com"
                    }
                })
                assert.res_status(401, res)
            end)

            it("401 Unauthorized when token is invalid", function()
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer 39cd86e5-ca17-4936-a9b7-deac998431fb"
                    }
                })
                assert.res_status(401, res)
            end)

            it("200 status when token is active = true", function()
                -- ------------------GET Client Token-------------------------------
                local tokenRequest = {
                    oxd_host = oauth2_consumer_with_mix_mode.oxd_http_url,
                    client_id = oauth2_consumer_with_mix_mode.client_id,
                    client_secret = oauth2_consumer_with_mix_mode.client_secret,
                    scope = { "openid", "uma_protection" },
                    op_host = oauth2_consumer_with_mix_mode.op_host
                };

                local token = oxd.get_client_token(tokenRequest)
                local req_access_token = token.data.access_token

                -- 1st time request, Cache is not exist
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer " .. req_access_token
                    }
                })
                assert.res_status(200, res)

                -- 2nd time request, when cache exist
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer " .. req_access_token,
                    }
                })
                assert.res_status(200, res)

                -- 3rs time request, when cache exist
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer " .. req_access_token,
                    }
                })
                assert.res_status(200, res)
            end)

            it("401 status when OAuth token is active = true but uma_mode is active", function()
                -- ------------------GET Client Token-------------------------------
                local tokenRequest = {
                    oxd_host = oauth2_consumer_with_uma_mode.oxd_http_url,
                    client_id = oauth2_consumer_with_uma_mode.client_id,
                    client_secret = oauth2_consumer_with_uma_mode.client_secret,
                    scope = { "openid", "uma_protection" },
                    op_host = oauth2_consumer_with_uma_mode.op_host
                };

                local token = oxd.get_client_token(tokenRequest)
                local req_access_token = token.data.access_token

                -- 1st time request, Cache is not exist
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer " .. req_access_token,
                    }
                })
                local body = assert.res_status(401, res)
                local json = cjson.decode(body)
                assert.equal("Unauthorized! UMA Token is required in UMA Mode", json.message)
            end)
        end)

        -- This is same case when token_type is UMA RPT token
        describe("When oauth2-consumer is in uma_mode = true", function()
            it("401 Unauthorized when token is not present in header", function()
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com"
                    }
                })
                assert.res_status(401, res)
            end)

            it("401 Unauthorized when token is invalid", function()
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer 39cd86e5-ca17-4936-a9b7-deac998431fb"
                    }
                })
                assert.res_status(401, res)
            end)

            it("200 status when token is RPT token active = true", function()
                -- ------------------GET Client Token-------------------------------
                local tokenRequest = {
                    oxd_host = gluu_oauth2_rs_plugin.config.oxd_host,
                    client_id = gluu_oauth2_rs_plugin.config.client_id,
                    client_secret = gluu_oauth2_rs_plugin.config.client_secret,
                    scope = { "openid", "uma_protection" },
                    op_host = gluu_oauth2_rs_plugin.config.uma_server_host
                };

                local token = oxd.get_client_token(tokenRequest)
                -- -----------------------------------------------------------------

                -- ------------------GET check_access-------------------------------
                local umaAccessRequest = {
                    oxd_host = gluu_oauth2_rs_plugin.config.oxd_host,
                    oxd_id = gluu_oauth2_rs_plugin.config.oxd_id,
                    rpt = "",
                    path = "/posts",
                    http_method = "GET"
                }
                local umaAccessResponse = oxd.uma_rs_check_access(umaAccessRequest, token.data.access_token)

                -- ------------------GET Client Token-------------------------------
                local tokenRequest = {
                    oxd_host = oauth2_consumer_with_uma_mode.oxd_http_url,
                    client_id = oauth2_consumer_with_uma_mode.client_id,
                    client_secret = oauth2_consumer_with_uma_mode.client_secret,
                    scope = { "openid", "uma_protection" },
                    op_host = oauth2_consumer_with_uma_mode.op_host
                };

                local token = oxd.get_client_token(tokenRequest)
                local req_access_token = token.data.access_token

                -- ------------------GET rpt-------------------------------
                local umaGetRPTRequest = {
                    oxd_host = oauth2_consumer_with_uma_mode.oxd_http_url,
                    oxd_id = oauth2_consumer_with_uma_mode.oxd_id,
                    ticket = umaAccessResponse.data.ticket
                }
                local umaGetRPTResponse = oxd.uma_rp_get_rpt(umaGetRPTRequest, req_access_token)

                -- -----------------------------------------------------------------

                -- 1st time request, Cache is not exist
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer " .. umaGetRPTResponse.data.access_token,
                    }
                })
                assert.res_status(200, res)

                -- 2nd time request, when cache exist
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer " .. umaGetRPTResponse.data.access_token,
                    }
                })
                assert.res_status(200, res)

                -- 3rd time request, when cache exist
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer " .. umaGetRPTResponse.data.access_token,
                    }
                })
                assert.res_status(200, res)
            end)

            it("401 status when UMA RPT token active = true but oauth_mode is active", function()
                -- ------------------GET Client Token-------------------------------
                local tokenRequest = {
                    oxd_host = gluu_oauth2_rs_plugin.config.oxd_host,
                    client_id = gluu_oauth2_rs_plugin.config.client_id,
                    client_secret = gluu_oauth2_rs_plugin.config.client_secret,
                    scope = { "openid", "uma_protection" },
                    op_host = gluu_oauth2_rs_plugin.config.uma_server_host
                };

                local token = oxd.get_client_token(tokenRequest)
                -- -----------------------------------------------------------------

                -- ------------------GET check_access-------------------------------
                local umaAccessRequest = {
                    oxd_host = gluu_oauth2_rs_plugin.config.oxd_host,
                    oxd_id = gluu_oauth2_rs_plugin.config.oxd_id,
                    rpt = "",
                    path = "/posts",
                    http_method = "GET"
                }
                local umaAccessResponse = oxd.uma_rs_check_access(umaAccessRequest, token.data.access_token)

                -- ------------------GET Client Token-------------------------------
                local tokenRequest = {
                    oxd_host = oauth2_consumer_oauth_mode.oxd_http_url,
                    client_id = oauth2_consumer_oauth_mode.client_id,
                    client_secret = oauth2_consumer_oauth_mode.client_secret,
                    scope = { "openid", "uma_protection" },
                    op_host = oauth2_consumer_oauth_mode.op_host
                };

                local token = oxd.get_client_token(tokenRequest)
                local req_access_token = token.data.access_token

                -- ------------------GET rpt-------------------------------
                local umaGetRPTRequest = {
                    oxd_host = oauth2_consumer_oauth_mode.oxd_http_url,
                    oxd_id = oauth2_consumer_oauth_mode.oxd_id,
                    ticket = umaAccessResponse.data.ticket
                }
                local umaGetRPTResponse = oxd.uma_rp_get_rpt(umaGetRPTRequest, req_access_token)

                -- -----------------------------------------------------------------
                local res = assert(proxy_client:send {
                    method = "GET",
                    path = "/posts",
                    headers = {
                        ["Host"] = "jsonplaceholder.typicode.com",
                        ["Authorization"] = "Bearer " .. umaGetRPTResponse.data.access_token,
                    }
                })
                local body = assert.res_status(401, res)
                local json = cjson.decode(body)
                assert.equal("Unauthorized", json.message)
            end)
        end)
    end)
end)