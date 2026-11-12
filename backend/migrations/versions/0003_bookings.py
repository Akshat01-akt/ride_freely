"""bookings with a no-double-booking exclusion constraint"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import ExcludeConstraint


revision = '0003'
down_revision = '0002'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table('bookings',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('customer_id', sa.UUID(), nullable=False),
    sa.Column('driver_id', sa.UUID(), nullable=False),
    sa.Column('booking_type', sa.Enum('HOURLY', 'FULL_DAY', name='bookingtype', native_enum=False, length=20), nullable=False),
    sa.Column('start_time', sa.DateTime(timezone=True), nullable=False),
    sa.Column('end_time', sa.DateTime(timezone=True), nullable=False),
    sa.Column('hours', sa.Integer(), nullable=False),
    sa.Column('pickup_address', sa.String(length=300), nullable=False),
    sa.Column('notes', sa.String(length=500), nullable=True),
    sa.Column('price_amount', sa.Numeric(precision=10, scale=2), nullable=False),
    sa.Column('status', sa.Enum('REQUESTED', 'ACCEPTED', 'REJECTED', 'CANCELLED', 'EXPIRED', 'IN_PROGRESS', 'COMPLETED', name='bookingstatus', native_enum=False, length=20), server_default='REQUESTED', nullable=False),
    sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['customer_id'], ['customer_profiles.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['driver_id'], ['driver_profiles.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    ExcludeConstraint(('driver_id', '='), (sa.text('tstzrange(start_time, end_time)'), '&&'), using='gist', where=sa.text("status IN ('REQUESTED', 'ACCEPTED', 'IN_PROGRESS')"), name='bookings_no_driver_overlap'),
    )
    op.create_index(op.f('ix_bookings_customer_id'), 'bookings', ['customer_id'], unique=False)
    op.create_index(op.f('ix_bookings_driver_id'), 'bookings', ['driver_id'], unique=False)


def downgrade() -> None:
    op.drop_table('bookings')
