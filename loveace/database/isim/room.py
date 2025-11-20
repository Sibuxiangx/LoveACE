import datetime

from sqlalchemy import String, func
from sqlalchemy.orm import Mapped, mapped_column

from loveace.database.base import Base


class RoomBind(Base):
    __tablename__ = "isim_room_bind_table"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[str] = mapped_column(String(20), nullable=False)
    roomid: Mapped[str] = mapped_column(String(20), nullable=False)
    roomtext: Mapped[str] = mapped_column(String(50), nullable=False)
    create_date: Mapped[datetime.datetime] = mapped_column(server_default=func.now())
