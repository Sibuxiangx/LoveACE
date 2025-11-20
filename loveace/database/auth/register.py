import datetime

from sqlalchemy import String, func
from sqlalchemy.orm import Mapped, mapped_column

from loveace.database.base import Base


class InviteCode(Base):
    __tablename__ = "invite_code_table"
    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    create_date: Mapped[datetime.datetime] = mapped_column(server_default=func.now())


class RegisterCoolDown(Base):
    __tablename__ = "register_cooldown_table"
    id: Mapped[int] = mapped_column(primary_key=True)
    userid: Mapped[str] = mapped_column(String(20), unique=True, nullable=False)
    expire_date: Mapped[datetime.datetime] = mapped_column(nullable=False)
