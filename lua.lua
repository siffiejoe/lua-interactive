-- lua.lua - Lua 5.1 interpreter (lua.c) reimplemented in Lua.
--
-- WARNING: This is not completed but was quickly done just an experiment.
-- Fix omissions/bugs and test if you want to use this in production.
-- Particularly pay attention to error handling.
--
-- (c) David Manura, 2008-08
-- Licensed under the same terms as Lua itself.
-- Based on lua.c from Lua 5.1.3.
-- Improvements by Shmuel Zeigerman.

-- Variables analogous to those in luaconf.h
local LUA_INIT = "LUA_INIT"
local LUA_PROGNAME = "lua"
local LUA_PROMPT   = "> "
local LUA_PROMPT2  = ">> "
local function LUA_QL(x) return "'" .. x .. "'" end

-- Variables analogous to those in lua.h
local LUA_RELEASE   = "Lua 5.1.3"
local LUA_COPYRIGHT = "Copyright (C) 1994-2008 Lua.org, PUC-Rio"


-- Note: don't allow user scripts to change implementation.
-- Check for globals with "cat lua.lua | luac -p -l - | grep ETGLOBAL"
local _G = _G
local assert = assert
local collectgarbage = collectgarbage
local loadfile = loadfile
local loadstring = load
local pcall = pcall
local rawget = rawget
local select = select
local tostring = tostring
local type = type
local unpack = table.unpack
local xpcall = xpcall
local io_stderr = io.stderr
local io_stdout = io.stdout
local io_stdin = io.stdin
local string_format = string.format
local string_sub = string.sub
local os_getenv = os.getenv
local os_exit = os.exit
local require = require
local bci = require( "bci" )
local bci_getheader = bci.getheader
local bci_getlocal = bci.getlocal
local bci_getupvalue = bci.getupvalue
local debug = require( "debug" )
local db_getupvalue = debug.getupvalue
local db_upvaluejoin = debug.upvaluejoin
local tconcat = table.concat


local progname = LUA_PROGNAME

-- Use external functions, if available
local lua_stdin_is_tty = function() return true end
local setsignal = function() end

local function print_usage()
  io_stderr:write(string_format(
  "usage: %s [options] [script [args]].\n" ..
  "Available options are:\n" ..
  "  -e stat  execute string " .. LUA_QL("stat") .. "\n" ..
  "  -l name  require library " .. LUA_QL("name") .. "\n" ..
  "  -i       enter interactive mode after executing " ..
              LUA_QL("script") .. "\n" ..
  "  -v       show version information\n" ..
  "  --       stop handling options\n" ..
  "  -        execute stdin and stop handling options\n"
  ,
  progname))
  io_stderr:flush()
end

local function l_message (pname, msg)
  if pname then io_stderr:write(string_format("%s: ", pname)) end
  io_stderr:write(string_format("%s\n", msg))
  io_stderr:flush()
end

local function report(status, msg)
  if not status and msg ~= nil then
    msg = (type(msg) == 'string' or type(msg) == 'number') and tostring(msg)
          or "(error object is not a string)"
    l_message(progname, msg);
  end
  return status
end

local function tuple(...)
  return {n=select('#', ...), ...}
end

local function traceback (message)
  local tp = type(message)
  if tp ~= "string" and tp ~= "number" then return message end
  local debug = _G.debug
  if type(debug) ~= "table" then return message end
  local tb = debug.traceback
  if type(tb) ~= "function" then return message end
  return tb(message, 2)
end

local function docall(f, ...)
  local tp = {...}  -- no need in tuple (string arguments only)
  local F = function() return f(unpack(tp)) end
  setsignal(true)
  local result = tuple(xpcall(F, traceback))
  setsignal(false)
  -- force a complete garbage collection in case of errors
  if not result[1] then collectgarbage("collect") end
  return unpack(result, 1, result.n)
end

local function dofile(name)
  local f, msg = loadfile(name)
  if f then f, msg = docall(f) end
  return report(f, msg)
end

local function dostring(s, name)
  local f, msg = loadstring(s, name)
  if f then f, msg = docall(f) end
  return report(f, msg)
end

local function dolibrary (name)
  return report(docall(_G.require, name))
end

local function print_version()
  l_message(nil, LUA_RELEASE .. "  " .. LUA_COPYRIGHT)
end

local function getargs (argv, n)
  local arg = {}
  for i=1,#argv do arg[i - n] = argv[i] end
  if _G.arg then
    local i = 0
    while _G.arg[i] do
      arg[i - n] = _G.arg[i]
      i = i - 1
    end
  end
  return arg
end

--FIX? readline support
local history = {}
local function saveline(s)
--  if #s > 0 then
--    history[#history+1] = s
--  end
end


local function get_prompt (firstline)
  -- use rawget to play fine with require 'strict'
  local pmt = rawget(_G, firstline and "_PROMPT" or "_PROMPT2")
  local tp = type(pmt)
  if tp == "string" or tp == "number" then
    return tostring(pmt)
  end
  return firstline and LUA_PROMPT or LUA_PROMPT2
end


local function incomplete (msg)
  if msg then
    local ender = "<eof>"
    if string_sub(msg, -#ender) == ender then
      return true
    end
  end
  return false
end


local function funclocals (chunk)
  local names = {}
  local header = bci_getheader(chunk)
  for i = 1, header.upvalues do
    local name = bci_getupvalue(chunk, i)
    if not names[ name ] then
      names[ #names+1 ] = name
      names[ name ] = #names
    end
  end
  for i = 1, header.locals do
    local name = bci_getlocal(chunk, i)
    if name:sub( 1, 1 ) ~= "(" and not names[ name ] then
      names[ #names+1 ] = name
      names[ name ] = #names
    end
  end
  return names
end

local function make_list (f)
  local names = funclocals(f)
  local h = tconcat(names, ", ")
  return h
end

local function find_upvalue (f, name)
  local i = 1
  repeat
    local up_name = db_getupvalue(f, i)
    if up_name == name then
      return i
    end
    i = i + 1
  until up_name == nil
end


local function pushline (firstline)
  local prmt = get_prompt(firstline)
  io_stdout:write(prmt)
  io_stdout:flush()
  local b = io_stdin:read'*l'
  if not b then return end -- no input
  if firstline and string_sub(b, 1, 1) == '=' then
    return "return " .. string_sub(b, 2), true -- change '=' to `return'
  else
    return b
  end
end


local function loadline (lastlocals)
  local b, returns = pushline(true)
  if not b then return -1 end  -- no input
  local lnames = make_list(lastlocals)
  local f, msg
  while true do  -- repeat until gets a complete line
    local h = lnames ~= "" and "local "..lnames.."; " or ""
    f, msg = loadstring(h..b, "=stdin")
    if f then
      local nlnames = make_list(f)
      local common = "return (function("..lnames..
                     ") return function() _ENV=_ENV; "
      local nh = returns and nlnames or ""
      f = assert(loadstring(common..b..
                 "\nreturn function() return "..nlnames..
                 " end end end)()", b) or
                 loadstring(common.."return function() return "..nh..
                 " end, (function() _ENV=_ENV; "..b..
                 "\nend)() end end)()", b))()
      local i = 1
      repeat
        local name, val = db_getupvalue(lastlocals, i)
        if name then
          local n = find_upvalue(f, name)
          if n then
            db_upvaluejoin(f, n, lastlocals, i)
          end
          i = i + 1
        end
      until name == nil
    end
    if not incomplete(msg) then break end  -- cannot try to add lines?
    local b2 = pushline(false)
    if not b2 then -- no more input?
      return -1
    end
    b = b .. "\n" .. b2 -- join them
  end

  saveline(b)

  return f, msg
end


local function dotty ()
  local oldprogname = progname
  progname = nil
  local lastlocals = function() end
  while true do
    local result
    local status, msg = loadline(lastlocals)
    if status == -1 then break end
    if status then
      result = tuple(docall(status))
      status, msg = result[1], result[2]
    end
    report(status, msg)
    if status and result.n > 1 then
      lastlocals = result[2]
      if result.n > 2 then  -- any result to print?
        status, msg = pcall(_G.print, unpack(result, 3, result.n))
        if not status then
          l_message(progname, string_format(
              "error calling %s (%s)",
              LUA_QL("print"), msg))
        end
      end
    end
  end
  io_stdout:write"\n"
  io_stdout:flush()
  progname = oldprogname
end


local function handle_script(argv, n)
  _G.arg = getargs(argv, n)  -- collect arguments
  local fname = argv[n]
  if fname == "-" and argv[n-1] ~= "--" then
    fname = nil  -- stdin
  end
  local status, msg = loadfile(fname)
  if status then
    status, msg = docall(status, unpack(_G.arg))
  end
  return report(status, msg)
end


local function collectargs (argv, p)
  local i = 1
  while i <= #argv do
    if string_sub(argv[i], 1, 1) ~= '-' then  -- not an option?
      return i
    end
    local prefix = string_sub(argv[i], 1, 2)
    if prefix == '--' then
      if #argv[i] > 2 then return -1 end
      return argv[i+1] and i+1 or 0
    elseif prefix == '-' then
      return i
    elseif prefix == '-i' then
      if #argv[i] > 2 then return -1 end
      p.i = true
      p.v = true
    elseif prefix == '-v' then
      if #argv[i] > 2 then return -1 end
      p.v = true
    elseif prefix == '-e' then
      p.e = true
      if #argv[i] == 2 then
        i = i + 1
        if argv[i] == nil then return -1 end
      end
    elseif prefix == '-l' then
      if #argv[i] == 2 then
        i = i + 1
        if argv[i] == nil then return -1 end
      end
    else
      return -1  -- invalid option
    end
    i = i + 1
  end
  return 0
end


local function runargs(argv, n)
  local i = 1
  while i <= n do if argv[i] then
    assert(string_sub(argv[i], 1, 1) == '-')
    local c = string_sub(argv[i], 2, 2) -- option
    if c == 'e' then
      local chunk = string_sub(argv[i], 3)
      if chunk == '' then i = i + 1; chunk = argv[i] end
      assert(chunk)
      if not dostring(chunk, "=(command line)") then return false end
    elseif c == 'l' then
      local filename = string_sub(argv[i], 3)
      if filename == '' then i = i + 1; filename = argv[i] end
      assert(filename)
      if not dolibrary(filename) then return false end
    end
    i = i + 1
  end end
  return true
end


local function handle_luainit()
  local init = os_getenv(LUA_INIT)
  if init == nil then
    return  -- status OK
  elseif string_sub(init, 1, 1) == '@' then
    dofile(string_sub(init, 2))
  else
    dostring(init, "=" .. LUA_INIT)
  end
end


local import = _G.import
if import then
  lua_stdin_is_tty = import.lua_stdin_is_tty or lua_stdin_is_tty
  setsignal        = import.setsignal or setsignal
  LUA_RELEASE      = import.LUA_RELEASE or LUA_RELEASE
  LUA_COPYRIGHT    = import.LUA_COPYRIGHT or LUA_COPYRIGHT
  _G.import = nil
end

if _G.arg and _G.arg[0] and #_G.arg[0] > 0 then progname = _G.arg[0] end
local argv = {...}
handle_luainit()
local has = {i=false, v=false, e=false}
local script = collectargs(argv, has)
if script < 0 then -- invalid args?
  print_usage()
  os_exit(1)
end
if has.v then print_version() end
local status = runargs(argv, (script > 0) and script-1 or #argv)
if not status then os_exit(1) end
if script ~= 0 then
  status = handle_script(argv, script)
  if not status then os_exit(1) end
else
  _G.arg = nil
end
if has.i then
  dotty()
elseif script == 0 and not has.e and not has.v then
  if lua_stdin_is_tty() then
    print_version()
    dotty()
  else dofile(nil)  -- executes stdin as a file
  end
end

