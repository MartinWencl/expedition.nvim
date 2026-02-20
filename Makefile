.PHONY: test test-file coverage lint check

test:
	busted

test-file:
	busted $(FILE)

coverage:
	busted --coverage --helper spec/coverage_helper.lua

lint:
	luacheck lua/ plugin/ spec/

check: lint test
