#!/usr/bin/env python3
"""Filesystem service — read/write/list/search files on the host OS."""

import asyncio
import os
import stat
from pathlib import Path
from typing import Any


class FSService:
    """Async filesystem operations using asyncio.to_thread."""

    async def read_file(self, path: str, encoding: str = "utf-8") -> dict:
        """Read a file's contents."""
        def _read():
            p = Path(path).expanduser().resolve()
            if not p.exists():
                raise FileNotFoundError(str(p))
            if p.is_dir():
                return {"path": str(p), "type": "directory", "entries": sorted([e.name for e in p.iterdir()])}
            return {"path": str(p), "content": p.read_text(encoding=encoding), "size": p.stat().st_size}

        result = await asyncio.to_thread(_read)
        return result

    async def write_file(self, path: str, content: str, encoding: str = "utf-8") -> dict:
        """Write content to a file, creating parent dirs as needed."""
        def _write():
            p = Path(path).expanduser().resolve()
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content, encoding=encoding)
            return {"path": str(p), "size": len(content)}

        return await asyncio.to_thread(_write)

    async def list_dir(self, path: str, recursive: bool = False) -> dict:
        """List directory contents."""
        def _list():
            p = Path(path).expanduser().resolve()
            if not p.is_dir():
                raise FileNotFoundError(f"Not a directory: {p}")
            entries = []
            for entry in sorted(p.iterdir()):
                st = entry.stat()
                entries.append({
                    "name": entry.name,
                    "path": str(entry),
                    "type": "directory" if entry.is_dir() else "file",
                    "size": st.st_size if entry.is_file() else 0,
                    "modified": st.st_mtime,
                })
            return {"path": str(p), "entries": entries, "count": len(entries)}

        return await asyncio.to_thread(_list)

    async def delete(self, path: str) -> dict:
        """Delete a file or empty directory."""
        def _delete():
            p = Path(path).expanduser().resolve()
            if not p.exists():
                raise FileNotFoundError(str(p))
            if p.is_dir():
                p.rmdir()  # only empty dirs
            else:
                p.unlink()
            return {"deleted": str(p)}

        return await asyncio.to_thread(_delete)

    async def stat(self, path: str) -> dict:
        """Get file/directory metadata."""
        def _stat():
            p = Path(path).expanduser().resolve()
            if not p.exists():
                raise FileNotFoundError(str(p))
            st = p.stat()
            return {
                "path": str(p),
                "name": p.name,
                "type": "directory" if p.is_dir() else "file",
                "size": st.st_size,
                "mode": stat.filemode(st.st_mode),
                "uid": st.st_uid,
                "gid": st.st_gid,
                "modified": st.st_mtime,
                "accessed": st.st_atime,
            }

        return await asyncio.to_thread(_stat)

    async def search(self, path: str, pattern: str, max_results: int = 100) -> dict:
        """Search for files matching a glob pattern."""
        def _search():
            p = Path(path).expanduser().resolve()
            matches = list(p.glob(pattern))[:max_results]
            return {
                "path": str(p),
                "pattern": pattern,
                "matches": [str(m) for m in matches],
                "count": len(matches),
            }

        return await asyncio.to_thread(_search)
