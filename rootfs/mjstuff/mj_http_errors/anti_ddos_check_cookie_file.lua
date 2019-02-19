local salty_tears = 'Pbyfblf'
local str_to_hash = ngx.var.remote_addr .. ngx.var.host .. salty_tears
local cookie = ngx.md5(str_to_hash)
if ngx.var.cookie_mj_anti_flood == cookie then
	return
end
ngx.exec('/mj-anti-flood')