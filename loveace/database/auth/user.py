import datetime

from sqlalchemy import String, func
from sqlalchemy.orm import Mapped, mapped_column

from loveace.database.base import Base


class ACEUser(Base):
    __tablename__ = "ace_user_table"
    id: Mapped[int] = mapped_column(primary_key=True)
    userid: Mapped[str] = mapped_column(String(20), unique=True, nullable=False)
    password: Mapped[str] = mapped_column(String(2048), nullable=True)
    ec_password: Mapped[str] = mapped_column(String(2048), nullable=True)
    create_date: Mapped[datetime.datetime] = mapped_column(server_default=func.now())
    last_login_date: Mapped[datetime.datetime] = mapped_column(nullable=True)
