"""sign up with email or mobile: optional phone, unique normalised email, driver details filled in later"""
from alembic import op
import sqlalchemy as sa


revision = '0005'
down_revision = '0004'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column('users', 'phone', existing_type=sa.String(length=20), nullable=True)
    op.add_column('users', sa.Column('email_normalized', sa.String(length=254), nullable=True))
    op.execute("UPDATE users SET email_normalized = lower(email) WHERE email IS NOT NULL")
    # Where several accounts share an email, the oldest keeps it; the others lose it (they still have their phone).
    op.execute(
        """
        UPDATE users u SET email = NULL, email_normalized = NULL
        WHERE u.email_normalized IS NOT NULL AND EXISTS (
          SELECT 1 FROM users o WHERE o.email_normalized = u.email_normalized
            AND (o.created_at, o.id) < (u.created_at, u.id))
        """
    )
    op.create_index('ux_users_email_normalized', 'users', ['email_normalized'], unique=True)
    op.alter_column('driver_profiles', 'licence_number', existing_type=sa.String(length=50), nullable=True)
    op.alter_column('driver_profiles', 'experience_years', existing_type=sa.Integer(), nullable=True)
    op.alter_column('driver_profiles', 'hourly_rate', existing_type=sa.Numeric(10, 2), nullable=True)


def downgrade() -> None:
    op.alter_column('driver_profiles', 'hourly_rate', existing_type=sa.Numeric(10, 2), nullable=False)
    op.alter_column('driver_profiles', 'experience_years', existing_type=sa.Integer(), nullable=False)
    op.alter_column('driver_profiles', 'licence_number', existing_type=sa.String(length=50), nullable=False)
    op.drop_index('ux_users_email_normalized', table_name='users')
    op.drop_column('users', 'email_normalized')
    op.alter_column('users', 'phone', existing_type=sa.String(length=20), nullable=False)
