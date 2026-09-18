local gpu = require("component").gpu
local event = require("event")
local computer = require("computer")

gpu.setResolution(40, 20)

-- Colors
local C_BG = 0x1a1a2e
local C_DISP = 0x000000
local C_DISP_TEXT = 0x00FF00
local C_HIST = 0x888888
local C_NUM = 0x333333
local C_OP = 0xFF8800
local C_FUNC = 0x0066CC
local C_EQ = 0x00AA00
local C_CLR = 0xFF0000
local C_EXIT = 0xAA0000
local C_WHITE = 0xFFFFFF

-- Display
local DISP_X, DISP_Y = 1, 2
local DISP_W, DISP_H = 10, 3
local HIST_Y = 1

-- Buttons
local BTN_X, BTN_Y = 1, 6
local BTN_W, BTN_H = 4, 2
local GAP = 1

-- State
local expression = ""
local history = ""
local lastAnswer = 0
local justCalculated = false

-- Math functions
local function factorial(n)
  if n < 0 then return 0 end
  if n == 0 or n == 1 then return 1 end
  if n > 20 then n = 20 end
  local r = 1
  for i = 2, n do r = r * i end
  return r
end

-- Tokenizer
local function tokenize(expr)
  local tokens = {}
  local i = 1
  local s = expr:gsub("%s+", "")
  while i <= #s do
    local c = s:sub(i, i)
    if c:match("%d") or c == "." then
      local num = ""
      while i <= #s and (s:sub(i,i):match("[%d.]")) do
        num = num .. s:sub(i,i)
        i = i + 1
      end
      table.insert(tokens, {type="num", value=tonumber(num)})
    elseif c:match("[%+%-%*/%^%(%)!,]") then
      table.insert(tokens, {type="op", value=c})
      i = i + 1
    elseif c:match("[%a_]") then
      local name = ""
      while i <= #s and s:sub(i,i):match("[%a_]") do
        name = name .. s:sub(i,i)
        i = i + 1
      end
      if name == "pi" then
        table.insert(tokens, {type="num", value=math.pi})
      elseif name == "e" then
        table.insert(tokens, {type="num", value=math.exp(1)})
      else
        table.insert(tokens, {type="func", value=name})
      end
    else
      i = i + 1
    end
  end
  return tokens
end

-- Parser
local Parser = {}
Parser.__index = Parser

function Parser.new(tokens)
  local p = setmetatable({}, Parser)
  p.tokens = tokens
  p.pos = 1
  return p
end

function Parser:peek()
  return self.tokens[self.pos]
end

function Parser:eat()
  local t = self.tokens[self.pos]
  self.pos = self.pos + 1
  return t
end

function Parser:parseExpr()
  return self:addSub()
end

function Parser:addSub()
  local left = self:mulDiv()
  while self:peek() and self:peek().type == "op" and (self:peek().value == "+" or self:peek().value == "-") do
    local op = self:eat().value
    local right = self:mulDiv()
    if op == "+" then left = left + right
    else left = left - right end
  end
  return left
end

function Parser:mulDiv()
  local left = self:power()
  while self:peek() and self:peek().type == "op" and (self:peek().value == "*" or self:peek().value == "/") do
    local op = self:eat().value
    local right = self:power()
    if op == "*" then left = left * right
    else
      if right == 0 then error("Div by zero") end
      left = left / right
    end
  end
  return left
end

function Parser:power()
  local base = self:unary()
  if self:peek() and self:peek().type == "op" and self:peek().value == "^" then
    self:eat()
    local exp = self:unary()
    base = base ^ exp
  end
  return base
end

function Parser:unary()
  if self:peek() and self:peek().type == "op" and self:peek().value == "-" then
    self:eat()
    return -self:postfix()
  elseif self:peek() and self:peek().type == "op" and self:peek().value == "+" then
    self:eat()
  end
  return self:postfix()
end

function Parser:postfix()
  local val = self:primary()
  while self:peek() and self:peek().type == "op" and self:peek().value == "!" do
    self:eat()
    val = factorial(math.floor(val))
  end
  return val
end

function Parser:primary()
  local t = self:peek()
  if not t then error("Unexpected end") end
  if t.type == "num" then
    self:eat()
    return t.value
  elseif t.type == "func" then
    self:eat()
    if not (self:peek() and self:peek().type == "op" and self:peek().value == "(") then
      error("Expected ( after " .. t.value)
    end
    self:eat()
    local arg = self:parseExpr()
    if not (self:peek() and self:peek().type == "op" and self:peek().value == ")") then
      error("Expected )")
    end
    self:eat()
    local name = t.value
    if name == "sin" then return math.sin(arg)
    elseif name == "cos" then return math.cos(arg)
    elseif name == "tan" then return math.tan(arg)
    elseif name == "sqrt" or name == "sqr" then return math.sqrt(arg)
    elseif name == "log" then return math.log10(arg)
    elseif name == "ln" then return math.log(arg)
    elseif name == "abs" then return math.abs(arg)
    elseif name == "exp" then return math.exp(arg)
    elseif name == "fact" then return factorial(math.floor(arg))
    else error("Unknown func: " .. name)
    end
  elseif t.type == "op" and t.value == "(" then
    self:eat()
    local val = self:parseExpr()
    if not (self:peek() and self:peek().type == "op" and self:peek().value == ")") then
      error("Expected )")
    end
    self:eat()
    return val
  else
    error("Unexpected: " .. tostring(t.value))
  end
end

local function evaluate(expr)
  if expr == "" then return 0 end
  local tokens = tokenize(expr)
  if #tokens == 0 then return 0 end
  local p = Parser.new(tokens)
  local result = p:parseExpr()
  return result
end

-- Buttons layout
local buttons = {
  {x=1, y=1, label="sin",  type="func", val="sin("},
  {x=2, y=1, label="cos",  type="func", val="cos("},
  {x=3, y=1, label="tan",  type="func", val="tan("},
  {x=4, y=1, label="log",  type="func", val="log("},
  {x=5, y=1, label="ln",   type="func", val="ln("},
  {x=1, y=2, label="sqrt", type="func", val="sqrt("},
  {x=2, y=2, label="x^2",  type="func", val="^2"},
  {x=3, y=2, label="x^y",  type="func", val="^"},
  {x=4, y=2, label="!",    type="func", val="!"},
  {x=5, y=2, label="pi",   type="func", val="pi"},
  {x=1, y=3, label="7",    type="num",  val="7"},
  {x=2, y=3, label="8",    type="num",  val="8"},
  {x=3, y=3, label="9",    type="num",  val="9"},
  {x=4, y=3, label="/",    type="op",   val="/"},
  {x=5, y=3, label="(",    type="op",   val="("},
  {x=1, y=4, label="4",    type="num",  val="4"},
  {x=2, y=4, label="5",    type="num",  val="5"},
  {x=3, y=4, label="6",    type="num",  val="6"},
  {x=4, y=4, label="*",    type="op",   val="*"},
  {x=5, y=4, label=")",    type="op",   val=")"},
  {x=1, y=5, label="1",    type="num",  val="1"},
  {x=2, y=5, label="2",    type="num",  val="2"},
  {x=3, y=5, label="3",    type="num",  val="3"},
  {x=4, y=5, label="-",    type="op",   val="-"},
  {x=5, y=5, label="e",    type="func", val="e"},
  {x=1, y=6, label="0",    type="num",  val="0"},
  {x=2, y=6, label=".",    type="num",  val="."},
  {x=3, y=6, label="ANS",  type="func", val="ans"},
  {x=4, y=6, label="+",    type="op",   val="+"},
  {x=5, y=6, label="C",    type="clr",  val="C"},
  {x=1, y=7, label="AC",   type="clr",  val="AC"},
  {x=2, y=7, label="=",    type="eq",   val="="},
  {x=3, y=7, label="EXIT", type="exit", val="EXIT"},
}

local function getButtonColor(btn)
  if btn.type == "num" then return C_NUM
  elseif btn.type == "op" then return C_OP
  elseif btn.type == "func" then return C_FUNC
  elseif btn.type == "eq" then return C_EQ
  elseif btn.type == "clr" then return C_CLR
  elseif btn.type == "exit" then return C_EXIT
  end
  return C_NUM
end

local function drawBackground()
  gpu.setBackground(C_BG)
  gpu.fill(1, 1, 40, 20, " ")
  gpu.setBackground(0x00AA00)
  gpu.fill(1, 19, 40, 1, " ")
  gpu.setBackground(0x008800)
  gpu.fill(1, 20, 40, 1, " ")
end

local function drawDisplay()
  gpu.setBackground(C_BG)
  gpu.fill(DISP_X, HIST_Y, DISP_W, 1, " ")
  gpu.setForeground(C_HIST)
  local histText = history
  if #histText > DISP_W then
    histText = histText:sub(#histText - DISP_W + 1)
  end
  gpu.set(DISP_X, HIST_Y, histText)
  
  gpu.setBackground(C_DISP)
  gpu.fill(DISP_X, DISP_Y, DISP_W, DISP_H, " ")
  gpu.setForeground(C_DISP_TEXT)
  
  local text = expression
  if text == "" then text = "0" end
  if #text > DISP_W * DISP_H then
    text = text:sub(#text - DISP_W * DISP_H + 1)
  end
  
  local lines = {}
  while #text > 0 do
    table.insert(lines, text:sub(1, DISP_W))
    text = text:sub(DISP_W + 1)
  end
  for i, line in ipairs(lines) do
    local ly = DISP_Y + DISP_H - i
    if ly >= DISP_Y then
      gpu.set(DISP_X, ly, line)
    end
  end
  
  gpu.setBackground(0x444444)
  gpu.fill(DISP_X - 1, DISP_Y - 1, DISP_W + 2, 1, " ")
  gpu.fill(DISP_X - 1, DISP_Y + DISP_H, DISP_W + 2, 1, " ")
  for y = DISP_Y, DISP_Y + DISP_H - 1 do
    gpu.set(DISP_X - 1, y, "|")
    gpu.set(DISP_X + DISP_W, y, "|")
  end
end

local function drawButtons()
  for _, btn in ipairs(buttons) do
    local px = BTN_X + (btn.x - 1) * (BTN_W + GAP)
    local py = BTN_Y + (btn.y - 1) * (BTN_H + GAP)
    local color = getButtonColor(btn)
    
    gpu.setBackground(color)
    gpu.fill(px, py, BTN_W, BTN_H, " ")
    
    gpu.setBackground(0xFFFFFF)
    gpu.fill(px, py, BTN_W, 1, " ")
    gpu.setBackground(color)
    
    gpu.setForeground(C_WHITE)
    local lbl = btn.label
    if #lbl > BTN_W then lbl = lbl:sub(1, BTN_W) end
    local lx = px + math.floor((BTN_W - #lbl) / 2)
    gpu.set(lx, py + 1, lbl)
  end
end

local function draw()
  drawBackground()
  drawDisplay()
  drawButtons()
end

local function findButton(x, y)
  for _, btn in ipairs(buttons) do
    local px = BTN_X + (btn.x - 1) * (BTN_W + GAP)
    local py = BTN_Y + (btn.y - 1) * (BTN_H + GAP)
    if x >= px and x < px + BTN_W and y >= py and y < py + BTN_H then
      return btn
    end
  end
  return nil
end

local function handleButton(btn)
  computer.beep(500, 0.05)
  
  if btn.type == "exit" then
    computer.beep(300, 0.2)
    os.exit()
    return
  end
  
  if btn.type == "clr" then
    if btn.val == "AC" then
      expression = ""
      history = ""
    else
      expression = ""
    end
    draw()
    return
  end
  
  if btn.type == "eq" then
    if expression == "" then return end
    history = expression .. " ="
    local ok, result = pcall(evaluate, expression)
    if ok then
      local rounded = math.floor(result * 1000000) / 1000000
      expression = tostring(rounded)
      lastAnswer = rounded
      computer.beep(800, 0.1)
    else
      expression = "Error"
      computer.beep(200, 0.3)
    end
    justCalculated = true
    draw()
    return
  end
  
  if btn.val == "ans" then
    if justCalculated then
      expression = ""
    end
    expression = expression .. tostring(lastAnswer)
    justCalculated = false
    draw()
    return
  end
  
  if justCalculated and btn.type == "num" then
    expression = ""
  end
  justCalculated = false
  expression = expression .. btn.val
  draw()
end

-- Main
draw()

while true do
  local ev = {event.pull(0.05)}
  if ev[1] == "touch" then
    local x, y = ev[3], ev[4]
    local btn = findButton(x, y)
    if btn then
      handleButton(btn)
    end
  elseif ev[1] == "key_down" then
    local key = ev[3]
    local ch = ev[4]
    if ch == "q" then os.exit()
    elseif ch == "c" then expression = ""; history = ""; draw()
    elseif ch == "=" or key == 28 then
      handleButton({type="eq", val="="})
    elseif ch == "." or ch:match("%d") then
      handleButton({type="num", val=ch})
    elseif ch == "+" or ch == "-" or ch == "*" or ch == "/" then
      handleButton({type="op", val=ch})
    elseif ch == "(" or ch == ")" then
      handleButton({type="op", val=ch})
    elseif ch == "^" then
      handleButton({type="func", val="^"})
    end
  end
end
