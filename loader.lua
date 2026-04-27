-- Sigmatik Protected Loader
-- Single public URL. Reads UID/HWID, asks the API, runs anti-dump checks,
-- decrypts and executes the protected payload. By @sigmatik323
--
-- Distribute ONLY this URL:
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/Hjgyhfyh/Scripts-roblox/main/loader.lua"))()

local API_BASE  = "https://telepasta.ru/sig-api"  -- HTTPS via nginx -> 127.0.0.1:8088

local HttpService = game:GetService("HttpService")
local Players     = game:GetService("Players")
local LP          = Players.LocalPlayer

-- ---------- anti-dump (run BEFORE any payload code) ----------
local function _abort(reason, extra)
    -- best-effort signal home so the owner knows; never throw.
    pcall(function()
        local body = HttpService:JSONEncode({
            userId    = LP and LP.UserId or 0,
            username  = LP and LP.Name or "?",
            detected  = tostring(reason),
            extra     = tostring(extra or ""):sub(1, 200),
            ts        = os.time(),
        })
        local req = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
        if req then
            pcall(req, {Url = API_BASE .. "/alert", Method = "POST",
                        Headers = {["Content-Type"] = "application/json"}, Body = body})
        end
    end)
end

local function _antiDump()
    -- 1. Common dump-tool fingerprints in environment / globals
    local hits = {
        "Cobalt", "RemoteSpy", "Remote Spy", "Decompiler", "DEX Explorer",
        "saveinstance", "SaveInstance", "Dex.lua", "infyiff",
    }
    -- hookmetamethod identity
    if hookmetamethod then
        local s = tostring(hookmetamethod)
        for _, kw in ipairs(hits) do
            if s:find(kw, 1, true) then _abort("hookmetamethod_id", s) return false end
        end
    end
    -- caller source
    local ok, src = pcall(function() return debug.getinfo(2, "S").source end)
    if ok and type(src) == "string" then
        local low = src:lower()
        for _, kw in ipairs({"spy", "dump", "decompile", "saveinstance"}) do
            if low:find(kw, 1, true) then _abort("caller_source", src:sub(1, 200)) return false end
        end
    end
    -- getgc walking
    if getgc then
        local ok2, gc = pcall(getgc, true)
        if ok2 and type(gc) == "table" then
            for i = 1, math.min(#gc, 5000) do
                local v = gc[i]
                if type(v) == "string" and #v < 200 then
                    for _, kw in ipairs(hits) do
                        if v:find(kw, 1, true) then _abort("getgc_str", kw) return false end
                    end
                end
            end
        end
    end
    -- known dump-tool globals
    if rawget(_G, "saveinstance") or rawget(_G, "SaveInstance") then
        _abort("global_saveinstance"); return false
    end
    return true
end

if not _antiDump() then return end

-- ---------- HWID resolver ----------
local function _hwid()
    local cands = {}
    if gethwid then table.insert(cands, function() return gethwid() end) end
    if syn and syn.get_hwid then table.insert(cands, function() return syn.get_hwid() end) end
    if identifyexecutor then table.insert(cands, function()
        local n, v = identifyexecutor(); return tostring(n) .. "|" .. tostring(v)
    end) end
    table.insert(cands, function()
        return game:GetService("RbxAnalyticsService"):GetClientId()
    end)
    for _, fn in ipairs(cands) do
        local ok, v = pcall(fn)
        if ok and type(v) == "string" and #v >= 4 then return v end
    end
    return "fallback-" .. tostring(LP and LP.UserId or 0)
end

-- ---------- HTTP helpers ----------
local function _httpReq(url, method, body)
    local req = (syn and syn.request) or (http and http.request) or http_request
                or (fluxus and fluxus.request) or request
    if req then
        local ok, res = pcall(req, {
            Url = url, Method = method or "GET",
            Headers = {["Content-Type"] = "application/json"}, Body = body,
        })
        if ok and res and res.Body then return res.StatusCode or 0, res.Body end
    end
    -- fallback to Roblox HttpGet/HttpPost
    if method == "POST" then
        local ok, b = pcall(function() return HttpService:PostAsync(url, body or "", Enum.HttpContentType.ApplicationJson) end)
        if ok then return 200, b end
    else
        local ok, b = pcall(game.HttpGet, game, url)
        if ok then return 200, b end
    end
    return 0, nil
end

-- ---------- XOR decrypt (mirrors server side) ----------
local function _xorDecrypt(hex, key)
    -- key derived from sha256(token); we use a portable Lua sha256
    local function _band(a, b) return bit32 and bit32.band(a, b) or (a % 256) end
    local function _bxor(a, b) return bit32 and bit32.bxor(a, b) or (a % 256) end

    -- minimal sha256 (32-bit)
    local function sha256(msg)
        local k = {
            0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
            0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
            0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
            0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
            0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
            0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
            0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
            0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
        }
        local function rrot(x, n) return bit32.bor(bit32.rshift(x, n), bit32.lshift(x, 32 - n)) % 0x100000000 end
        local h = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
        local len = #msg
        msg = msg .. "\128"
        while #msg % 64 ~= 56 do msg = msg .. "\0" end
        local bits = len * 8
        for i = 7, 0, -1 do msg = msg .. string.char(math.floor(bits / 2^(i*8)) % 256) end
        for chunk = 1, #msg, 64 do
            local w = {}
            for i = 0, 15 do
                local p = chunk + i*4
                w[i+1] = msg:byte(p)*0x1000000 + msg:byte(p+1)*0x10000 + msg:byte(p+2)*0x100 + msg:byte(p+3)
            end
            for i = 17, 64 do
                local s0 = bit32.bxor(rrot(w[i-15], 7), rrot(w[i-15], 18), bit32.rshift(w[i-15], 3))
                local s1 = bit32.bxor(rrot(w[i-2], 17), rrot(w[i-2], 19), bit32.rshift(w[i-2], 10))
                w[i] = (w[i-16] + s0 + w[i-7] + s1) % 0x100000000
            end
            local a,b,c,d,e,f,g,hh = h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8]
            for i = 1, 64 do
                local S1 = bit32.bxor(rrot(e, 6), rrot(e, 11), rrot(e, 25))
                local ch = bit32.bxor(bit32.band(e, f), bit32.band(bit32.bnot(e) % 0x100000000, g))
                local t1 = (hh + S1 + ch + k[i] + w[i]) % 0x100000000
                local S0 = bit32.bxor(rrot(a, 2), rrot(a, 13), rrot(a, 22))
                local mj = bit32.bxor(bit32.band(a, b), bit32.band(a, c), bit32.band(b, c))
                local t2 = (S0 + mj) % 0x100000000
                hh,g,f,e,d,c,b,a = g, f, e, (d + t1) % 0x100000000, c, b, a, (t1 + t2) % 0x100000000
            end
            h[1]=(h[1]+a)%0x100000000; h[2]=(h[2]+b)%0x100000000; h[3]=(h[3]+c)%0x100000000; h[4]=(h[4]+d)%0x100000000
            h[5]=(h[5]+e)%0x100000000; h[6]=(h[6]+f)%0x100000000; h[7]=(h[7]+g)%0x100000000; h[8]=(h[8]+hh)%0x100000000
        end
        local out = {}
        for i = 1, 8 do
            for s = 24, 0, -8 do out[#out+1] = string.char(math.floor(h[i] / 2^s) % 256) end
        end
        return table.concat(out)
    end

    local keyBytes = sha256(key)
    local out = {}
    local n = #hex
    local idx = 1
    for i = 1, n, 2 do
        local b = tonumber(hex:sub(i, i+1), 16)
        if not b then return nil end
        local kb = string.byte(keyBytes, ((idx - 1) % #keyBytes) + 1)
        out[idx] = string.char(_bxor(b, kb))
        idx = idx + 1
    end
    return table.concat(out)
end

-- ---------- main ----------
local hwid = _hwid()
getgenv().__SIG_HWID = hwid

local authBody = HttpService:JSONEncode({
    userId   = LP.UserId,
    username = LP.Name,
    hwid     = hwid,
})

local code, body = _httpReq(API_BASE .. "/auth", "POST", authBody)
if code ~= 200 or not body then return end

local ok, parsed = pcall(function() return HttpService:JSONDecode(body) end)
if not ok or not parsed or not parsed.ok then return end

local token     = parsed.token
local watermark = parsed.watermark
getgenv().__SIG_WM    = watermark
getgenv().__SIG_TOKEN = token

-- expose runRemoteCmd for the payload (server-side rotated logic)
getgenv().runRemoteCmd = function(action)
    local b = HttpService:JSONEncode({ token = token, action = action })
    local c, r = _httpReq(API_BASE .. "/cmd", "POST", b)
    if c ~= 200 or not r then return false end
    local pok, pj = pcall(function() return HttpService:JSONDecode(r) end)
    if not pok or not pj or not pj.ok or not pj.snippet then return false end
    local plain = _xorDecrypt(pj.snippet, token)
    if not plain then return false end
    local fn, err = loadstring(plain)
    if not fn then return false end
    local rok, rres = pcall(fn)
    return rok and rres
end

-- expose heartbeat for the payload
getgenv().__SIG_HEARTBEAT = function()
    local c = _httpReq(API_BASE .. "/heartbeat?token=" .. token, "GET")
    return c == 200
end

-- fetch and run the encrypted payload
local pcode, pbody = _httpReq(API_BASE .. "/payload?token=" .. token, "GET")
if pcode ~= 200 or not pbody then return end
local plain = _xorDecrypt(pbody, token)
if not plain then return end

local fn, err = loadstring(plain)
if not fn then return end
local sok, serr = pcall(fn)
if not sok then
    pcall(function()
        local body = HttpService:JSONEncode({ token = token, detected = "payload_runtime", extra = tostring(serr):sub(1,200) })
        _httpReq(API_BASE .. "/alert", "POST", body)
    end)
end
