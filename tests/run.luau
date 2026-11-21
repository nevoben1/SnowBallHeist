--!strict
-- Run all pure-logic tests:  lune run tests/run
local process = require("@lune/process")
local TestKit = require("./TestKit")

local ok = TestKit.run({
	CarryCodec = require("./CarryCodec.spec"),
	Config = require("./Config.spec"),
	Format = require("./Format.spec"),
	Formulas = require("./Formulas.spec"),
	HeistRules = require("./HeistRules.spec"),
	Purchases = require("./Purchases.spec"),
})

process.exit(if ok then 0 else 1)
