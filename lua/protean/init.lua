-- Generated using ntangle.nvim
local M = {}
local client

local client_co

local send_queue = {}

local received_data = ""

local server_handle

local anonymous_section_idx = 1

function M.connect(port, on_connected, on_not_connected, max_retries, filetype)
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

      local data = vim.json.encode(to_send)
      client:write(data .. "\n")

      local response = read_response()
      if response.status ~= "Done" then
        vim.api.nvim_echo({{response.status, "Error"}}, true, {})
      end

    end
  end)

  send_queue = {}

  received_data = ""

  coroutine.resume(client_co)

  local try_connect
  try_connect = function(num_retries)
    if num_retries > max_retries then
      if not on_not_connected then
        vim.api.nvim_echo({{"Could not connect to server", "Error"}}, true, {})
      else
        vim.schedule(function() on_not_connected() end)
      end
      return
    end

    client = vim.uv.new_tcp()
    client:connect("127.0.0.1", port, vim.schedule_wrap(function(err)
      if err then
        if client then
          client:close()
        end
        client = nil
        vim.defer_fn(function() try_connect(num_retries+1) end, 250*(num_retries+1))
        return
      end

      if on_connected then
        vim.schedule(function() on_connected() end)
      end
      client:read_start(vim.schedule_wrap(function(err, data)
        if err then
          vim.schedule(function()
            vim.api.nvim_echo({{err, "Error"}}, true, {})
          end)
        end
        if data then
          received_data = received_data .. data

          coroutine.resume(client_co)
        else
          client:close()
          client = nil
        end
      end))
    end))
  end

  try_connect(0)

end

function M.send_code(name, lines_lit)
  if name ~= "loop" then
    for section_name, lines in pairs(lines_lit) do
      if section_name ~= name then
        local msg = {}
        msg.cmd = "execute"
        msg.data = {}
        msg.data.name = section_name
        msg.data.lines = lines
        msg.data.execute = false
        table.insert(send_queue, msg)
        if client_co and coroutine.status(client_co) == "suspended" then
          coroutine.resume(client_co)
        else
          vim.api.nvim_echo({{"Client not connected", "Error"}}, true, {})
        end

      end
    end
  end

  local msg = {}
  msg.cmd = "execute"
  msg.data = {}
  msg.data.name = name
  msg.data.lines = lines_lit[name]
  msg.data.execute = true
  table.insert(send_queue, msg)
  if client_co and coroutine.status(client_co) == "suspended" then
    coroutine.resume(client_co)
  else
    vim.api.nvim_echo({{"Client not connected", "Error"}}, true, {})
  end

end

function M.try_connect(port, on_connected, filetype)
  if not M.is_connected() then
    M.connect(port, on_connected, function()
      local err
      local stdin = vim.uv.new_pipe()
      local stdout = vim.uv.new_pipe()
      local stderr = vim.uv.new_pipe()

      if filetype == 'python' then
        server_handle, err = vim.uv.spawn("python", {
          stdio = {stdin, stdout, stderr},
          args = {vim.g.protean_server},
          cwd = vim.fs.dirname(vim.g.protean_server),
        }, function(code, signal)
        end)

      elseif filetype == 'javascript' then
        server_handle, err = vim.uv.spawn("node", {
          stdio = {stdin, stdout, stderr},
          args = {vim.g.protean_js_server},
          cwd = vim.fs.dirname(vim.g.protean_js_server),
        }, function(code, signal)
        end)
      end
      stdout:read_start(function(err, data)
        assert(not err, err)
      end)

      stderr:read_start(function(err, data)
        assert(not err, err)
      end)


      M.connect(port, on_connected, nil, 5, filetype)
    end, 1, filetype)
  else
    if on_connected then
      on_connected()
    end
  end
end

function M.is_connected()
  if client then
    return true
  else
    return false
  end
end

function M.stop()
  if server_handle then
    server_handle:kill() 
    server_handle = nil
  end
end

function M.kill_loop()
  local msg = {}
  msg.cmd = "killLoop"
  table.insert(send_queue, msg)
  if client_co and coroutine.status(client_co) == "suspended" then
    coroutine.resume(client_co)
  else
    vim.api.nvim_echo({{"Client not connected", "Error"}}, true, {})
  end

end
function M.send_ntangle_v2()
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
  local section_name
  if hl_elem then
  	local Tangle = require"vim.tangle"
  	local ll = Tangle.get_ll_from_buf(buf)
  	assert(ll)
  	local hl = Tangle.get_hl_from_ll(ll)
  	assert(hl)

  	lines_lit = hl:getlines_all_lit(hl_elem)
  else
    return
  end


	local cur_hl_elem = ntangle_inc.Tto_hl_elem(buf, row-1)
	local cur_row = row
	while cur_hl_elem and cur_hl_elem.type ~= ntangle_inc.HL_ELEM_TYPE.SECTION_PART do
		cur_row = cur_row - 1
		cur_hl_elem = cur_hl_elem.prev
	end

	local start_row = cur_row+1

	local section_length = #lines_lit[hl_elem.name]

	vim.schedule(function()
		local ns = vim.api.nvim_create_namespace("")
		vim.api.nvim_set_hl(0, "SendNTPY", { reverse = true })
		for i=start_row,start_row+section_length-1 do
			vim.api.nvim_buf_add_highlight(buf, ns, "SendNTPY", i-1, 0, -1)
		end

		vim.defer_fn(function()
			vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

		end, 150)
	end)


  M.send_code(hl_elem.name, lines_lit)
end

function M.send_ntangle_visual_v2()
  local name = "temp_section_protean_" .. tostring(anonymous_section_idx)
	anonymous_section_idx = anonymous_section_idx + 1

  local _,slnum,_,_ = unpack(vim.fn.getpos("v"))
  local _,elnum,_,_ = unpack(vim.fn.getpos("."))
  if slnum > elnum then
  	slnum ,elnum = elnum ,slnum
  end
  local buf = vim.api.nvim_get_current_buf()

  local found, ntangle_inc = pcall(require, "ntangle-inc")
  assert(found)

  local all_lines = {}
  for lnum=slnum-1,elnum-1 do
    local hl_elem = ntangle_inc.Tto_hl_elem(buf, lnum)

    if hl_elem then
    	local Tangle = require"vim.tangle"
    	local ll = Tangle.get_ll_from_buf(buf)
    	assert(ll)
    	local hl = Tangle.get_hl_from_ll(ll)
    	assert(hl)

    	hl:getlines_single_lit(hl_elem, name, all_lines)
    else
      return
    end
  end


  M.send_code(name, all_lines)
end

function M.toggle_backend()
  local msg = {}
  msg.cmd = "toggleBackend"
  table.insert(send_queue, msg)
  if client_co and coroutine.status(client_co) == "suspended" then
    coroutine.resume(client_co)
  else
    vim.api.nvim_echo({{"Client not connected", "Error"}}, true, {})
  end

end
return M
