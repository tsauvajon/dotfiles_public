local get_cwd = ya.sync(function()
	return cx.active.current.cwd
end)

local function fail(message)
	ya.notify({
		title = "live-search",
		content = message,
		timeout = 5,
		level = "error",
	})
end

local function run(command, cwd)
	local permit = ui.hide()
	local command_with_path = [[PATH="$HOME/.nix-profile/bin:$PATH"; ]] .. command
	local child, spawn_err = Command("sh")
		:arg({ "-c", command_with_path })
		:cwd(tostring(cwd))
		:stdin(Command.INHERIT)
		:stdout(Command.PIPED)
		:stderr(Command.INHERIT)
		:spawn()

	if not child then
		permit:drop()
		return nil, "Failed to start search: " .. tostring(spawn_err)
	end

	local output, wait_err = child:wait_with_output()
	permit:drop()

	if not output then
		return nil, "Failed to read search output: " .. tostring(wait_err)
	end

	if output.status.code == 130 or output.status.code == 1 then
		return "", nil
	end

	if output.status.code ~= 0 then
		return nil, "Search exited with code " .. tostring(output.status.code)
	end

	return output.stdout:gsub("\n$", ""), nil
end

local function resolve(cwd, path)
	local url = Url(path)
	if url.is_absolute then
		return url
	end
	return cwd:join(url)
end

local function reveal_or_cd(cwd, path)
	if not path or path == "" then
		return
	end

	local url = resolve(cwd, path)
	local cha = fs.cha(url)
	if cha and cha.is_dir then
		ya.emit("cd", { url })
	else
		ya.emit("reveal", { url })
	end
end

local function file_search(cwd)
	return run([[
fd --hidden --exclude .git --color=never . |
fzf \
  --with-shell='/bin/sh -c' \
  --height=90% \
  --layout=reverse \
  --border \
  --prompt='files> ' \
  --preview='if [ -d {} ]; then eza -la --color=always --icons=always {} 2>/dev/null || ls -la {}; else bat --color=always --style=numbers --line-range=:200 {} 2>/dev/null; fi'
]], cwd)
end

local function content_search(cwd)
	return run([[
fzf \
  --with-shell='/bin/sh -c' \
  --height=90% \
  --layout=reverse \
  --border \
  --disabled \
  --delimiter=':' \
  --prompt='rg> ' \
  --preview='bat --color=always --style=numbers --highlight-line {2} {1} 2>/dev/null' \
  --preview-window='+{2}+3/2' \
  --bind='change:reload:if [ -z "$FZF_QUERY" ]; then printf ""; else rg --no-heading --line-number --column --smart-case -- "$FZF_QUERY"; fi || true'
]], cwd)
end

local function selected_content_path(selected)
	return selected:match("^(.-):%d+:%d+:") or selected
end

local function entry(_, job)
	local cwd = get_cwd()
	if cwd.scheme.is_virtual then
		return fail("Virtual filesystems are not supported")
	end

	local mode = job.args[1]
	local selected, err
	if mode == "files" then
		selected, err = file_search(cwd)
	elseif mode == "content" then
		selected, err = content_search(cwd)
	else
		return fail("Expected mode: files or content")
	end

	if err then
		return fail(err)
	end

	if mode == "content" then
		reveal_or_cd(cwd, selected_content_path(selected))
	else
		reveal_or_cd(cwd, selected)
	end
end

return {
	entry = entry,
	_test = {
		selected_content_path = selected_content_path,
	},
}
