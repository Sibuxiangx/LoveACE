import datetime

from sqlalchemy import String, func
from sqlalchemy.orm import Mapped, mapped_column

from loveace.database.base import Base


class UserProfile(Base):
    __tablename__ = "ace_user_profile"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[str] = mapped_column(String(20), nullable=False)
    nickname: Mapped[str] = mapped_column(String(50), nullable=False)
    slogan: Mapped[str] = mapped_column(String(100), nullable=True)
    avatar_url: Mapped[str] = mapped_column(String(200), nullable=True)
    avatar_md5: Mapped[str] = mapped_column(String(128), nullable=True)
    create_date: Mapped[datetime.datetime] = mapped_column(server_default=func.now())
