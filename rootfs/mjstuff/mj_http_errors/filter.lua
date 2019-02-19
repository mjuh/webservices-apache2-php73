local filter_table = ngx.shared.filter_table
local act = filter_table:get(ngx.var.remote_addr)

if not act then
  return
elseif act == 0 then
  local str_to_hash = ngx.var.remote_addr .. ngx.var.host .. "Pbyfblf"
  local cookie = ngx.md5(str_to_hash)
  if ngx.var.cookie_mj_anti_flood == cookie then
    return
  else
    ngx.header.content_type = "text/html"
    ngx.say(string.format("<html><head><title>Majordomo</title><meta http-equiv='Content-Type' content='text/html; charset=utf-8'><style type='text/css' >body {width:100%%; height:100%%;margin:0;}body * {font-family:Tahoma, Arial, Verdana; font-size:11px;color:#737373;}hr {width:600px; margin-left: 0px; margin-top: 20px;}h1 {font-family:Tahoma, Arial, Verdana; font-size:32px;color:#737373;}a.link {color:#034c7a;}</style></head><body><div style='margin-left:100px;margin-top:0px;height:100%%; position:relative;'>&nbsp;<div style='font-size:19px;margin:70px 0 35px 0;'><h1>С&nbsp;вашего IP адреса&nbsp; %s зафиксирован ряд подозрительных запросов.</h1><br/>Для входа на&nbsp;сайт нажмите, пожалуйста, кнопку&nbsp;&mdash; мы&nbsp;установим<br/> защитные cookie и&nbsp;переадресуем на&nbsp;сайт.<br/><br/><button onclick=\"var d=new Date();d.setTime(d.getTime()+(7*24*60*60*1000));var expires='expires='+d.toUTCString();document.cookie = 'mj_anti_flood=%s;'+expires;document.location.reload();\" style=\"width: 120px;height: 40px;\"><span style=\"font-size: medium;\">Я не робот</span></button></div>Если Вы владелец сайта, дополнительную информацию Вы можете узнать <br>по e-mail <a class='link' href='mailto:support@majordomo.ru'>support@majordomo.ru</a> <br></div></body></html>", ngx.var.remote_addr, cookie))
    ngx.exit(ngx.HTTP_OK)
  end
elseif act == 1 then
  ngx.exit(ngx.HTTP_FORBIDDEN)
elseif act == 2 then
  ngx.exit(444)
end