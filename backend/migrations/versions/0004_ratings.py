"""ratings and completion time on bookings"""
from alembic import op
import sqlalchemy as sa


revision = '0004'
down_revision = '0003'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('bookings', sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('bookings', sa.Column('rating', sa.SmallInteger(), nullable=True))
    op.add_column('bookings', sa.Column('rated_at', sa.DateTime(timezone=True), nullable=True))
    op.create_check_constraint('bookings_rating_range', 'bookings', 'rating BETWEEN 1 AND 5')


def downgrade() -> None:
    op.drop_constraint('bookings_rating_range', 'bookings', type_='check')
    op.drop_column('bookings', 'rated_at')
    op.drop_column('bookings', 'rating')
    op.drop_column('bookings', 'completed_at')
