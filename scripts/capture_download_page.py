"""Captura a página de downloads em viewports CSS exatos via Chrome DevTools."""

import argparse
import asyncio
import base64
import json
import socket
import subprocess
import tempfile
import time
import urllib.request
from pathlib import Path

from websockets.asyncio.client import connect


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


async def capture(url: str, output: Path, width: int, height: int) -> tuple[int, int]:
    chrome = Path(r"C:\Program Files\Google\Chrome\Application\chrome.exe")
    port = free_port()
    with tempfile.TemporaryDirectory(prefix="ubs-rapida-chrome-") as profile:
        process = subprocess.Popen(
            [
                str(chrome),
                "--headless=new",
                "--disable-gpu",
                "--hide-scrollbars",
                "--no-first-run",
                "--remote-allow-origins=*",
                f"--remote-debugging-port={port}",
                f"--user-data-dir={profile}",
                "about:blank",
            ],
            creationflags=subprocess.CREATE_NO_WINDOW,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            targets = None
            for _ in range(50):
                try:
                    with urllib.request.urlopen(f"http://127.0.0.1:{port}/json", timeout=1) as response:
                        targets = json.load(response)
                    break
                except Exception:
                    time.sleep(0.1)
            if not targets:
                raise RuntimeError("Chrome DevTools não iniciou.")
            page = next(target for target in targets if target["type"] == "page")
            async with connect(page["webSocketDebuggerUrl"], origin="http://127.0.0.1") as ws:
                request_id = 0

                async def command(method: str, params: dict | None = None) -> dict:
                    nonlocal request_id
                    request_id += 1
                    current = request_id
                    await ws.send(json.dumps({"id": current, "method": method, "params": params or {}}))
                    while True:
                        message = json.loads(await ws.recv())
                        if message.get("id") == current:
                            if "error" in message:
                                raise RuntimeError(message["error"])
                            return message.get("result", {})

                await command("Page.enable")
                await command(
                    "Emulation.setDeviceMetricsOverride",
                    {
                        "width": width,
                        "height": height,
                        "deviceScaleFactor": 1,
                        "mobile": width <= 500,
                    },
                )
                await command("Page.navigate", {"url": url})
                await asyncio.sleep(1)
                await command(
                    "Runtime.evaluate",
                    {"expression": "document.fonts.ready", "awaitPromise": True},
                )
                metrics = await command("Page.getLayoutMetrics")
                content_height = int(metrics["cssContentSize"]["height"] + 0.999)
                shot = await command(
                    "Page.captureScreenshot",
                    {
                        "format": "png",
                        "captureBeyondViewport": True,
                        "clip": {
                            "x": 0,
                            "y": 0,
                            "width": width,
                            "height": content_height,
                            "scale": 1,
                        },
                    },
                )
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(base64.b64decode(shot["data"]))
                return width, content_height
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("url")
    parser.add_argument("output", type=Path)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, default=900)
    args = parser.parse_args()
    width, height = asyncio.run(capture(args.url, args.output, args.width, args.height))
    print(f"CAPTURE={args.output} CSS_WIDTH={width} CONTENT_HEIGHT={height}")


if __name__ == "__main__":
    main()
