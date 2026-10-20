"""Keep a persistent connection to an LG webOS TV and expose volume control over local HTTP.

    lgtv_volumed.py pair  --tv 192.168.1.50     # one-time: accept the prompt on the TV
    lgtv_volumed.py serve --tv 192.168.1.50     # GET /up /down /mute /status on 127.0.0.1:18765
"""
import argparse, asyncio, json, logging, os
from bscpylgtv import WebOsClient

DEFAULT_KEY_FILE = "~/.local/share/lgtv-volumed/keys.sqlite"
DEFAULT_PORT = 18765
REASONS = {200: "OK", 404: "Not Found", 503: "Service Unavailable"}

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
log = logging.getLogger("lgtv")


class TV:
    def __init__(self, ip, key_file):
        self.ip = ip
        self.key_file = key_file
        self.client = None
        self.lock = asyncio.Lock()

    async def disconnect(self):
        if self.client is not None:
            try:
                await self.client.disconnect()
            except Exception:
                pass

    async def ensure_client(self):
        if self.client is not None and self.client.is_connected():
            return self.client
        await self.disconnect()
        self.client = await WebOsClient.create(self.ip, key_file_path=self.key_file, states=["muted", "volume"],
                                               timeout_connect=2, connect_retry_attempts=1)
        await self.client.connect()
        log.info("connected to TV %s", self.ip)
        return self.client

    async def run(self, cmd):
        async with self.lock:
            for attempt in (1, 2):
                try:
                    c = await self.ensure_client()
                    if cmd == "up":
                        await c.volume_up()
                    elif cmd == "down":
                        await c.volume_down()
                    elif cmd == "mute":
                        await c.set_mute(not c.muted)
                    elif cmd != "status":
                        return 404, {"error": "unknown command"}
                    return 200, {"volume": c.volume, "muted": c.muted}
                except Exception as e:
                    log.warning("%s failed (attempt %d): %r", cmd, attempt, e)
                    await self.disconnect()
            return 503, {"error": "tv unreachable"}


async def serve(tv, host, port):
    async def handle(reader, writer):
        try:
            line = (await reader.readline()).decode(errors="ignore")
            while (await reader.readline()) not in (b"\r\n", b"\n", b""):
                pass
            path = line.split(" ")[1] if line.count(" ") >= 2 else "/"
            status, body = await tv.run(path.strip("/"))
            payload = json.dumps(body).encode()
            writer.write(b"HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"
                         % (status, REASONS[status].encode(), len(payload)) + payload)
            await writer.drain()
        finally:
            writer.close()

    server = await asyncio.start_server(handle, host, port)
    log.info("listening on %s:%d", host, port)
    async with server:
        await server.serve_forever()


async def pair(ip, key_file):
    print("Connecting to %s - accept the pairing prompt on the TV screen..." % ip)
    client = await WebOsClient.create(ip, key_file_path=key_file, timeout_connect=10)
    await client.connect()
    print("Paired. Key saved to %s (volume=%s, muted=%s)" % (key_file, client.volume, client.muted))
    await client.disconnect()


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("command", choices=["serve", "pair"])
    p.add_argument("--tv", default=os.environ.get("LGTV_IP"), help="TV IP address (or env LGTV_IP)")
    p.add_argument("--key-file", default=os.environ.get("LGTV_KEY_FILE", DEFAULT_KEY_FILE))
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=int(os.environ.get("LGTV_PORT", DEFAULT_PORT)))
    args = p.parse_args()
    if not args.tv:
        p.error("TV IP is required (--tv or LGTV_IP)")
    key_file = os.path.expanduser(args.key_file)
    os.makedirs(os.path.dirname(key_file), exist_ok=True)

    if args.command == "pair":
        asyncio.run(pair(args.tv, key_file))
    else:
        asyncio.run(serve(TV(args.tv, key_file), args.host, args.port))


if __name__ == "__main__":
    main()
