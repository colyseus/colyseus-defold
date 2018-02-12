LUA     := lua
VERSION := $($(LUA) -e "m = require [[colyseus.client]]; print(m.VERSION)")
TARBALL := lua-colyseus-$(VERSION).tar.gz
REV     := 1

LUAVER  := 5.2
PREFIX  := /usr/local
DPREFIX := $(DESTDIR)$(PREFIX)
LIBDIR  := $(DPREFIX)/share/lua/$(LUAVER)
INSTALL := install


luacheck:
	luacheck --std=max --codes colyseus

testsuite:
	busted -v test/*.lua
