"""server-defined registration forms"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = '0006'
down_revision = '0005'
branch_labels = None
depends_on = None

# (role, key, label, type, required, help_text, position, is_core)
SEED = [
    ('driver', 'licence_number', 'Driving licence number', 'text', True, None, 1, True),
    ('driver', 'experience_years', 'Years of driving experience', 'number', True, None, 2, True),
    ('driver', 'hourly_rate', 'Your hourly rate (INR)', 'number', True, 'What you charge per hour of driving', 3, True),
    ('driver', 'LICENCE', 'Driving licence', 'document', True, 'A clear photo or PDF of your licence', 4, True),
    ('driver', 'ID_PROOF', 'ID proof', 'document', True, 'Aadhaar, voter ID or passport', 5, True),
    ('driver', 'PHOTO', 'Your photo', 'document', False, 'A recent passport-style photo', 6, True),
    ('customer', 'default_address', 'Home address', 'text', False, 'Used to prefill your pickup location', 1, False),
]


def upgrade() -> None:
    form_fields = op.create_table(
        'form_fields',
        sa.Column('id', sa.UUID(), nullable=False),
        sa.Column('role', sa.String(length=20), nullable=False),
        sa.Column('key', sa.String(length=40), nullable=False),
        sa.Column('label', sa.String(length=120), nullable=False),
        sa.Column('field_type', sa.String(length=20), nullable=False),
        sa.Column('required', sa.Boolean(), server_default='false', nullable=False),
        sa.Column('help_text', sa.String(length=300), nullable=True),
        sa.Column('choices', postgresql.JSONB(), nullable=True),
        sa.Column('position', sa.Integer(), nullable=False),
        sa.Column('is_active', sa.Boolean(), server_default='true', nullable=False),
        sa.Column('is_core', sa.Boolean(), server_default='false', nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('role', 'key', name='uq_form_field_role_key'),
    )
    form_versions = op.create_table(
        'form_versions',
        sa.Column('role', sa.String(length=20), nullable=False),
        sa.Column('version', sa.Integer(), server_default='1', nullable=False),
        sa.PrimaryKeyConstraint('role'),
    )
    import uuid

    op.bulk_insert(form_fields, [
        {'id': uuid.uuid4(), 'role': r, 'key': k, 'label': label, 'field_type': t, 'required': req,
         'help_text': h, 'position': pos, 'is_core': core}
        for r, k, label, t, req, h, pos, core in SEED
    ])
    op.bulk_insert(form_versions, [{'role': 'driver', 'version': 1}, {'role': 'customer', 'version': 1}])


def downgrade() -> None:
    op.drop_table('form_versions')
    op.drop_table('form_fields')
