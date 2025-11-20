import datetime

from sqlalchemy import String, func
from sqlalchemy.orm import Mapped, mapped_column

from loveace.database.base import Base


class LDJLBTicket(Base):
    __tablename__ = "ldjlb_ticket_table"
    id: Mapped[int] = mapped_column(primary_key=True)
    userid: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    ldjlb_token: Mapped[str] = mapped_column(String(1024), nullable=False)
    create_date: Mapped[datetime.datetime] = mapped_column(server_default=func.now())
