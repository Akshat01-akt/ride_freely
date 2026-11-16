# Demo and daily commands

Run everything from the repository root (`ride_freely/`). Needs Docker and, for tests, the backend virtualenv (`backend/.venv`) and Flutter.

## 1. Start the website and API

```bash
docker compose up -d --build                 # db, redis, api, nginx
docker compose exec api alembic upgrade head # create or update tables (not automatic)
docker compose ps                            # all four should be Up / healthy
```

Open the admin site: **http://localhost/admin/**  (API docs are not exposed; the API lives at http://localhost/api/v1).

## 2. Create an admin and log in

```bash
docker compose exec -e ADMIN_PASSWORD='choose-a-password' api \
  python -m app.cli create-admin --phone +919000000001 --name "Demo Admin"
```

Use `--phone`, `--email`, or both (at least one), for example `--email ops@example.com`. Log in at http://localhost/admin/ with that mobile number or email and the password. Leave out `-e ADMIN_PASSWORD=...` and the command asks for the password instead.

## 3. Fill it with demo data

```bash
backend/.venv/bin/python scripts/seed_demo.py 'choose-a-password'
```

This creates demo drivers Ravi (waiting for review), Meera (approved and online), one driver who has not applied, and one customer. Demo accounts use mobile numbers `98111000xx` and password `demo-pass-123`.

A driver's location counts as live for 30 seconds. To keep Meera on the **Live map** for about 12 minutes:

```bash
T=$(curl -s localhost/api/v1/auth/driver/login -H 'content-type: application/json' \
  -d '{"identifier":"9811100002","password":"demo-pass-123"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
for i in $(seq 1 90); do
  curl -s -o /dev/null localhost/api/v1/locations/update -H "authorization: Bearer $T" -H 'content-type: application/json' \
    -d "{\"latitude\":$(python3 -c "print(12.9716+$i*0.0002)"),\"longitude\":77.5946,\"speed\":8}"
  sleep 8
done
```

## 4. What to try in the site

| Page | Try |
|------|-----|
| Dashboard | Stat tiles count up; click one to jump to the filtered list |
| Review queue | Open Ravi, approve both documents, then "Approve driver" |
| Drivers | Filter by approval, availability, "Needs to update details" |
| Driver detail | Send one answer back with a note, see the lifecycle timeline change to "Needs changes" |
| Forms | Add a required question to the driver form; approved drivers stay bookable and show "Needs to update" |
| Live map | Meera's dot moves; click it for details |
| Users, Bookings | Search by name, email or phone; open a booking |

## 5. Remove the demo data

```bash
docker compose exec db psql -U app_user -d driver_booking \
  -c "delete from users where phone like '+91981110000%' or phone = '+919000000001'"
```

(Cascades remove their profiles, documents and answers.)

## 6. Tests and checks

```bash
cd backend && source .venv/bin/activate && python -m pytest -q   # backend, 350 tests (needs the docker db and redis up)
cd .. && flutter analyze && flutter test                          # app, 276 tests
node --test docker/admin/js                                       # admin site helpers, 11 tests
```

## 7. Run the Flutter app against the local server

```bash
flutter run                                                       # picks a per-platform default server address
flutter run --dart-define=API_BASE_URL=http://<your-computer-ip>/api/v1   # for a physical phone on the same Wi-Fi
flutter run -t lib/main_preview.dart --dart-define=UI_PREVIEW=true        # screens with sample data, no server needed
```

## 8. Stop and reset

```bash
docker compose stop                 # stop, keep data
docker compose down                 # remove containers, keep data volumes
docker compose down -v              # also DELETE the database and uploads (cannot be undone)
```
