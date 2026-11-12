"""Command line tools: `python -m app.cli create-admin --phone +919000000001 --name "Ops"`."""

import argparse
import asyncio
import getpass
import os
import sys

from pydantic import ValidationError

from app.core.database import SessionLocal
from app.services.auth_service import PhoneAlreadyRegistered, create_admin


async def _create_admin(name: str, phone: str, password: str) -> int:
    async with SessionLocal() as session:
        try:
            await create_admin(session, name, phone, password)
        except PhoneAlreadyRegistered:
            print("That phone number is already registered.", file=sys.stderr)
            return 1
        except (ValueError, ValidationError) as exc:
            print(f"Invalid input: {exc}", file=sys.stderr)
            return 2
    print(f"Admin created for {phone}.")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="app.cli")
    sub = parser.add_subparsers(dest="command", required=True)
    admin = sub.add_parser("create-admin", help="Create an admin account")
    admin.add_argument("--phone", required=True)
    admin.add_argument("--name", required=True)
    args = parser.parse_args(argv)
    password = os.environ.get("ADMIN_PASSWORD") or getpass.getpass("Admin password (min 8 chars): ")
    return asyncio.run(_create_admin(args.name, args.phone, password))


if __name__ == "__main__":
    raise SystemExit(main())
