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

# Headless run of example/testsuite.collection: test/testsuite.ini swaps the
# bootstrap collection, so the built engine runs deftest and exits. Exits
# non-zero when deftest reports a failure or an error — usable as a CI gate.
# (Keep testsuite.ini free of comments; bob's settings parser rejects them.)
#
# BOB must match your editor's engine_sha1 (see README), and JAVA must be 25+ —
# the macOS editor bundles one, which is what the default picks up.
DEFOLD_APP  ?= /Applications/Defold.app
JAVA        ?= $(shell ls -d "$(DEFOLD_APP)"/Contents/Resources/packages/jdk-*/bin/java 2>/dev/null | tail -1)
BOB         ?= bob.jar
PLATFORM    ?= arm64-macos
TEST_BUNDLE ?= .testsuite-bundle
TEST_APP    ?= $(TEST_BUNDLE)/Colyseus Defold SDK.app/Contents/MacOS/ColyseusDefoldSDK

testsuite:
	"$(JAVA)" -jar "$(BOB)" --platform $(PLATFORM) --variant headless \
		--settings test/testsuite.ini --archive \
		resolve build bundle --bundle-output $(TEST_BUNDLE)
	"$(TEST_APP)"
