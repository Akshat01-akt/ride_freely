"""Fills a local dev server with clearly labelled demo accounts so the admin site has something to show.

Usage: backend/.venv/bin/python scripts/seed_demo.py ADMIN_PASSWORD
Needs the stack running at http://localhost and an admin +919000000001 (see docs/demo-commands.md).
Creates: Ravi (applied, waiting for review), Meera (approved, online), one driver who has not applied, one customer.
All demo accounts use the password demo-pass-123 and mobile numbers 98111000xx. Safe to run once per database.
"""
import sys

import httpx

PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 64
c = httpx.Client(base_url="http://localhost/api/v1", timeout=20)


def signup(role: str, name: str, phone: str) -> dict:
    r = c.post(f"/auth/{role}/register", json={"full_name": name, "phone": phone, "password": "demo-pass-123"})
    r.raise_for_status()
    return {"Authorization": "Bearer " + r.json()["access_token"]}


def apply(h: dict, licence: str, years: str, rate: str) -> None:
    for key in ("LICENCE", "ID_PROOF"):
        c.post("/drivers/documents", headers=h, data={"doc_type": key}, files={"file": ("d.png", PNG, "image/png")}).raise_for_status()
    c.post("/drivers/application", headers=h, json={"answers": {"licence_number": licence, "experience_years": years, "hourly_rate": rate}}).raise_for_status()


admin_password = sys.argv[1]
ravi = signup("driver", "Demo Driver Ravi", "9811100001")
apply(ravi, "DL-DEMO-0001", "6", "180")
meera = signup("driver", "Demo Driver Meera", "9811100002")
apply(meera, "DL-DEMO-0002", "3", "150")
signup("driver", "Demo Driver Not Applied", "9811100003")
signup("customer", "Demo Customer Asha", "9811100004")

token = c.post("/auth/admin/login", json={"identifier": "+919000000001", "password": admin_password}).json()["access_token"]
admin = {"Authorization": f"Bearer {token}"}
for doc in c.get("/drivers/me", headers=meera).json()["application"]["documents"]:
    c.patch(f"/admin/documents/{doc['id']}", headers=admin, json={"status": "APPROVED"}).raise_for_status()
driver_id = next(d["id"] for d in c.get("/admin/drivers", headers=admin, params={"q": "Meera"}).json()["items"])
c.patch(f"/admin/drivers/{driver_id}/verification", headers=admin, json={"status": "APPROVED"}).raise_for_status()
c.patch("/drivers/availability", headers=meera, json={"status": "AVAILABLE"}).raise_for_status()
c.post("/locations/update", headers=meera, json={"latitude": 12.9716, "longitude": 77.5946}).raise_for_status()
print("Demo data ready. Meera is online (keep her on the map with the keep-alive command in docs/demo-commands.md).")
