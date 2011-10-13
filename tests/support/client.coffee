log = console.log
fs = require 'fs'
url = require 'url'
request = require 'request'
jsdom = require 'jsdom'
io = require 'socket.io-client'

# socket.io-client is normally used in a browser, so it would normally send the
# 'connect.sid' cookie with it. Override it here to send it in our tests.
_req = io.util.request

class Client
  constructor: (arg) ->
    @cookies = {}
    if typeof arg is 'string'
      @url = arg
      @parsed = url.parse arg
      @protocol = @parsed.protocol or 'http:'
      @host = @parsed.hostname
      @port = @parsed.port or 80
    else
      @app = arg
      check = =>
        try
          @host = @app.address().address
          @port = @app.address().port
        catch err
          process.nextTick check
      check()

  request: (method = 'get', args...) ->
    for k, v of args
      switch typeof v
        when 'string' then path = v
        when 'object' then opts = v
        when 'function' then cb = v

    opts ?= {}
    opts.followRedirect ?= no
    opts.method ?= method
    opts.url = "http://#{@host}:#{@port}#{path}"
    opts.encoding ?= 'utf8'

    req = request opts, (err, res) =>
      if err and cb? then cb(err)
      else
        # Hacky cookie support...
        if res.headers?["set-cookie"]?[0]?
          [key, value] = res.headers?["set-cookie"]?[0]?.split?("; ")?[0]?.split?("=")
          if value?
            @cookies[key] = value
        
        if opts.dom?
          jsdom.env html: res.body, done: (err, window) ->
            if err and cb? then cb(err)
            else cb(null, res, window)
        else
          cb(null, res) if cb?
  
  get: (args...) -> @request 'get', args...
  post: (args...) -> @request 'post', args...
  put: (args...) -> @request 'put', args...
  del: (args...) -> @request 'delete', args...

  connect: ->
    io.util.request = (xdomain) =>
      xhr = _req xdomain
      if Object.keys(@cookies).length > 0
        cookieString = ("#{key}=#{value}" for key, value of @cookies).join("; ")
        console.log "Cookie: ", cookieString
        xhr.setRequestHeader "Cookie", cookieString
      xhr
    @socket = io.connect "http://#{@host}:#{@port}"
  on: -> @socket.on.apply @socket, arguments
  emit: -> @socket.emit.apply @socket, arguments

module.exports = (args...) ->
  c = new Client(args...)
  c.get.dom = (args...) ->
    for a in args
      if typeof a is 'object'
        found = yes
        a.dom = yes
    args.push dom: yes unless found
    c.get.apply c, args
  c