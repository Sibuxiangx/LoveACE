import datetime

from sqlalchemy import String, func
from sqlalchemy.orm import Mapped, mapped_column

from loveace.database.base import Base


class AuthMEToken(Base):
    __tablename__ = "auth_me_token_table"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[str] = mapped_column(String(20), nullable=False)
    token: Mapped[str] = mapped_column(String(256), unique=True, nullable=False)
    device_id: Mapped[str] = mapped_column(String(256), nullable=False)
    create_date: Mapped[datetime.datetime] = mapped_column(server_default=func.now())
