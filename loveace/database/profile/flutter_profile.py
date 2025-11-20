import datetime

from sqlalchemy import String, func
from sqlalchemy.orm import Mapped, mapped_column

from loveace.database.base import Base


class FlutterThemeProfile(Base):
    __tablename__ = "flutter_theme_profile"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(nullable=False, unique=True)
    dark_mode: Mapped[bool] = mapped_column(nullable=False, default=False)
    light_mode_opacity: Mapped[float] = mapped_column(nullable=False, default=1.0)
    light_mode_brightness: Mapped[float] = mapped_column(nullable=False, default=1.0)
    light_mode_background_url: Mapped[str] = mapped_column(String(300), nullable=True)
    light_mode_background_md5: Mapped[str] = mapped_column(String(128), nullable=True)
    light_mode_blur: Mapped[float] = mapped_column(nullable=False, default=0.0)
    dark_mode_opacity: Mapped[float] = mapped_column(nullable=False, default=1.0)
    dark_mode_brightness: Mapped[float] = mapped_column(nullable=False, default=1.0)
    dark_mode_background_url: Mapped[str] = mapped_column(String(300), nullable=True)
    dark_mode_background_md5: Mapped[str] = mapped_column(String(128), nullable=True)
    dark_mode_background_blur: Mapped[float] = mapped_column(
        nullable=False, default=0.0
    )
    create_date: Mapped[datetime.datetime] = mapped_column(server_default=func.now())
