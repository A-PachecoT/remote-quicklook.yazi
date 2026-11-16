--- @since 25.5.31
-- remote-quicklook.yazi — Quick Look / Finder on your Mac for files on a remote box.
--
-- You run yazi on a Linux machine (over ssh, Eternal Terminal, mosh, a multiplexer)
-- but you are looking at it from a Mac. This plugin copies the hovered file to a
-- cache on the Mac over ssh and opens it there: `preview` = Quick Look,
-- `reveal` = Finder. See README.md for setup.

local M = {}

local state = ya.sync(function(st)
	local h = cx.active.current.hovered
	return {
		url = h and tostring(h.url) or nil,
		is_dir = h and h.cha.is_dir or false,
		host = st.host,
		cache = st.cache,
		max_mb = st.max_mb,
	}
end)

-- $1 mode, $2 host, $3 file, $4 cache dir (relative to the Mac's $HOME), $5 max MB
local SCRIPT = [[
set -eu
mode=$1 host=$2 file=$3 cache=$4 max=$5
size=$(wc -c < "$file")
[ "$size" -le $((max * 1024 * 1024)) ] || { echo "file over ${max} MB" >&2; exit 3; }
# One folder per source directory, so same-named files from different places don't collide.
sub=$(cd "$(dirname "$file")" && pwd | cksum | cut -d' ' -f1)
dest="$cache/$sub/$(basename "$file")"
q=$(printf "%s" "$dest" | sed "s/'/'\\\\''/g")
mac() { ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" "$@"; }
mac "mkdir -p \"\$(dirname '$q')\" && cat > '$q'" < "$file"
case $mode in
  preview) mac "cd ~ && (qlmanage -p '$q' >/dev/null 2>&1 &); sleep 0.3; osascript -e 'tell application \"System Events\" to set frontmost of process \"qlmanage\" to true' >/dev/null 2>&1 || true" ;;
  reveal)  mac "cd ~ && open -R '$q'" ;;
esac
]]

function M:setup(opts)
	opts = opts or {}
	self.host = opts.host
	self.cache = opts.cache or "Library/Caches/remote-quicklook"
	self.max_mb = opts.max_mb or 500
end

function M:entry(job)
	local mode = job.args[1] or "preview"
	if mode ~= "preview" and mode ~= "reveal" then
		return ya.notify { title = "remote-quicklook", content = "Unknown mode: " .. mode, timeout = 3, level = "error" }
	end

	local s = state()
	if not s.host then
		return ya.notify {
			title = "remote-quicklook",
			content = 'Set your Mac in init.lua: require("remote-quicklook"):setup { host = "you@mac" }',
			timeout = 5,
			level = "error",
		}
	end
	if not s.url or s.is_dir then
		return ya.notify { title = "remote-quicklook", content = "Hover a file", timeout = 2, level = "warn" }
	end

	ya.notify { title = "remote-quicklook", content = "Sending to " .. s.host .. "…", timeout = 1 }
	local out, err = Command("sh")
		:arg({ "-c", SCRIPT, "sh", mode, s.host, s.url, s.cache, tostring(s.max_mb) })
		:stdin(Command.NULL)
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()

	if not out then
		ya.notify { title = "remote-quicklook", content = "Cannot run sh: " .. tostring(err), timeout = 5, level = "error" }
	elseif not out.status.success then
		local msg = out.stderr ~= "" and out.stderr or ("exit " .. tostring(out.status.code))
		ya.notify { title = "remote-quicklook", content = msg, timeout = 5, level = "error" }
	end
end

return M
