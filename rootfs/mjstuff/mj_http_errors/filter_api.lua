local filter_table = ngx.shared.filter_table
local method = ngx.req.get_method()
local act_map = {setCookie = 0, return403 = 1, connReset = 2}
local _, addr = ngx.var.uri:match("/(.-)/(.+)")
local auth_token = "w5iwLomy2okyHDFLUiTimSuk84VLtY70pfiI"

function valid_ip(ip)
  if not ip then
    return false
  end
  local chunks = {ip:match("(%d+)%.(%d+)%.(%d+)%.(%d+)")}
  if (#chunks == 4) then
    for _, v in pairs(chunks) do
      if (tonumber(v) < 0 or tonumber(v) > 255) then
        return false
      end
    end
      return true
  end
  return false
end

function valid_set_req(addr, action, ttl)
  local ttl = tonumber(ttl)
  if not ttl then
    return false, "ttl must be a number"
  end
  if ttl ~= math.floor(ttl) then
    return false, "ttl must be an integer"
  end
  if not act_map[action] then
    return false, "unknown action '" .. action .. "', value must be one of 'setCookie', 'return403' or 'connReset'"
  end
  if not valid_ip(addr) then
    return false, (addr or "empty string obviously") .. " is not an IP address"
  end
  if addr == public_ip then
    return false, addr .. " is my own IP!"
  end
  if addr == "127.0.0.1" then
    return false, "blocking localhost is not a good idea"
  end
  if addr == ngx.var.remote_addr then
    return false, "so, you are asking me to block your own address. are you sane?"
  end
  return true, nil
end

function auth_check(action, ttl)
  local ttl = tonumber(ttl)
  local req_auth_token = ngx.req.get_headers()["Authorization"]
  if ttl then
    if (ttl < 1 or ttl > 7200) and req_auth_token ~= auth_token then
      return false, "setting ttl above 7200 or 0 requires authorization"
    end
  end
  if action ~= "setCookie" and req_auth_token ~= auth_token then
    return false, "'" .. action .. "' action requires authorization"
  end
  return true, nil
end

function extract_set_val(line)
    local addr, ttl, action = line:match("(.-) (.-) (.-)\n")
    if not addr then
      addr, ttl = line:match("(.-) (.-)\n")
    end
    if not addr then
      addr = line:match("(.-)\n")
    end
    ttl = tonumber(ttl) or 600
    action = action or "setCookie"
    return {addr=addr, action=action, ttl=ttl}
end

function action_name(code)
  for k, v in pairs(act_map) do
    if v == code then
      return k
    end
  end
end


ngx.header.content_type = "text/plain"

if method == "GET" then
  local res = nil
  if addr then
    res = filter_table:get(addr)
  else
    res = filter_table:get_keys(0)
  end
  if type(res) == "table" then
    for _, addr in pairs(res) do
      ngx.say(addr .. " " .. action_name(filter_table:get(addr)))
    end
  elseif res then
    ngx.say(action_name(res))
  else
    ngx.status = ngx.HTTP_NOT_FOUND
  end
  ngx.exit(ngx.HTTP_OK)
elseif method == "DELETE" then
  if valid_ip(addr) then
    filter_table:delete(addr)
    ngx.log(ngx.WARN, addr .. " removed from filtering table")
  else
    ngx.status = ngx.HTTP_BAD_REQUEST
    ngx.say((addr or "empty string obviously") .. " is not an IP address")
  end
  ngx.exit(ngx.HTTP_OK)
elseif method == "PUT" then
  local args, _ = ngx.req.get_uri_args()
  local ttl = args["ttl"] or 600
  local action = args["action"] or "setCookie"
  local ok, err = valid_set_req(addr, action, ttl)
  local allow, reason = auth_check(action, ttl)
  if not ok then
    ngx.status = ngx.HTTP_BAD_REQUEST
    ngx.say(err)
  elseif not allow then
    ngx.status = ngx.HTTP_UNAUTHORIZED
    ngx.say(reason)
  else
    filter_table:set(addr, act_map[action], ttl)
    ngx.log(ngx.WARN, addr .. " added to filtering table for " .. ttl .. " seconds, action: " .. action)
  end
  ngx.exit(ngx.HTTP_OK)
elseif method == "POST" then
  ngx.req.read_body()
  local data = ngx.req.get_body_data()
  local num = 1
  for line in data:gmatch(".-\n") do
    local args = extract_set_val(line)
    local ok, err = valid_set_req(args["addr"], args["action"], args["ttl"])
    local allow, reason = auth_check(args["action"], args["ttl"])
    if not ok or not allow then
      if not ok and ngx.status ~= ngx.HTTP_BAD_REQUEST and ngx.status ~=  ngx.HTTP_UNAUTHORIZED then
        ngx.status = ngx.HTTP_BAD_REQUEST
      elseif not allow and ngx.status ~= ngx.HTTP_BAD_REQUEST and ngx.status ~=  ngx.HTTP_UNAUTHORIZED then
        ngx.status = ngx.HTTP_UNAUTHORIZED
      end
      ngx.say(err or reason .. " in line no. " .. num .. ": '" .. line:match("(.-)\n") .. "'")
    end
    num = num + 1
  end
  if ngx.status ~= ngx.HTTP_BAD_REQUEST then
    for line in data:gmatch(".-\n") do
      local args = extract_set_val(line)
      filter_table:set(args["addr"], act_map[args["action"]], args["ttl"])
      ngx.log(ngx.WARN, args["addr"] .. " added to filtering table for " .. args["ttl"] .. " seconds, action: " .. args["action"])
    end
  end
  ngx.exit(ngx.HTTP_OK)
else
  ngx.status = ngx.HTTP_NOT_ALLOWED
  ngx.say(method .. " is not allowed here")
  ngx.exit(ngx.HTTP_OK)
end
