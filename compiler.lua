local compiler = {}
compiler.__index = compiler

compiler.op_table, compiler.env = { ["+"] = "+", ["-"] = "-", ["*"] = "*", ["/"] = "/", ["^"] = "^",["%"] ="%", ["++"] = "..", ["=="] = "==", ["!="] = "~=", [">"] = ">", ["<"] = "<", ["<="] = "<=", [">="] = ">=", ["and"] = "and", ["or"] = "or" },{}

compiler.init_code = [[
function pure(x) return function() return x end end
function _bind(v,f) return function() local val = v() if val == nil then return nil end return f(val)() end end
function cons(h,t) return {h,t} end
function car(l) return l[1] end
function cdr(l) return l[2] end
function _ls(...) local args,l = {...},nil for i = #args, 1, -1 do l = {args[i], l} end return l end
function totbl(l) local t = {} while l ~= nil do t[#t + 1], l = l[1], l[2] end return t end
function tols(t) return _ls(table.unpack(t)) end
function at(l,i) if i == 0 then return l[1] end return at(l[2],i - 1) end
function l_map(fun, li) local dummy = {nil, nil}; local cur = dummy while li do cur[2] = {fun(li[1]), nil}; cur, li = cur[2], li[2] end return dummy[2] end
function l_filter(pred, li) local dummy = {nil, nil}; local cur = dummy while li do if pred(li[1]) then cur[2] = {li[1], nil}; cur = cur[2] end; li = li[2] end return dummy[2] end
function l_foldl(fun, acc, li) while li do acc, li = fun(acc, li[1]), li[2] end return acc end
function l_rev(li) local rev = nil while li do rev, li = {li[1], rev}, li[2] end return rev end
function l_range(f,l,s) s = -(s or 1); local r = nil; for i = l,f,s do r = {i,r} end; return r end
function l_zip(l1, l2) local dummy = {nil, nil}; local cur = dummy; while l1 and l2 do cur[2] = {{l1[1], {l2[1], nil}}, nil}; cur, l1, l2 = cur[2], l1[2], l2[2] end; return dummy[2] end
function l_unzip(li) local d1, d2 = {nil, nil}, {nil, nil}; local c1, c2 = d1, d2; while li do c1[2], c2[2] = {li[1][1], nil}, {li[1][2][1], nil}; c1, c2, li = c1[2], c2[2], li[2] end; return {d1[2], {d2[2], nil}} end
function tblidx(l,i) return l[i] end
function _export(t,n,v) t[n] = v; return v end
function putStr(s) return function() print(tostring(s)) ; return s end end
function getLine() return function() return io.read() end end
function writeFile(p,c) return function() local f = io.open(p,'w'); f:write(c); f:close() end end
function appendFile(p,c) return function() local f = io.open(p,'a'); f:write(c); f:close() end end
function readFile(p) return function() local f = io.open(p,'r'); local c = f:read('*a'); f:close(); return c end end
function fcall(fun) return fun() end
]]

local function CompileError(msg, line, col, context) return { type = "CompileError", message = msg, line = line or "?", col = col or "?", context = context or "" } end
local function format_error(err, source)
  if type(err) == "table" and err.type == "CompileError" then
    local msg = string.format("Compile Error [Line %s, Col %s]: %s",  tostring(err.line), tostring(err.col), err.message)
    local lines = {}
    for l in (source .. "\n"):gmatch("(.-)\r?\n") do table.insert(lines, l) end
    local line_text = lines[err.line]
    if line_text then msg = msg .. "\n  Near: " .. line_text
      if type(err.col) == "number" and err.col > 0 then msg = msg .. "\n" .. string.rep(" ", 8 + err.col - 1) .. "^" end
    end
    return msg
  end
  return tostring(err)
end

function compiler.new() return setmetatable({}, compiler) end

function compiler:_tokenize(input)
  local tokens = {}
  local i = 1
  local line = 1
  local col = 1
  while i <= #input do
    local c = input:sub(i, i)
    if c == "\n" then
      line = line + 1
      col = 1
      i = i + 1
    elseif c:match("%s") then
      i = i + 1
      col = col + 1
    elseif c == '"' then
      local start = i
      local start_line, start_col = line, col
      local escaped = false
      i = i + 1
      col = col + 1
      while i <= #input do
        local char = input:sub(i, i)
        if escaped then escaped = false
        elseif char == "\\" then escaped = true
        elseif char == '"' then break
        elseif char == "\n" then line, col = line + 1, 0 end
        i = i + 1
        col = col + 1
      end
      if i > #input then error(CompileError("Unterminated string literal", start_line, start_col,  input:sub(start, math.min(start + 20, #input)))) end
      table.insert(tokens, { value = input:sub(start, i), line = start_line, col = start_col })
      i = i + 1
      col = col + 1
    elseif input:sub(i, i + 1) == "--" then
      local newline = input:find("\n", i)
      if newline then
        i = newline + 1
        line = line + 1
        col = 1
      else i = #input + 1 end
    elseif c:match('[\\:%(%)%[%]{}]') then
      table.insert(tokens, {value = c, line = line, col = col})
      i = i + 1
      col = col + 1
    else
      local start_col = col
      local j = input:find('[%s\\:%(%)%[%]{}]', i) or (#input + 1)
      local token = input:sub(i, j - 1)
      table.insert(tokens, {value = token, line = line, col = start_col})
      col = col + (j - i)
      i = j
    end
  end
  return tokens
end

local function peek(state)
  if state.ptr > #state.tokens then return nil end
  return state.tokens[state.ptr]
end
local function peek_value(state)
  local t = peek(state)
  return t and t.value or nil
end
local function consume(state)
  local t = peek(state)
  if t then state.ptr = state.ptr + 1 end
  return t
end
local function expect(state, expected, context)
  local t = peek(state)
  if not t then
    local last = state.tokens[#state.tokens]
    error(CompileError( "Unexpected end of input, expected '" .. expected .. "'", last and last.line or "EOF", last and last.col or "EOF", context or "" ))
  end
  if t.value ~= expected then error(CompileError( "Expected '" .. expected .. "' but got '" .. t.value .. "'", t.line, t.col, context or "" )) end
  consume(state)
  return t
end
local function at_end(state) return state.ptr > #state.tokens end

local function ASTLiteral(value, l, c) return {type="literal", value=value, line=l, col=c} end
local function ASTIdentifier(name, l, c) return {type="identifier", name=name, line=l, col=c} end
local function ASTCall(fn, args, l, c) return {type="call", fn=fn, args=args, line=l, col=c} end
local function ASTFunction(params, body, l, c) return {type="function", params=params, body=body, line=l, col=c} end
local function ASTLet(var, value, body) return {type="let", var=var, value=value, body=body} end
local function ASTOperator(op, left, right) return {type="operator", op=op, left=left, right=right} end
local function ASTFnDef(name, value) return {type="fndef", name=name, value=value} end
local function ASTIf(cond, thn, els) return {type="if", cond=cond, thn=thn, els=els} end

function compiler:_parse_atom(state)
  local t = peek(state)
  if not t then return nil end
  local tv = t.value
  if tv == "fn" then
    consume(state)
    local name_tok = peek(state)
    if not name_tok then error(CompileError("Expected function name after 'fn'", t.line, t.col)) end
    local name = name_tok.value
    consume(state)
    local rhs = self:_parse_expression(state, true)
    if not rhs then error(CompileError("Expected function body after 'fn " .. name .. "'", name_tok.line, name_tok.col)) end
    return ASTFnDef(name, rhs)
  elseif tv == "type" then
    consume(state)
    local name_tok = consume(state)
    if not name_tok then error(CompileError("Expected name after 'type'", t.line, t.col)) end
    local name = name_tok.value
    local params = {}
    while peek_value(state) ~= ":" do table.insert(params, consume(state).value) end
    expect(state, ":", "type signature")
    local ret = consume(state).value
    return { type = "typesig", name = name, params = params, ret = ret }
  elseif tv == "cast" then
    consume(state)
    local target_type = consume(state) 
    if not target_type then  error(CompileError("Expected target type string after 'cast'", t.line, t.col))  end
    local expr = self:_parse_expression(state, true)
    if not expr then  error(CompileError("Expected expression to cast", t.line, t.col))  end
    return { type = "cast", target = target_type.value, value = expr }
  elseif tv == "\\" then
    consume(state)
    local params = {}
    local params_start = peek(state)
    while peek_value(state) ~= ":" do
      local p = peek(state)
      if not p then error(CompileError("Expected ':' after lambda parameters",  params_start and params_start.line or t.line, params_start and params_start.col or t.col)) end
      table.insert(params, p.value)
      consume(state)
    end
    if #params == 0 then error(CompileError("Lambda must have at least one parameter", t.line, t.col)) end
    expect(state, ":", "lambda definition")
    local body = self:_parse_expression(state, true)
    if not body then error(CompileError("Expected lambda body after ':'", t.line, t.col)) end
    return ASTFunction(params, body,t.line,t.col)
  elseif tv == "let" then
    consume(state)
    local var_tok = peek(state)
    if not var_tok then error(CompileError("Expected variable name after 'let'", t.line, t.col)) end
    local var = var_tok.value
    consume(state)
    local val = self:_parse_expression(state, true)
    if not val then error(CompileError("Expected value after 'let " .. var .. "'", var_tok.line, var_tok.col)) end
    if peek_value(state) == ":" then consume(state) end
    local body = self:_parse_expression(state, true)
    if not body then error(CompileError("Expected body after 'let' binding", var_tok.line, var_tok.col)) end
    return ASTLet(var, val, body)
  elseif tv == "(" then
    local open_paren = consume(state)
    local next_t = peek_value(state)
    if not next_t then error(CompileError("Unexpected end of input inside parentheses", open_paren.line, open_paren.col)) end
    local node
    if self.op_table[next_t] then
      consume(state)
      local left = self:_parse_expression(state, true)
      if not left then error(CompileError("Expected left operand for operator '" .. next_t .. "'", open_paren.line, open_paren.col)) end
      local right = self:_parse_expression(state, true)
      if not right then error(CompileError("Expected right operand for operator '" .. next_t .. "'", open_paren.line, open_paren.col)) end
      node = ASTOperator(self.op_table[next_t], left, right)
    else
      node = self:_parse_expression(state, false)
      if not node then error(CompileError("Expected expression inside parentheses", open_paren.line, open_paren.col)) end
    end
    expect(state, ")", "closing parentheses")
    return node
  elseif tv == "if" then
    consume(state)
    local cond = self:_parse_expression(state, true)
    if not cond then error(CompileError("Expected condition after 'if'", t.line, t.col)) end
    local thn = self:_parse_expression(state, true)
    if not thn then error(CompileError("Expected then-branch after if condition", t.line, t.col)) end
    local els = self:_parse_expression(state, true)
    if not els then error(CompileError("Expected else-branch after then-branch", t.line, t.col)) end
    return ASTIf(cond, thn, els)
  elseif tv == "[" then
    local open_bracket = consume(state)
    local elements = {}
    while peek_value(state) ~= "]" do
      if at_end(state) then error(CompileError("Unclosed list - expected ']'", open_bracket.line, open_bracket.col)) end
      local elem = self:_parse_expression(state, true)
      if elem then table.insert(elements, elem)
      else error(CompileError("Expected expression in list", peek(state).line, peek(state).col)) end
    end
    expect(state, "]", "list")
    return ASTCall(ASTIdentifier("_ls"), elements,t.line,t.col)
  elseif tv == "{" then
    local open_brace = consume(state)
    local elements = {}
    while peek_value(state) ~= "}" do
      if at_end(state) then error(CompileError("Unclosed table - expected '}'", open_brace.line, open_brace.col)) end
      local elem = self:_parse_expression(state, true)
      if elem then table.insert(elements, elem) end
    end
    expect(state, "}", "table")
    return {type = "table", elements = elements}
  elseif tv == "do" then
    local do_tok = consume(state)
    if peek_value(state) == "[" then consume(state) end
    local function parse_do_chain()
      local token = peek_value(state)
      if not token then error(CompileError("Unexpected end in do-block", do_tok.line, do_tok.col)) end
      if token == "finish" then
        consume(state)
        return self:_parse_expression(state, true)
      end
      local var_tok = consume(state)
      local var_name = var_tok.value
      if peek_value(state) ~= "<-" then error(CompileError("Expected '<-' after variable in do-block", var_tok.line, var_tok.col)) end
      consume(state)
      local action = self:_parse_expression(state, true)
      if not action then error(CompileError("Expected action after '<-'", var_tok.line, var_tok.col)) end
      if peek_value(state) == ";" then consume(state) end
      local callback = ASTFunction({var_name}, parse_do_chain())
      return ASTCall(ASTIdentifier("_bind"), {action, callback},t.line,t.col)
    end
    local result = parse_do_chain()
    if peek_value(state) == "]" then consume(state) end
    return result
  elseif tv == "match" then
    local match_tok = consume(state)
    local targets = {}
    while not at_end(state) and peek_value(state) ~= "[" do table.insert(targets, self:_parse_expression(state, true)) end
    if #targets == 0 then error(CompileError("Match requires at least one target value", match_tok.line, match_tok.col)) end
    local has_bracket = false
    if peek_value(state) == "[" then
      consume(state)
      has_bracket = true
    end
    local first_case, last_case = nil, nil
    while not at_end(state) do
      if has_bracket and peek_value(state) == "]" then break end
      local patterns = {}
      while not at_end(state) and peek_value(state) ~= "=>" and peek_value(state) ~= "|" do
        local p = peek(state)
        table.insert(patterns, p.value)
        consume(state)
      end
      if #patterns ~= #targets then
        local p = peek(state)
        error(CompileError("Match case mismatch: expected " .. #targets .. " patterns, got " .. #patterns, p and p.line or match_tok.line, p and p.col or match_tok.col ))
      end
      local guard = nil
      if peek_value(state) == "|" then
        consume(state)
        guard = self:_parse_expression(state, true)
      end
      if peek_value(state) ~= "=>" then
        local p = peek(state)
        error(CompileError("Expected '=>' after patterns in match",  p and p.line or match_tok.line,  p and p.col or match_tok.col))
      end
      consume(state)
      local result = self:_parse_expression(state, true)
      if not result then error(CompileError("Expected result after '=>' in match case", match_tok.line, match_tok.col)) end
      local current_case = {patterns = patterns, guard = guard, result = result, next = nil}
      if not first_case then first_case = current_case
      else last_case.next = current_case end
      last_case = current_case
      if peek_value(state) == ";" then consume(state) end
    end
    if has_bracket then expect(state, "]", "match block") end
    return {type = "match", targets = targets, cases = first_case}
  elseif tv == ">>=" then
    consume(state)
    local box = self:_parse_expression(state, true)
    local fun = self:_parse_expression(state, true)
    return ASTCall(ASTIdentifier("_bind"), {box, fun},t.line,t.col)
  elseif tv == "module" then
    consume(state)
    local name_tok = peek(state)
    if not name_tok then error(CompileError("Expected module name after 'module'", t.line, t.col)) end
    consume(state)
    return {type="mdef", name=name_tok.value}
  elseif tv == "export" then
    consume(state)
    local mname_tok = peek(state)
    if not mname_tok then error(CompileError("Expected module name after 'export'", t.line, t.col)) end
    consume(state)
    local name_tok = peek(state)
    if not name_tok then error(CompileError("Expected export name", mname_tok.line, mname_tok.col)) end
    consume(state)
    local val = self:_parse_expression(state, true)
    if not val then error(CompileError("Expected value to export", name_tok.line, name_tok.col)) end
    return {type="export", mname=mname_tok.value, name=name_tok.value, value=val}
  elseif tv == "use" then
    consume(state)
    local path_tok = peek(state)
    if not path_tok then error(CompileError("Expected path after 'use'", t.line, t.col)) end
    consume(state)
    return {type="import", path=path_tok.value}
  elseif tv == "finish" then
    consume(state)
    local val = self:_parse_expression(state, true)
    return {type="ret", name=val}
  elseif tv == "paren" then
    consume(state)
    return { type="paren",body=self:_parse_expression(state,false)}
  else
    consume(state)
    if tonumber(tv) or tv == "true" or tv == "false" or tv == "nil" or tv:sub(1,1) == '"' then return ASTLiteral(tv,t.line,t.col) else return ASTIdentifier(tv,t.line,t.col) end
  end
end

function compiler:_parse_expression(state, no_call)
  local atom = self:_parse_atom(state)
  if not atom then return nil end
  if not no_call then
    local args = {}
    while not at_end(state) do
      local t = peek_value(state)
      if not t or t == ")" or t == "]" or t == "}" or t == ";" or  t == "fn" or t == "let" or t == "|>" or self.op_table[t] then break end
      local arg = self:_parse_expression(state, true)
      if arg then table.insert(args, arg) else break end
    end
    if #args > 0 then atom = ASTCall(atom, args,atom.line,atom.col) end
  end
  while peek_value(state) == "|>" do
  consume(state)
  local next_node = self:_parse_atom(state)
  if not next_node then  error(CompileError("Expected function after '>>'", state.tokens[state.ptr].line, state.tokens[state.ptr].col))  end
  local args = {}
  while not at_end(state) do
    local t = peek_value(state)
    if not t or t == ")" or t == "]" or t == "}" or t == ";" or t == "fn"  or t == "let" or t == "|>" or t == ">>=" or self.op_table[t] then  break  end
    local arg = self:_parse_expression(state, true)
    if arg then table.insert(args, arg) else break end
  end
  if #args > 0 then table.insert(args, atom); atom = ASTCall(next_node, args, next_node.line, next_node.col) else atom = ASTCall(next_node, {atom}, next_node.line, next_node.col) end
end
  return atom
end

function compiler:_ast_to_lua(node, is_tail)
  if not node then return "" end
  local t = node.type
  if t == "literal" then
    local code = node.value
    return is_tail and ("return " .. code) or code
  elseif t == "identifier" then
    local code = node.name
    return is_tail and ("return " .. code) or code
  elseif t == "function" then
    local params = table.concat(node.params, ", ")
    local body = self:_ast_to_lua(node.body, true)
    local code = "function(" .. params .. ") " .. body .. " end"
    return is_tail and ("return " .. code) or code
  elseif t == "let" then
    local val = self:_ast_to_lua(node.value, false)
    local body = self:_ast_to_lua(node.body, is_tail)
    if is_tail then return "local "..node.var.." ; local " .. node.var .. " = " .. val .. "; " .. body
    else return "((function(" .. node.var .. ") return " .. body .. " end)(" .. val .. "))" end
  elseif t == "call" then
    local fn_code = self:_ast_to_lua(node.fn, false)
    if node.fn.type == "function" or node.fn.type == "let" then fn_code = "(" .. fn_code .. ")" end
    local args = {}
    for _, a in ipairs(node.args) do table.insert(args, self:_ast_to_lua(a, false)) end
    local call_str = fn_code .. "(" .. table.concat(args, ", ") .. ")"
    return is_tail and ("return " .. call_str) or call_str
  elseif t == "cast" then
    return self:_ast_to_lua(node.value, is_tail)
  elseif t == "operator" then
    local left = self:_ast_to_lua(node.left, false)
    local right = self:_ast_to_lua(node.right, false)
    local code = "(" .. left .. " " .. node.op .. " " .. right .. ")"
    return is_tail and ("return " .. code) or code
  elseif t == "if" then
    local cond = self:_ast_to_lua(node.cond, false)
    local thn = self:_ast_to_lua(node.thn, false)
    local els = self:_ast_to_lua(node.els, false)
    if is_tail then return "if " .. cond .. " then " .. thn .. " else " .. els .. " end"
    else return "((function() if " .. cond .. " then return " .. thn .. " else return " .. els .. " end end)())" end
  elseif t == "table" then
    local parts = {}
    for _, el in ipairs(node.elements) do table.insert(parts, self:_ast_to_lua(el, false)) end
    local code = "{" .. table.concat(parts, ", ") .. "}"
    return is_tail and ("return " .. code) or code
  elseif t == "match" then
    local target_codes = {}
    for _, tgt in ipairs(node.targets) do table.insert(target_codes, self:_ast_to_lua(tgt, false)) end
    local targets_packed = "{" .. table.concat(target_codes, ", ") .. "}"
    local function gen_cases(case)
      if not case then return "error('match failure')" end
      local conds = {}
      local bindings = {}
      for i, pat in ipairs(case.patterns) do
        local is_wildcard = (pat == "_")
        local is_literal = tonumber(pat) or pat == "true" or pat == "false" or pat:sub(1,1) == '"'
        if is_literal then table.insert(conds, "_vals[" .. i .. "] == " .. pat)
        elseif not is_wildcard then table.insert(bindings, "local " .. pat .. " = _vals[" .. i .. "]") end
      end
      local cond_str = #conds > 0 and table.concat(conds, " and ") or "true"
      if case.guard then
        local g = self:_ast_to_lua(case.guard, false)
        if #bindings > 0 then g = "((function() " .. table.concat(bindings, "; ") .. "; return " .. g .. " end)())" end
        cond_str = cond_str .. " and " .. g
      end
      local res = self:_ast_to_lua(case.result, is_tail)
      local body = table.concat(bindings, "; ") .. (#bindings > 0 and "; " or "")
      if is_tail then body = body .. res
      else body = body .. "return " .. res end
      return "if " .. cond_str .. " then " .. body .. " else " .. gen_cases(case.next) .. " end"
    end
    if is_tail then
      return "local _vals = " .. targets_packed .. "; " .. gen_cases(node.cases)
    else
      return "((function(_vals) " .. gen_cases(node.cases) .. " end)(" .. targets_packed .. "))"
    end
  elseif t == "mdef" then
    return node.name.." = {}"
  elseif t == "export" then
    local val = self:_ast_to_lua(node.value, false)
    return "_export("..node.mname..",'" .. node.name .. "', " .. val .. ")"
  elseif t == "import" then
    return "require(" .. node.path .. ")"
  elseif t == "ret" then
    local vcode = self:_ast_to_lua(node.name, false)
    return "return "..vcode
  elseif t == "fndef" then
    local val = self:_ast_to_lua(node.value, false)
    return node.name .. " = " .. val
  elseif t == "paren" then
    return "( "..self:_ast_to_lua(node.body,is_tail).." )"
  else error("Unknown AST node type: " .. t) end
end

function compiler:_choke(asts)
  for _, node in ipairs(asts) do if node.type == "typesig" then self.env[node.name] = { params = node.params, ret = node.ret } end end
  local function find_pos(node) if type(node) == "table" and node.line then return node.line, node.col elseif type(node) == "string" then for _, tok in ipairs(self.tokens) do if tok.value == node then return tok.line, tok.col end end end; return "?", "?" end
  local function consistent(t1, t2)
    if t1 == "Any" or t2 == "Any" then return true end
    if type(t1) == "table" and type(t2) == "table" then
      if #t1.params ~= #t2.params then return false end
      return consistent(t1.ret, t2.ret)
    end
    return t1 == t2
  end
  local function verify(node, tenv)
    if not node or type(node) ~= "table" then return "Any" end
    local t = node.type
    if t == "cast" then
      return node.target:gsub('"', '')
    elseif t == "literal" then
      local val = node.value
      if tonumber(val) then return "N" end
      if val == "true" or val == "false" then return "B" end
      if val:sub(1,1) == '"' then return "S" end
      return "Any"
    elseif t == "identifier" then
      local ftype = tenv[node.name] or self.env[node.name]
      if ftype then return ftype end
      return "Any"
    elseif t == "fndef" then
      local sig = self.env[node.name]
      local new_tenv = {}
      for k, v in pairs(tenv) do new_tenv[k] = v end
      local res = verify(node.value, tenv)
      if sig then
        if node.value.type == "function" then
          if #node.value.params ~= #sig.params then error(CompileError(string.format("Type Error: '%s' defined with %d params, expected %d", node.name, #node.value.params, #sig.params),find_pos(node.name))) end
          for i, pname in ipairs(node.value.params) do new_tenv[pname] = sig.params[i] end
          local body_ret = verify(node.value.body, new_tenv)
          if not consistent(body_ret, sig.ret) then error(CompileError(string.format("Type Error: '%s' returns %s, but body evaluates to %s", node.name, sig.ret, body_ret),find_pos(node.name))) end
          return sig.ret
        elseif not consistent(res, sig) then error(CompileError("Type Error: Inconsistent definition", find_pos(node.name))) end
      end
      return res
    elseif t == "function" then
      local new_tenv,sig_params = {},{}
      for k, v in pairs(tenv) do new_tenv[k] = v end
      for _, p in ipairs(node.params) do new_tenv[p] = "Any"; table.insert(sig_params,"Any") end
      return { params = sig_params, ret = verify(node.body, new_tenv) }
    elseif t == "let" then
      local val_type = verify(node.value, tenv)
      local new_tenv = {}
      for k, v in pairs(tenv) do new_tenv[k] = v end
      new_tenv[node.var] = val_type
      return verify(node.body, new_tenv)
    elseif t == "call" then
      local sig = verify(node.fn, tenv)
      if type(sig) == "table" then
        if #node.args ~= #sig.params then error(CompileError(string.format("Type Error: Function expects %d args, got %d", #sig.params, #node.args),find_pos(node.fn))) end
        for i, arg in ipairs(node.args) do
          local expected = sig.params[i]
          local actual = verify(arg, tenv)
          if not consistent(actual, expected) then error(CompileError(string.format("Type Error: Arg %d expected %s, got %s", i, expected, actual),find_pos(node.fn))) end
        end
        return sig.ret
      end
      for _, arg in ipairs(node.args) do verify(arg, tenv) end
      return "Any"
    elseif t == "if" then
      local cond_t = verify(node.cond, tenv)
      if not consistent(cond_t, "B") then error(CompileError(string.format("Type Error: 'if' condition expected B, got %s", cond_t),find_pos("if"))) end
      local t1 = verify(node.thn, tenv)
      local t2 = verify(node.els, tenv)
      if t1 == t2 then return t1 end
      return "Any"
    elseif t == "operator" then
      local lt = verify(node.left, tenv)
      local rt = verify(node.right, tenv)
      local op = node.op
      if op == ".." then
        if not consistent(lt, "S") then  error(CompileError(string.format("Type Error: '++' expects S, got %s", lt), find_pos("++"))) end
        if not consistent(rt, "S") then  error(CompileError(string.format("Type Error: '++' expects S, got %s", rt), find_pos("++"))) end
        return "S"
      elseif op == "==" or op == "~=" or op == "<" or op == ">" or op == "<=" or op == ">=" then return "B"
      elseif op == "and" or op == "or" then return "B"
      else
        if not consistent(lt, "N") then  error(CompileError(string.format("Type Error: Math op expects N, got %s", lt), find_pos(op))) end
        if not consistent(rt, "N") then  error(CompileError(string.format("Type Error: Math op expects N, got %s", rt), find_pos(op))) end
        return "N"
      end
    elseif t == "match" then
      for _, tgt in ipairs(node.targets) do verify(tgt, tenv) end
      local case = node.cases
      local first_ret = nil
      while case do
        local case_tenv = {}
        for k, v in pairs(tenv) do case_tenv[k] = v end
        for i, pat in ipairs(case.patterns) do if pat ~= "_" then case_tenv[pat] = "Any" end end
        local res_t = verify(case.result, case_tenv)
        if not first_ret then first_ret = res_t end
        case = case.next
      end
      return first_ret or "Any"
    end
    return "Any"
  end
  for _, node in ipairs(asts) do verify(node, {}) end
end

function compiler:compile(input)
  self.tokens = self:_tokenize(input)
  local state = { tokens = self.tokens, ptr = 1, source = input }
  local success, result = pcall(function()
    local asts = {}
    while not at_end(state) do
      local ast = self:_parse_expression(state)
      if ast then table.insert(asts, ast) else break end
    end
    self:_choke(asts)
    local out = {}
    for _, a in ipairs(asts) do if a.type ~= "typesig" then table.insert(out, self:_ast_to_lua(a, false)) end end
    return table.concat(out, "\n")
  end)
  if not success then return nil, format_error(result, input) end
  return result, nil
end

return compiler