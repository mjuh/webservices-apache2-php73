local socket = require("socket")
local udp = socket.udp()

udp:setpeername("8.8.8.8", 53)
public_ip, _, _ = udp:getsockname()
udp:close()