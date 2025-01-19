-- Generated using ntangle.nvim
local M = {}
local client

local client_co

local send_queue = {}

local received_data = ""

function M.connect(port)
  local read_response = function()
    while true do
      local pos = received_data:find("\n")
      if pos then
        local line = received_data:sub(1,pos-1)
        received_data = received_data:sub(pos+1)
        return vim.json.decode(line)
      else
        coroutine.yield()
      end
    end
  end

  client_co = coroutine.create(function()
    while true do
      while #send_queue == 0 do
        coroutine.yield()
      end

      local to_send = send_queue[1]
      table.remove(send_queue, 1)

      local msg = {}
      msg.cmd = "execute"
      msg.data = to_send
      local data = vim.json.encode(msg)
      client:write(data .. "\n")

      local response = read_response()
      if response.status ~= "Done" then
        vim.api.nvim_echo({{response.status, "Error"}}, true, {})
      else
        vim.api.nvim_echo({{response.status, "Normal"}}, false, {})
      end

    end
  end)

  send_queue = {}

  received_data = ""

  coroutine.resume(client_co)

  client = vim.uv.new_tcp()
  client:connect("127.0.0.1", port, function(err)
    print("Connected.")
    assert(not err, err)
    client:read_start(vim.schedule_wrap(function(err, data)
      assert(not err, err)
      if data then
        received_data = received_data .. data

        coroutine.resume(client_co)
      else
        client:close()
        client = nil
      end
    end))
  end)

end

function M.send_code(name, lines)
  local msg = {}
  msg.name = name
  msg.lines = lines
  table.insert(send_queue, msg)
  if client_co and coroutine.status(client_co) == "suspended" then
    coroutine.resume(client_co)
  else
    vim.api.nvim_echo({{"Client not connected", "Error"}}, true, {})
  end

end

function M.try_connect(port)
  if not M.is_connected() then
    M.connect(port)
  end
end

function M.is_connected()
  if client then
    return true
  else
    return false
  end
end
function M.send_ntangle_v2()
	vim.api.nvim_echo({{"Sending.", "Normal"}}, false, {})
  local found, ntangle_inc = pcall(require, "ntangle-inc")
  assert(found)

  local buf = vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))

  local lnum = row-1
  local hl_elem = ntangle_inc.Tto_hl_elem(buf, lnum)

  if hl_elem and hl_elem.part then
  	hl_elem = hl_elem.part
  end
  local lines = {}
  if hl_elem then
  	local Tangle = require"vim.tangle"
  	local ll = Tangle.get_ll_from_buf(buf)
  	assert(ll)
  	local hl = Tangle.get_hl_from_ll(ll)
  	assert(hl)

  	lines = hl:getlines_all(hl_elem, lines)
  else
    return
  end


  M.send_code(hl_elem.name, lines)
end

function M.send_ntangle_visual_v2()
	vim.api.nvim_echo({{"Sending.", "Normal"}}, false, {})
  local _,slnum,_,_ = unpack(vim.fn.getpos("'<"))
  local _,elnum,_,_ = unpack(vim.fn.getpos("'>"))
  local buf = vim.api.nvim_get_current_buf()

  local found, ntangle_inc = pcall(require, "ntangle-inc")
  assert(found)

  local all_lines = {}
  for lnum=slnum-1,elnum-1 do
    local hl_elem = ntangle_inc.Tto_hl_elem(buf, lnum)

    local lines = {}
    if hl_elem then
    	local Tangle = require"vim.tangle"
    	local ll = Tangle.get_ll_from_buf(buf)
    	assert(ll)
    	local hl = Tangle.get_hl_from_ll(ll)
    	assert(hl)

    	lines = hl:getlines_all(hl_elem, lines)
    else
      return
    end

    for _, line in ipairs(lines) do
    	table.insert(all_lines, line)
    end
  end

  local lines = all_lines

  local name = "temp" .. tostring(os.time())
  M.send_code(name)
end

return M
