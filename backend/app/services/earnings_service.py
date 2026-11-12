import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.booking import Booking, BookingStatus

# The product runs in India, so "today", "this week" and "this month" mean India time.
IST = ZoneInfo("Asia/Kolkata")


def period_starts(now: datetime) -> dict[str, datetime | None]:
    local = now.astimezone(IST)
    midnight = local.replace(hour=0, minute=0, second=0, microsecond=0)
    return {
        "today": midnight,
        "week": midnight - timedelta(days=midnight.weekday()),  # Monday
        "month": midnight.replace(day=1),
        "total": None,
    }


async def driver_earnings(session: AsyncSession, driver_id: uuid.UUID) -> dict[str, dict]:
    """Completed-trip counts and booking totals for this driver. Totals are booking prices, not payouts."""
    starts = period_starts(datetime.now(UTC))
    columns = []
    for name, start in starts.items():
        cond = Booking.completed_at >= start if start is not None else None
        columns.append(func.count().filter(cond) if cond is not None else func.count())
        columns.append(
            func.coalesce(func.sum(Booking.price_amount).filter(cond) if cond is not None else func.sum(Booking.price_amount), 0)
        )
    row = (
        await session.execute(
            select(*columns).where(Booking.driver_id == driver_id, Booking.status == BookingStatus.COMPLETED)
        )
    ).one()
    return {
        name: {"trips": int(row[2 * i]), "amount": f"{Decimal(row[2 * i + 1]):.2f}"}
        for i, name in enumerate(starts)
    }
