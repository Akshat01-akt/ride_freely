from fastapi import APIRouter, FastAPI

from app.api.v1 import admin, auth, customers, drivers

app = FastAPI(title="Ride Freely")

api_router = APIRouter(prefix="/api/v1")


@api_router.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


api_router.include_router(admin.router)
api_router.include_router(auth.router)
api_router.include_router(customers.router)
api_router.include_router(drivers.router)
app.include_router(api_router)
