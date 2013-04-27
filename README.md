#                           lua-interactive                          #

A Lua interpreter with support for locals in interactive mode

The default [Lua interpreter][1] loads each line as a separate chunk
(if syntactically possible) when in interactive mode. This has the
advantage of immediate feedback, but prevents locals defined on one
line to be used on the following lines.

This experimental adaption of David Manura's "[Lua interpreter in
Lua][2]" uses code generation and debugging techniques to make locals
from previous chunks/lines available.

  [1]:  http://www.lua.org/manual/5.2/manual.html#7
  [2]:  http://lua-users.org/wiki/LuaInterpreterInLua

##                           What You Need                          ##

This prototype only works for Lua 5.2 (it uses `debug.upvaluejoin`).
Additionally you will need [lbci][3] for Lua 5.2, which at this time
(2013/04/26) is not officially released. The preliminary [version][4]
floating around in the mailing list archives is sufficient.

  [3]:  http://www.tecgraf.puc-rio.br/~lhf/ftp/lua/#lbci
  [4]:  http://lua-users.org/lists/lua-l/2013-04/msg00664.html

##                  Features/Quirks (mostly quirks)                 ##

*   The original "Lua interpreter in Lua" was written for Lua 5.1. I
    only changed what was absolutely necessary, so you will probably
    find some remains, like e.g. the old version string.
*   A top-level `return` will close all locals. This was a) a lot
    easier to implement, and b) helps avoid hitting the upvalue limit
    if you start to paste lots of code into the interactive
    interpreter. That means, that if you want to paste your module
    code, you must omit the final return statement if you want to
    access the locals in the module later on. You can also use a
    `return` statement to reset the `_ENV` environment, in case you
    changed it earlier (e.g. via `module`). The special `=<expr>`
    syntax should work as expected without affecting/resetting any
    locals.
*   The code needs to compile each chunk multiple times and slice it
    using `string.*`, `lbci.*`, and `debug.*` functions, it also
    creates multiple closures for each chunk. Therefore, it will work
    (i.e. load/compile) slower and consume more memory than usual --
    this shouldn't be a problem in an interactive session, though.
*   If a single chunk (typically a line) defines locals and then
    throws an error, those locals will be gone as well. They will not
    show up in the following chunks!
*   There still are differences between interactive and
    non-interactive mode, e.g. the following will silently do
    different things in an interactive session than in normal mode:

        local a
        = 1

##                             Examples                             ##

One sample session using a shared upvalue and closures:

    > local a = 1
    > local function inc()
    >> a = a + 1
    >> print( a )
    >> end
    > local function dec()
    >> a = a - 1
    >> print( a )
    >> end
    > local a = 17
    > =a
    17
    > inc()
    2
    > inc()
    3
    > inc()
    4
    > dec()
    3
    > dec()
    2
    > =a
    17
    > =_ENV.a
    nil

Using the (deprecated) `module` function which modifies the `_ENV`
upvalue:

    > local module, print = module, print
    > module( "mymodule" )
    > =_G
    nil
    > function myprint()
    >> print( "hello world" )
    >> end
    > return
    > =_G     
    table: 0x16d65f0
    > local mm = require( "mymodule" )
    > =mm
    table: 0x16f0e10
    > mm.myprint()
    hello world

##                              License                             ##

The original "Lua interpreter in Lua" written by David Manura is
licensed under the MIT license (see comments in the source code), my
modifications are hereby placed in the public domain.

