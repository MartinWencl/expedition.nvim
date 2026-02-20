--- Busted test framework type stubs for lua-language-server
--- @meta

--- @class busted.AssertNegation
--- @field equals fun(unexpected: any, actual: any, message: string?)

--- @class busted.Assert
--- @field equals fun(expected: any, actual: any, message: string?)
--- @field same fun(expected: any, actual: any, message: string?)
--- @field truthy fun(value: any, message: string?)
--- @field is_true fun(value: any, message: string?)
--- @field is_false fun(value: any, message: string?)
--- @field is_nil fun(value: any, message: string?)
--- @field is_not_nil fun(value: any, message: string?)
--- @field is_string fun(value: any, message: string?)
--- @field is_table fun(value: any, message: string?)
--- @field is_not busted.AssertNegation
--- @field are busted.Assert
assert = {}

--- @param description string
--- @param func fun()
function describe(description, func) end

--- @param description string
--- @param func fun()
function it(description, func) end

--- @param func fun()
function before_each(func) end

--- @param func fun()
function after_each(func) end

--- @param func fun()
function setup(func) end

--- @param func fun()
function teardown(func) end

--- @param description string
function pending(description) end

spy = {}
stub = {}
mock = {}
