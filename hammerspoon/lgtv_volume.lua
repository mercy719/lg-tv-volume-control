-- Forward the keyboard volume keys to lgtv_volumed while the macOS sound output is an LG TV.
--
-- Usage in ~/.hammerspoon/init.lua:
--   require("lgtv_volume").start()                                  -- defaults
--   require("lgtv_volume").start({ deviceName = "LG TV", api = "http://127.0.0.1:18765/" })
local M = {}

local config = {
  deviceName = "LG TV",                  -- substring of the audio output device name
  api = "http://127.0.0.1:18765/",
  showVolume = false,                    -- flash the TV volume in an alert after each key press
}
local actions = { SOUND_UP = "up", SOUND_DOWN = "down", MUTE = "mute" }

M.hits = 0  -- diagnostics: `hs -c 'print(require("lgtv_volume").hits)'`

local function outputIsTV()
  local dev = hs.audiodevice.defaultOutputDevice()
  return dev ~= nil and dev:name():find(config.deviceName, 1, true) ~= nil
end

local function onKey(e)
  local k = e:systemKey()
  local action = k and actions[k.key]
  if not action or not outputIsTV() then return false end
  M.hits = M.hits + 1
  if k.down then
    hs.http.asyncGet(config.api .. action, nil, function(status, body)
      if status ~= 200 then
        hs.alert.show("LG TV volume failed (" .. tostring(status) .. ")")
      elseif config.showVolume then
        local ok, s = pcall(hs.json.decode, body)
        if ok and s then hs.alert.closeAll(); hs.alert.show(s.muted and "TV muted" or ("TV volume " .. tostring(s.volume)), 0.6) end
      end
    end)
  end
  return true -- swallow the key so macOS doesn't show its "cannot adjust volume" HUD
end

-- macOS silently kills event taps after sleep/wake and display/network changes while
-- isEnabled() keeps returning true, so the tap is rebuilt instead of just re-enabled.
local function buildTap()
  if M.tap then M.tap:stop() end
  M.tap = hs.eventtap.new({ hs.eventtap.event.types.systemDefined }, onKey):start()
end

-- Event-driven rebuilds wait for the system to settle and coalesce bursts
local rebuildTimer
local function scheduleRebuild()
  if rebuildTimer then rebuildTimer:stop() end
  rebuildTimer = hs.timer.doAfter(3, buildTap)
end

function M.start(opts)
  for k, v in pairs(opts or {}) do config[k] = v end
  buildTap()

  M.wakeWatcher = hs.caffeinate.watcher.new(function(ev)
    local w = hs.caffeinate.watcher
    if ev == w.systemDidWake or ev == w.screensDidWake or ev == w.screensDidUnlock then scheduleRebuild() end
  end):start()

  M.screenWatcher = hs.screen.watcher.new(scheduleRebuild):start()

  hs.audiodevice.watcher.setCallback(function(ev)
    if ev == "dOut" then scheduleRebuild() end
  end)
  hs.audiodevice.watcher.start()

  -- Safety nets: restart within 5s if explicitly disabled; unconditional rebuild every 10 min
  M.watchdog = hs.timer.doEvery(5, function()
    if not M.tap:isEnabled() then M.tap:start() end
  end)
  M.rebuilder = hs.timer.doEvery(600, buildTap)
  return M
end

return M
