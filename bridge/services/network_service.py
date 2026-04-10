#!/usr/bin/env python3
"""Network service — ping, DNS lookup, HTTP fetch."""

import asyncio
import json
import socket
import urllib.request
import urllib.error
from typing import Any


class NetworkService:
    """Async network operations."""

    async def ping(self, host: str, count: int = 3, timeout: float = 2.0) -> dict:
        """Ping a host (TCP connect check, not ICMP)."""
        results = []
        port = 80
        for i in range(count):
            try:
                start = asyncio.get_event_loop().time()
                _, writer = await asyncio.wait_for(
                    asyncio.open_connection(host, port), timeout=timeout
                )
                elapsed = (asyncio.get_event_loop().time() - start) * 1000
                writer.close()
                await writer.wait_closed()
                results.append({"seq": i + 1, "time_ms": round(elapsed, 1)})
            except asyncio.TimeoutError:
                results.append({"seq": i + 1, "time_ms": None, "error": "timeout"})
            except Exception as e:
                results.append({"seq": i + 1, "time_ms": None, "error": str(e)})

        times = [r["time_ms"] for r in results if r.get("time_ms") is not None]
        return {
            "host": host,
            "results": results,
            "sent": count,
            "received": len(times),
            "avg_ms": round(sum(times) / len(times), 1) if times else None,
        }

    async def dns_lookup(self, hostname: str) -> dict:
        """Resolve a hostname."""
        try:
            addrs = await asyncio.get_event_loop().getaddrinfo(hostname, None)
            ips = list({addr[4][0] for addr in addrs})
            return {"hostname": hostname, "addresses": ips}
        except socket.gaierror as e:
            return {"error": f"DNS lookup failed: {e}"}

    async def fetch(self, url: str, method: str = "GET", headers: dict = None, timeout: float = 10.0) -> dict:
        """Fetch a URL and return the response."""
        def _fetch():
            try:
                req = urllib.request.Request(url, method=method)
                if headers:
                    for k, v in headers.items():
                        req.add_header(k, v)
                with urllib.request.urlopen(req, timeout=timeout) as resp:
                    body = resp.read().decode("utf-8", errors="replace")
                    return {
                        "status": resp.status,
                        "headers": dict(resp.headers),
                        "body": body[:50000],  # cap at 50KB
                        "size": len(body),
                    }
            except urllib.error.HTTPError as e:
                body = e.read().decode("utf-8", errors="replace") if e.fp else ""
                return {"status": e.code, "error": str(e), "body": body[:5000]}
            except Exception as e:
                return {"error": str(e)}

        return await asyncio.to_thread(_fetch)
