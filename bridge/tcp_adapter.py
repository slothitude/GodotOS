#!/usr/bin/env python3
"""
TCP Adapter for GodotOS Bridge
Proxies between GDScript's StreamPeerTCP and the Unix socket bridge server.
GDScript can't connect to Unix sockets, so we expose TCP on 127.0.0.1:47625.
"""

import asyncio
import json
import logging
import os
import struct

log = logging.getLogger("bridge")

TCP_HOST = "127.0.0.1"
TCP_PORT = 47625
UNIX_SOCKET = "/tmp/godotos_bridge.sock"


class TCPAdapter:
    """Accepts TCP connections and relays to the Unix socket."""

    def __init__(self):
        self._server: asyncio.Server | None = None

    async def _handle_tcp_client(
        self,
        tcp_reader: asyncio.StreamReader,
        tcp_writer: asyncio.StreamWriter,
    ):
        addr = tcp_writer.get_extra_info("peername")
        log.info(f"[TCP] Client connected from {addr}")

        # Connect to Unix socket
        try:
            unix_reader, unix_writer = await asyncio.open_unix_connection(UNIX_SOCKET)
        except Exception as e:
            log.error(f"[TCP] Cannot connect to Unix socket: {e}")
            tcp_writer.close()
            return

        async def tcp_to_unix():
            """Relay: TCP client → Unix socket → TCP client."""
            try:
                while True:
                    # Read length-prefixed message from TCP
                    header = await tcp_reader.readexactly(4)
                    length = struct.unpack("<I", header)[0]
                    if length > 10_000_000:
                        log.error(f"[TCP] Oversized message: {length}")
                        break
                    body = await tcp_reader.readexactly(length)

                    # Forward to Unix socket
                    unix_writer.write(header + body)
                    await unix_writer.drain()

                    # Read response from Unix socket
                    resp_header = await unix_reader.readexactly(4)
                    resp_length = struct.unpack("<I", resp_header)[0]
                    resp_body = await unix_reader.readexactly(resp_length)

                    # Send response back to TCP client
                    tcp_writer.write(resp_header + resp_body)
                    await tcp_writer.drain()

            except asyncio.IncompleteReadError:
                pass
            except Exception as e:
                log.debug(f"[TCP] tcp_to_unix error: {e}")
            finally:
                unix_writer.close()
                tcp_writer.close()

        task = asyncio.create_task(tcp_to_unix())
        try:
            await task
        finally:
            task.cancel()
            log.info(f"[TCP] Client {addr} disconnected")

    async def start(self):
        self._server = await asyncio.start_server(
            self._handle_tcp_client, TCP_HOST, TCP_PORT
        )
        log.info(f"TCP adapter listening on {TCP_HOST}:{TCP_PORT}")

        async with self._server:
            await self._server.serve_forever()


async def start_tcp_adapter():
    adapter = TCPAdapter()
    await adapter.start()
