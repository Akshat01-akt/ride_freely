from pathlib import Path
from typing import Protocol

from fastapi.concurrency import run_in_threadpool

from app.core.config import get_settings


class FileStorage(Protocol):
    async def save(self, key: str, data: bytes) -> None: ...
    async def read(self, key: str) -> bytes: ...
    async def delete(self, key: str) -> None: ...


class LocalFileStorage:
    """Stores files under one directory. Keys are server-generated; anything escaping the root is refused."""

    def __init__(self, root: str | Path):
        self.root = Path(root).resolve()

    def _path(self, key: str) -> Path:
        path = (self.root / key).resolve()
        if self.root not in path.parents:
            raise ValueError("invalid storage key")
        return path

    async def save(self, key: str, data: bytes) -> None:
        path = self._path(key)

        def write() -> None:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

        await run_in_threadpool(write)

    async def read(self, key: str) -> bytes:
        return await run_in_threadpool(self._path(key).read_bytes)

    async def delete(self, key: str) -> None:
        await run_in_threadpool(lambda: self._path(key).unlink(missing_ok=True))


def get_storage() -> FileStorage:
    return LocalFileStorage(get_settings().upload_dir)
