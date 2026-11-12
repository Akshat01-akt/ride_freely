from fastapi import APIRouter, FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.api.v1 import admin, auth, bookings, customers, drivers, locations

app = FastAPI(title="Ride Freely")

@app.exception_handler(RequestValidationError)
async def validation_error_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    # Report what is wrong, never the submitted values (they can hold passwords or non-JSON floats like NaN).
    errors = [{"loc": list(e["loc"]), "msg": e["msg"], "type": e["type"]} for e in exc.errors()]
    return JSONResponse(status_code=422, content={"detail": errors})


api_router = APIRouter(prefix="/api/v1")


@api_router.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


api_router.include_router(admin.router)
api_router.include_router(auth.router)
api_router.include_router(bookings.router)
api_router.include_router(customers.router)
api_router.include_router(drivers.router)
api_router.include_router(locations.router)
app.include_router(api_router)
