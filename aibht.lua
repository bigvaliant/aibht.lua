--[[
Copyright (c) 2010-2013 Matthias Richter
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.
Except as contained in this notice, the name(s) of the above copyright holders
shall not be used in advertising or otherwise to promote the sale, use or
other dealings in this Software without prior written authorization.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
]]--

local function include_helper(to, from, seen)
	if from == nil then
		return to
	elseif type(from) ~= 'table' then
		return from
	elseif seen[from] then
		return seen[from]
	end

	seen[from] = to
	for k,v in pairs(from) do
		k = include_helper({}, k, seen) -- keys might also be tables
		if not to[k] then
			to[k] = include_helper({}, v, seen)
		end
	end
	return to
end

-- deeply copies `other' into `class'. keys in `other' that are already
-- defined in `class' are omitted
local function include(class, other)
	return (include_helper(class, other, {}))
end

-- returns a deep copy of `other'
local function clone(other)
	return (setmetatable(include({}, other), getmetatable(other)))
end

local function new(class)
	-- mixins
	local inc = class.__includes or {}
	if getmetatable(inc) then inc = {inc} end

	for _, other in ipairs(inc) do
		include(class, other)
	end

	-- class implementation
	class.__index = class
	class.init    = class.init    or class[1] or function() end
	class.include = class.include or include
	class.clone   = class.clone   or clone

	-- constructor call
	return (setmetatable(class, {__call = function(c, ...)
		local o = setmetatable({}, c)
		o:init(...)
		return o
	end}))
end

-- interface for cross class-system compatibility (see https://github.com/bartbes/Class-Commons).
if class_commons ~= false and not common then
	common = {}
	function common.class(name, prototype, parent)
		return new{__includes = {prototype, parent}}
	end
	function common.instance(class, ...)
		return (class(...))
	end
end


-- the module
local Class = setmetatable({new = new, include = include, clone = clone},
	{__call = function(_,...) return (new(...)) end})


--
--  BehaviourTree
--
--  Created by Tilmann Hars on 2012-07-12.
--  Copyright (c) 2012 Headchant. All rights reserved.
--

--local Class = require 'hump_class'

local READY = "ready"
local RUNNING = "running"
local FAILED = "failed"

-- 执行节点（Action）：叶节点，执行设定的动作，一般返回TRUE。
Action = Class({
    init = function(self, task)
        self.task = task
        self.completed = false
    end
})

function Action:update(creatureAI)
    if self.completed then return READY end
    self.completed = self.task(creatureAI)
    return RUNNING
end

-- 条件节点（Condition）：叶节点，执行条件判断，返回判断结果。
Condition = Class({
    init = function(self, condition)
        self.condition = condition
    end
})

function Condition:update(creatureAI)
    return (self.condition(creatureAI) and READY or FAILED)
end

-- 选择节点（Selector）：组合节点，顺序执行子节点，只要碰到一个子节点返回TRUE，则返回TRUE；否则返回FALSE。
Selector = Class({
    init = function(self, children)
        self.children = children
    end
})

-- creatureAI -> self
function Selector:update(creatureAI)
    for _, v in ipairs(self.children) do
        local status = v:update(creatureAI)
        if status == RUNNING then
            return RUNNING
        elseif status == READY then
            if i == #self.children then
                self:resetChildren()
            end
            return READY
        end
    end
    return FAILED
end

function Selector:resetChildren()
    for _, vv in ipairs(self.children) do
        vv.completed = false
    end
end

-- 顺序节点（Sequence）：组合节点，顺序执行子节点，只要碰到一个子节点返回FALSE，则返回FALSE；否则返回TRUE。
Sequence = Class({
    init = function(self, children)
        self.children = children
        self.last = nil
        self.completed = false
    end
})

function Sequence:update(creatureAI)
    if self.completed then return READY end

    local last = 1

    if self.last and self.last ~= #self.children then
        last = self.last + 1
    end

    for i = last, #self.children do
        local v = self.children[i]:update(creatureAI)
        self.last = i
        if v == FAILED then
            self.last = nil
            self:resetChildren()
            return FAILED
        elseif i == #self.children then
            self.last = nil
            self:resetChildren()
            self.completed = true
            return v
        end
    end
end

function Sequence:resetChildren()
    for _, vv in ipairs(self.children) do
        vv.completed = false
    end
end

---------------------------------------------------------------------------
-- Example

local RAND_COND = function() return math.random(1, 6) > 3 end
--local FALSE = function() return false end
--local TRUE = function() return true end

local isThiefFarFromTreasure = Condition(RAND_COND)
local stillStrongEnoughToCarryTreasure = Condition(RAND_COND)

local makeThiefFlee = Action(function() print("making the thief flee") return false end)
local chooseCastle = Action(function() print("choosing Castle") return true end)
local flyToCastle = Action(function() print("fly to Castle") return true end)
local fightAndEatGuards = Action(function() print("fighting and eating guards") return true end)
local takeGold = Action(function() print("picking up gold") return true end)
local flyHome = Action(function() print("flying home") return true end)
local putTreasureAway = Action(function() print("putting treasure away") return true end)
local postPicturesOfTreasureOnFacebook = Action(function()
    print("posting pics on facebook")
    return true
end)

-- testing subtree
local packStuffAndGoHome = Selector {
    Sequence {
        stillStrongEnoughToCarryTreasure,
        takeGold,
        flyHome,
        putTreasureAway,
    }
}

local simpleBehaviour = Sequence {
    Selector {
        Sequence {
            isThiefFarFromTreasure,
            makeThiefFlee,
        },
        Sequence {
            chooseCastle,
            flyToCastle,
            fightAndEatGuards,
            packStuffAndGoHome,
        }
    },
    postPicturesOfTreasureOnFacebook,
}

function exampleLoop()
    math.randomseed(os.time())
    for _ = 1, 20 do
        simpleBehaviour:update()
    end
end

exampleLoop()
