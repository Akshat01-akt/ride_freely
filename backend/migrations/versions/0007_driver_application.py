"""driver application: answers table, free-form document keys, NOT_SUBMITTED state"""
from alembic import op
import sqlalchemy as sa


revision = '0007'
down_revision = '0006'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column('driver_documents', 'doc_type', existing_type=sa.String(length=20), type_=sa.String(length=40))
    op.create_table(
        'driver_answers',
        sa.Column('id', sa.UUID(), nullable=False),
        sa.Column('driver_id', sa.UUID(), nullable=False),
        sa.Column('field_key', sa.String(length=40), nullable=False),
        sa.Column('value', sa.String(length=500), nullable=False),
        sa.Column('status', sa.String(length=20), server_default='PENDING', nullable=False),
        sa.Column('review_note', sa.String(length=500), nullable=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['driver_id'], ['driver_profiles.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('driver_id', 'field_key', name='uq_driver_answer_field'),
    )
    op.create_index('ix_driver_answers_driver_id', 'driver_answers', ['driver_id'])
    op.alter_column('driver_profiles', 'verification_status', server_default='NOT_SUBMITTED')
    # Drivers who registered before this phase already gave these three details: keep them as answers.
    # Approved drivers stay approved and their answers count as approved; everyone else is waiting for review.
    for key, column in (('licence_number', 'licence_number'), ('experience_years', 'experience_years'), ('hourly_rate', 'hourly_rate')):
        op.execute(
            f"""
            INSERT INTO driver_answers (id, driver_id, field_key, value, status)
            SELECT gen_random_uuid(), id, '{key}', {column}::text,
                   CASE WHEN verification_status = 'APPROVED' THEN 'APPROVED' ELSE 'PENDING' END
            FROM driver_profiles WHERE {column} IS NOT NULL
            """
        )


def downgrade() -> None:
    op.execute("UPDATE driver_profiles SET verification_status = 'PENDING' WHERE verification_status = 'NOT_SUBMITTED'")
    op.alter_column('driver_profiles', 'verification_status', server_default='PENDING')
    op.drop_index('ix_driver_answers_driver_id', table_name='driver_answers')
    op.drop_table('driver_answers')
    op.execute("DELETE FROM driver_documents WHERE length(doc_type) > 20")
    op.alter_column('driver_documents', 'doc_type', existing_type=sa.String(length=40), type_=sa.String(length=20))
