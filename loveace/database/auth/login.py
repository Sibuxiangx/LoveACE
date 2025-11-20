import datetime

from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column

from loveace.database.base import Base


class LoginCoolDown(Base):
    __tablename__ = "login_cooldown_table"
    id: Mapped[int] = mapped_column(primary_key=True)
    userid: Mapped[str] = mapped_column(String(20), unique=True, nullable=False)
    expire_date: Mapped[datetime.datetime] = mapped_column(nullable=False)
