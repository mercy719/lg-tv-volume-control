# LG TV Volume Control

Use your Mac keyboard's volume keys (🔉 🔊 🔇) to control the **real volume of an LG webOS TV** when the TV is your Mac's display / sound output over HDMI.

[中文说明](#中文说明)

## Why

When a Mac outputs audio to a TV over HDMI, macOS can't change the volume — pressing the volume keys only shows a "🚫" HUD and you have to reach for the TV remote. This project:

- runs a tiny daemon (`lgtv_volumed.py`) that keeps a persistent websocket connection to the TV over your LAN (via [bscpylgtv](https://github.com/chros73/bscpylgtv)), so each key press takes effect almost instantly;
- uses a [Hammerspoon](https://www.hammerspoon.org/) event tap that intercepts the volume keys **only while the sound output device is the LG TV** and forwards them to the daemon. With other outputs (speakers, AirPods) the keys behave normally;
- runs a watchdog every 15 seconds. If the TV is reachable but the local API fails twice in a row, it restarts the daemon (with a five-minute cooldown). It leaves the daemon alone while the TV is off or unreachable.

```
volume key ─▶ Hammerspoon (output is "LG TV"?) ─▶ http://127.0.0.1:18765/up ─▶ lgtv_volumed ─ websocket ─▶ TV
```

## Requirements

- macOS, with [Hammerspoon](https://www.hammerspoon.org/) installed and granted Accessibility permission
- An LG webOS TV on the same network (tested on webOS 23), with *Settings → General → Devices → External Devices → TV On With Mobile* / *LG Connect Apps* enabled
- Preferably a fixed IP for the TV (DHCP reservation on your router)

## Install

```bash
git clone https://github.com/mercy719/lg-tv-volume-control.git
cd lg-tv-volume-control
./install.sh 192.168.1.50      # your TV's IP
```

During install a pairing prompt appears on the TV — accept it with the remote. The script then:

1. creates a venv in `~/.local/share/lgtv-volumed/` and installs `bscpylgtv`;
2. pairs with the TV and stores the key in `~/.local/share/lgtv-volumed/keys.sqlite`;
3. installs LaunchAgents (`io.github.lgtv-volumed` and `.watchdog`) that start the daemon and watchdog at login;
4. copies `lgtv_volume.lua` to `~/.hammerspoon/` and adds `require("lgtv_volume").start()` to `init.lua`.

Then reload the Hammerspoon config. macOS may ask to allow Python to access the local network — allow it.

## Configuration

Hammerspoon options:

```lua
require("lgtv_volume").start({
  deviceName = "LG TV",                 -- substring of the output device name (check Sound settings)
  api = "http://127.0.0.1:18765/",
  showVolume = true,                    -- show the TV volume in an alert after each press
})
```

Daemon options: `lgtv_volumed.py serve --tv IP [--port 18765] [--key-file PATH]` (or env `LGTV_IP`, `LGTV_PORT`, `LGTV_KEY_FILE`).

HTTP API (bound to 127.0.0.1 only): `GET /up`, `/down`, `/mute` (toggle), `/status` → `{"volume": 12, "muted": false}`. You can use it from anything else too, e.g. Raycast, Shortcuts or `curl`.

## Troubleshooting

- **`Errno 65 No route to host`** although the TV pings fine: the Python build may lack the macOS *Local Network* permission. Python from uv / pyenv / Homebrew is often silently blocked; the installer uses Apple's `/usr/bin/python3` for this reason. A long-running daemon can also get stuck with this error after network changes; the included watchdog restarts it when the TV itself is reachable.
- **`InvalidProxyMessage`**: `http_proxy`/`https_proxy` env vars are set in your shell. Run with `env -u http_proxy -u https_proxy -u all_proxy ...`. (The LaunchAgent doesn't inherit your shell env.)
- **Keys stop working after sleep / display change**: macOS silently disables event taps while `isEnabled()` still returns true. The module rebuilds the tap after wake, screen and audio-device changes, and every 10 minutes. If it still happens, reload Hammerspoon and check `hs -c 'print(require("lgtv_volume").hits)'` – the counter increases each time a volume key is intercepted.
- **`tv unreachable`**: check `~/Library/Logs/lgtv-volumed.log`, the TV's IP and that the TV is on. Watchdog restart events are recorded in `~/.local/share/lgtv-volumed/watchdog/watchdog.log`.

## Uninstall

```bash
./uninstall.sh
```

## License

MIT

---

## 中文说明

Mac 通过 HDMI 把 LG webOS 电视当显示器/音箱时，系统音量键是灰的（只弹一个 🚫）。这个小工具让键盘音量键直接调**电视本身的音量**：

- `lgtv_volumed.py`：常驻后台，通过局域网与电视保持 websocket 长连接，在 `127.0.0.1:18765` 提供 `/up` `/down` `/mute` `/status`，按键几乎无延迟；
- Hammerspoon 模块 `lgtv_volume.lua`：仅当声音输出设备是 LG 电视时拦截音量键并转发，切到其他音箱/耳机时按键行为不变；
- 看门狗每 15 秒检查一次：电视可达但本地接口连续两次异常时自动重启守护进程（5 分钟冷却），电视关机或离线时不干预。

安装：装好 Hammerspoon（授予辅助功能权限），然后

```bash
./install.sh <电视IP>
```

安装时电视上会弹出配对请求，用遥控器同意即可。建议在路由器上给电视绑定固定 IP。

常见问题：

- 能 ping 通电视但报 `Errno 65 No route to host`：可能是 Python 没有 macOS「本地网络」权限（uv / pyenv / Homebrew 的 Python 常被拦），安装脚本因此固定用系统自带的 `/usr/bin/python3`。常驻进程在网络变化后也可能卡住并持续报这个错误；内置看门狗会在电视实际可达时自动重启守护进程。
- 报 `InvalidProxyMessage`：终端里设置了 `http_proxy` 等代理变量，运行前 `env -u` 去掉即可。
- 看门狗的重启记录位于 `~/.local/share/lgtv-volumed/watchdog/watchdog.log`；守护进程自身的错误仍在 `~/Library/Logs/lgtv-volumed.log`。
- 睡眠唤醒、换显示器后音量键失效：macOS 会静默掐掉 event tap 且 `isEnabled()` 仍返回 true，模块已在唤醒、屏幕变化、输出设备变化后自动重建，并每 10 分钟兜底重建一次。
