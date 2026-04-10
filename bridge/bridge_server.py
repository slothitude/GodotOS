#!/usr/bin/env python3
"""
GodotOS Bridge Server
Runs as a background daemon. Godot connects via Unix socket.
Handles all Linux system operations — filesystem, processes, network, system info.

GodotOS → [Unix socket] → bridge_server.py → Linux
"""

import asyncio
import json
import os
import signal
import subprocess
import sys
import time
import logging
from pathlib import Path
from typing import Any

# Import service modules
from services.fs_service import FSService
from services.process_service import ProcessService
from services.system_service import SystemService
from services.network_service import NetworkService

SOCKET_PATH = "/tmp/godotos_bridge.sock"
LOG_PATH = os.path.expanduser("~/.local/share/godotos/bridge.log")
VERSION = "0.4.0"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [bridge] %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler(LOG_PATH),
        logging.StreamHandler(sys.stdout),
    ]
)
log = logging.getLogger("bridge")


class BridgeServer:
    def __init__(self):
        self.services = {
            "fs":      FSService(),
            "process": ProcessService(),
            "system":  SystemService(),
            "network": NetworkService(),
        }
        self._running = True
        self._connections: set[asyncio.StreamWriter] = set()

    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        self._connections.add(writer)
        addr = writer.get_extra_info("peername", "godot")
        log.info(f"Client connected: {addr}")

        try:
            while True:
                # Read length-prefixed JSON: [4-byte LE int][json bytes]
                header = await reader.readexactly(4)
                length = int.from_bytes(header, "little")
                if length > 10_000_000:  # 10MB sanity check
                    log.error(f"Oversized message: {length} bytes, closing")
                    break
                body = await reader.readexactly(length)
                command = json.loads(body.decode("utf-8"))
                response = await self._dispatch(command)
                self._send(writer, response)

        except asyncio.IncompleteReadError:
            log.info(f"Client disconnected")
        except Exception as e:
            log.error(f"Client error: {e}", exc_info=True)
        finally:
            self._connections.discard(writer)
            writer.close()

    async def _dispatch(self, command: dict) -> dict:
        cmd_id = command.get("id", "unknown")
        service_name = command.get("service", "")
        action = command.get("action", "")
        params = command.get("params", {})

        log.debug(f"[{cmd_id}] {service_name}.{action} params={list(params.keys())}")

        if service_name not in self.services:
            return {"id": cmd_id, "error": f"Unknown service: {service_name}"}

        try:
            service = self.services[service_name]
            handler = getattr(service, action, None)
            if not handler:
                return {"id": cmd_id, "error": f"Unknown action: {service_name}.{action}"}

            # All handlers are async
            result = await handler(**params)
            return {"id": cmd_id, "result": result}

        except PermissionError as e:
            return {"id": cmd_id, "error": f"Permission denied: {e}"}
        except FileNotFoundError as e:
            return {"id": cmd_id, "error": f"Not found: {e}"}
        except Exception as e:
            log.error(f"[{cmd_id}] Handler error: {e}", exc_info=True)
            return {"id": cmd_id, "error": str(e)}

    def _send(self, writer: asyncio.StreamWriter, data: dict) -> None:
        body = json.dumps(data).encode("utf-8")
        header = len(body).to_bytes(4, "little")
        writer.write(header + body)

    async def ping(self) -> None:
        """Periodic health ping — log alive status every 30s"""
        while self._running:
            await asyncio.sleep(30)
            log.debug(f"Bridge alive. Connections: {len(self._connections)}")

    async def start(self):
        # Remove stale socket
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)

        os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)

        server = await asyncio.start_unix_server(
            self.handle_client,
            path=SOCKET_PATH,
        )
        os.chmod(SOCKET_PATH, 0o600)  # owner only

        log.info(f"GodotOS Bridge v{VERSION} listening on {SOCKET_PATH}")

        asyncio.create_task(self.ping())

        async with server:
            await server.serve_forever()

    def shutdown(self):
        self._running = False
        for writer in self._connections:
            writer.close()
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)
        log.info("Bridge shutdown complete")


async def main():
    bridge = BridgeServer()

    loop = asyncio.get_event_loop()
    loop.add_signal_handler(signal.SIGTERM, bridge.shutdown)
    loop.add_signal_handler(signal.SIGINT, bridge.shutdown)

    # Start Unix socket server AND TCP adapter (for GDScript StreamPeerTCP)
    from tcp_adapter import start_tcp_adapter
    await asyncio.gather(
        bridge.start(),
        start_tcp_adapter(),
    )


if __name__ == "__main__":
    asyncio.run(main())
