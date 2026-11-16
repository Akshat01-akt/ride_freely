"""customer profile answers"""
from alembic import op
import sqlalchemy as sa


revision = '0008'
down_revision = '0007'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'customer_answers',
        sa.Column('id', sa.UUID(), nullable=False),
        sa.Column('customer_id', sa.UUID(), nullable=False),
        sa.Column('field_key', sa.String(length=40), nullable=False),
        sa.Column('value', sa.String(length=500), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['customer_id'], ['customer_profiles.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('customer_id', 'field_key', name='uq_customer_answer_field'),
    )
    op.create_index('ix_customer_answers_customer_id', 'customer_answers', ['customer_id'])
    # Anyone who already set a home address keeps it as their answer.
    op.execute(
        "INSERT INTO customer_answers (id, customer_id, field_key, value) "
        "SELECT gen_random_uuid(), id, 'default_address', default_address FROM customer_profiles WHERE default_address IS NOT NULL AND default_address <> ''"
    )


def downgrade() -> None:
    op.drop_index('ix_customer_answers_customer_id', table_name='customer_answers')
    op.drop_table('customer_answers')
