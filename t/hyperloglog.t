use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

log_level('debug');

repeat_each(1);
plan tests => repeat_each() * (3 * blocks());

no_long_string();

run_tests();

__DATA__
=== TEST 1: count
--- http_config
    lua_package_path 'lib/?.lua;;';
    init_by_lua_block {
        require 'luacov.tick'
        jit.off()
    }
--- config
    location /t {
        content_by_lua_block {
            local hll = require "resty.hyperloglog"
            local h = hll.new("test", 12)
            for i = 1, 100 do
                h:insert("/hello/world" .. i)
            end
            ngx.print("count:", h:count())
            ngx.exit(ngx.HTTP_OK)
        }
    }
--- request
GET /t
--- response_body_like: count:101
--- error_code: 200
--- timeout: 30
--- no_error_log
[error]


=== TEST 2: count: global obj
--- http_config
    lua_package_path 'lib/?.lua;;';

    init_by_lua_block {
        require 'luacov.tick'
        jit.off()

        local hll = require "resty.hyperloglog"
        h = hll.new("test", 12)
    }

--- config
    location /t {
        content_by_lua_block {
            for i = 1, 500 do
                h:insert("/hello/world" .. i)
            end
            ngx.print("count:", h:count())
            ngx.exit(ngx.HTTP_OK)
        }
    }

--- request
GET /t
--- response_body: count:499
--- error_code: 200
--- timeout: 30
--- no_error_log
[error]



=== TEST 3: count: repeat insert
--- http_config
    lua_package_path 'lib/?.lua;;';

    init_by_lua_block {
        require 'luacov.tick'
        jit.off()
    }

--- config
    location /t {
        content_by_lua_block {
            local hll = require "resty.hyperloglog"
            local h = hll.new("test", 12)
            for i = 1, 100 do
                h:insert("/hello/world" .. i)
                h:insert("/hello/world" .. i)
                h:insert("/hello/world" .. i)
                h:insert("/hello/world" .. i)
                h:insert("/hello/world" .. i)
            end
            for i = 1, 100 do
                h:insert("/hello/world" .. i)
                h:insert("/hello/world" .. i)
                h:insert("/hello/world" .. i)
                h:insert("/hello/world" .. i)
                h:insert("/hello/world" .. i)
            end
            ngx.print("count:", h:count())
            ngx.exit(ngx.HTTP_OK)
        }
    }

--- request
GET /t
--- response_body: count:101
--- error_code: 200
--- timeout: 30
--- no_error_log
[error]


=== TEST 4: count: used dict
--- http_config
    lua_package_path 'lib/?.lua;;';
    lua_shared_dict test 10m;

    init_by_lua_block {
        require 'luacov.tick'
        jit.off()
    }

--- config
    location /t {
        content_by_lua_block {
            local hll = require "resty.hyperloglog"
            local h = hll.new("test", 12)
            for i = 1, 100 do
                h:insert("/hello/world" .. i)
            end
            ngx.print("count:", h:count())
            h:close()
            ngx.exit(ngx.HTTP_OK)
        }
    }

--- request
GET /t
--- response_body_like: count:101
--- error_code: 200
--- timeout: 30
--- no_error_log
[error]


=== TEST 5: merge
--- http_config
    lua_package_path 'lib/?.lua;;';
    lua_shared_dict test1 10m;

    init_by_lua_block {
        require 'luacov.tick'
        jit.off()
    }

--- config
    location /t {
        content_by_lua_block {
            local hll = require "resty.hyperloglog"
            local h1 = hll.new("test1", 12)
            for i = 1, 1000 do
                h1:insert("/hello/world" .. i)
                h1:insert("/foo/bar" .. i)
            end
            ngx.print("h1_count:", h1:count())

            local h2 = hll.new("test2", 12)
            for i = 1, 30 do
                h2:insert("/hello/world" .. i)
                h2:insert("/foo/bar/foo" .. i)
            end
            ngx.print(" h2_count:", h2:count())

            local ok, err = h1:merge(h2)
            if not ok then
                ngx.log(ngx.ERR, "merge error.", err)
            end
            h2:close()
            ngx.print(" merge_count:", h1:count())
            ngx.exit(ngx.HTTP_OK)
        }
    }

--- request
GET /t
--- response_body: h1_count:2009 h2_count:61 merge_count:2048
--- error_code: 200
--- timeout: 30
--- no_error_log
[error]



