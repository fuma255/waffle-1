local async = require 'async'
local paths = require 'waffle.paths'
local utils = require 'waffle.utils'

local fs = async.fs
local _jencode = async.json.encode
local http_codes = async.http.codes

local response = { templates = '' }

response.resend = function(other, handler)
   handler(other.body, other.headers, other.statusCode)
end

response.save = function()
   return {
      body = response.body,
      headers = response.headers,
      statusCode = response.statusCode
   }
end

response.send = function(content)
   response.handler(content, response.headers, response.statusCode)
   response.body = content
end

response.setHeader = function(name, value)
   response.headers[name] = value
   return response
end
response.header = response.setHeader

response.setStatus = function(status)
   response.statusCode = status
   return response
end
response.status = response.setStatus

response.location = function(url)
   return response.setHeader('Location', url)
end

response.redirect = function(url)
   response.setStatus(302).location(url).send('')
end

response.sendFile = function(path)
   local sockwrite = response.write
   local sockfinish = response.finish

   local statusCode = response.statusCode
   local reasonPhrase = http_codes[statusCode]
   local head = {
      string.format('HTTP/1.1 %s %s\r\n', statusCode, reasonPhrase)
   }
   local headers = response.headers
   headers['Date'] = os.date('!%a, %d %b %Y %H:%M:%S GMT')
   headers['Server'] = 'ASyNC'

   for key, value in pairs(headers) do
      if type(key) == 'number' then
         table.insert(head, value)
         table.insert(head, '\r\n')
      else
         local entry = string.format('%s: %s\r\n', key, value)
         table.insert(head, entry)
      end
   end

   table.insert(head, '\r\n')
   sockwrite(table.concat(head))

   local _close = function(fd)
      sockfinish()
      fs.close(fd)
   end

   fs.open(path, 'r', '666', function(fd)
      local length = fs.bufferSize
      local offset = 0
      local function read()
         fs.read(fd, length, offset, function(data, err)
            if data == nil or err ~= nil then
               _close(fd)
               return
            end

            local ld = #data
            if ld == 0 or ld > length then
               _close(fd)
               return
            end

            offset = offset + length
            sockwrite(data)
            read()
         end)
      end
      read()
   end)
end

response.render = function(path, args, folder)
   args = args or {}
   local templates = response.templates or folder or ''
   local fname = paths.add(templates, path)
   response.header('Content-Type', 'text/html')
   fs.readFile(fname, function(content)
      response.send(content % args)
   end)
end

response.htmlua = function(path, args, folder)
   args = args or {}
   local templates = response.templates or folder or ''
   local fname = paths.add(templates, path)
   response.header('Content-Type', 'text/html')
   render(fname, args, response.send)
end

response.json = function(content)
   response.header('Content-Type', 'application/json').send(_jencode(content))
end

response.cookie = {}

local _cookie_set = function(name, val, options)
   options = options or {}
   local path = options.path or '/'
   local expires = ''
   if options.expires ~= nil then
      local date = string.format('%s GMT',
         os.date("%a %b %d %Y %X", os.time() + options.expires))
      expires = string.format('expires=%s;', date)
   end
   if type(val) == 'table' then
      val = async.json.encode(val)
   end
   local cookie = string.format('%s=%s;%sPath=%s', name, val, expires, path)
   response.header('Set-Cookie', cookie)
end
response.cookie.set = _cookie_set

local _cookie_delete = function(name)
   local cstr = '%s=;expires=Thu, 01 Jan 1970 00:00:00 UTC;Path="/"'
   local cookie = string.format(cstr, name)
   response.header('Set-Cookie', cookie)
end
response.cookie.delete = _cookie_delete

response.cookie.clear = function(cookies)
   for name, val in pairs(cookies) do
      _cookie_delete(name)
   end
end

setmetatable(response.cookie, {
   __call = function(self, ...) _cookie_set(...) end
})

local _new_response = function(self, handler, socket)
   self.body = ''
   self.headers = {}
   self.statusCode = 200
   self.handler = handler
   self.write = socket.write
   self.finish = socket.close
   return self
end

return setmetatable(response, { __call = _new_response })