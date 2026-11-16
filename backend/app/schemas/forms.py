import re
import uuid
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

FormRole = Literal["driver", "customer"]
FieldType = Literal["text", "number", "date", "choice", "document"]
KEY_PATTERN = re.compile(r"^[A-Za-z][A-Za-z0-9_]{1,39}$")
Key = Annotated[str, StringConstraints(pattern=KEY_PATTERN.pattern)]
Label = Annotated[str, Field(min_length=1, max_length=120)]
HelpText = Annotated[str, Field(max_length=300)]
Choices = Annotated[list[Annotated[str, Field(min_length=1, max_length=60)]], Field(min_length=2, max_length=20)]


def _check_choices(field_type: str, choices: list[str] | None) -> None:
    if field_type == "choice":
        if choices is None or len(set(choices)) != len(choices):
            raise ValueError("A choice field needs 2 to 20 different options")
    elif choices is not None:
        raise ValueError("Only choice fields have options")


class FieldIn(BaseModel):
    key: Key
    label: Label
    field_type: FieldType
    required: bool = False
    help_text: HelpText | None = None
    choices: Choices | None = None

    @model_validator(mode="after")
    def _choices_match_type(self):
        _check_choices(self.field_type, self.choices)
        return self


class FieldPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")

    label: Label | None = None
    field_type: FieldType | None = None
    required: bool | None = None
    help_text: HelpText | None = None
    choices: Choices | None = None
    is_active: bool | None = None


class OrderIn(BaseModel):
    ids: list[uuid.UUID]


class FieldOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    key: str
    label: str
    field_type: str
    required: bool
    help_text: str | None
    choices: list[str] | None
    position: int
    is_active: bool
    is_core: bool
