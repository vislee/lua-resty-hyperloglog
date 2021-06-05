-- Copyright (C) vislee

local base = require "resty.core.base"
local bit = require "bit"
local ffi = require "ffi"
local new_tab = base.new_tab
local C = ffi.C
local ffi_cast = ffi.cast
local bor = bit.bor
local band = bit.band
local lshift = bit.lshift
local rshift = bit.rshift
local mlog = math.log
local floor = math.floor
local tonumber = tonumber
local setmetatable = setmetatable
local ngx = ngx


ffi.cdef[[
typedef unsigned char u_char;
uint32_t ngx_murmur_hash2(u_char *data, size_t len);
]]


local _M = {}
local mt = { __index = _M }
local global = {}

local _murmur32 = function(v)
    return tonumber(C.ngx_murmur_hash2(ffi_cast("unsigned char*", v), #v))
end


local function u64_join(hi, lo)
    local rshift, band = rshift, band
    hi = rshift(hi, 1) * 2 + band(hi, 1)
    lo = rshift(lo, 1) * 2 + band(lo, 1)
    return (hi * 0x100000000ull) + (lo % 0x100000000)
end


local function u64_split(x)
    return floor(tonumber(x / 0x100000000)), tonumber(x % 0x100000000)
end


local function u64_lshift(x, n)
    if band(n, 0x3F) == 0 then return x end
    local hi, lo = u64_split(x)
    if band(n, 0x20) == 0 then
        lo, hi = lshift(lo, n), bor(lshift(hi, n), rshift(lo, 32 - n))
    else
        lo, hi = 0, lshift(lo, n)
    end
    return u64_join(hi, lo)
end


local _alpha = function(m)
    if m == 16 then
        return 0.673
    elseif m == 32 then
        return 0.697
    elseif m == 64 then
        return 0.709
    end

    return 0.7213 / (1 + 1.079/m)
end


local _leading_zeros32 = function(x)
    local _len32 = function(x)
        local n = 0
        if x >= lshift(1, 16) then
            x = rshift(x, 16)
            n = 16
        end
        if x >= lshift(1, 8) then
            x = rshift(x, 8)
            n = n + 8
        end
        if x >= lshift(1, 4) then
            x = rshift(x, 4)
            n = n + 4
        end

        local xx = {0x00, 0x01, 0x02, 0x02, 0x03, 0x03, 0x03, 0x03, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x05}
        return n + xx[tonumber(x)+1]
    end
    return 32 - _len32(x)
end


local _get_pos_val = function(x, p)
    local i = band(rshift(x, 32-p), lshift(1, p)-1)
    local w = bor(u64_lshift(band(x, 0XFFFF), p), lshift(1, p-1))
    return i, _leading_zeros32(w)+1
end


function _M.new(name, log2m)
    if log2m < 4 or log2m > 20 then
        return nil, "wrong log2m"
    end

    local obj = global[name]
    if obj and obj.log2m == log2m then
        return obj
    elseif obj then
        return nil, "conflict name"
    end

    local data
    local m = lshift(1, log2m)
    if ngx.shared[name] then
        -- get、safe_set、flush_all
        data = ngx.shared[name]
    else
        data = new_tab(0, m)
        setmetatable(data, { __index = {
            get = function(t, key)
                return rawget(t, key)
            end,
            safe_set = function(t, key, val)
                rawset(t, key, val)
                return true
            end,
            flush_all = function(t)
                for i = 1, m do
                    rawset(t, i, nil)
                end
            end
        }})
    end

    obj = setmetatable({
        name = name,
        log2m = log2m,
        m = m,
        data = data,
        alpha = _alpha(m),
        cached = -1,
    }, mt)
    global[name] = obj

    return obj
end


function _M.close(self)
    self.cached = -1
    self.data:flush_all()
    global[self.name] = nil
end


function _M.insert(self, s)
    local hash = _murmur32(s)
    local i, v = _get_pos_val(hash, self.log2m)
    local tmp = self.data:get(i) or 0
    if v > tmp then
        local ok, err = self.data:safe_set(i, v)
        if not ok then
            ngx.log(ngx.WARN, "insert error.", err)
        end
        self.cached = -1
    end
end


function _M.merge(self, hll)
    if hll == nil or type(hll) ~= "table" then
        return false, "hll not hyperloglog obj"
    end

    if self.name == hll.name then
        return false, "same obj"
    end

    if self.log2m ~= hll.log2m then
        return false, "not match log2m"
    end

    local x, y
    local ok, err
    for i =1, self.m do
        x = self.data:get(i) or 0
        y = hll.data:get(i) or 0
        if y > x then
            ok, err = self.data:safe_set(i, y)
            if not ok then
                ngx.log(ngx.WARN, "merge error.", err)
            end
            self.cached = -1
        end
    end

    return true
end


function _M.count(self)
    if self.cached ~= -1 then
        return self.cached
    end

    local alpha_mm = self.alpha * self.m * self.m
    local sum, zeros, item = 0, 0, 0
    for i = 1, self.m do
        item = self.data:get(i) or 0
        if item == 0 then
           zeros = zeros + 1
        end
        sum = sum + 1.0 / lshift(1, item)
    end

    local estimate = alpha_mm / sum
    if estimate <= 2.5 * self.m then
        self.cached = -floor(self.m * mlog(zeros/self.m) - 0.5)
        return self.cached
    end
    self.cached = floor(estimate + 0.5)
    return self.cached
end


return _M
