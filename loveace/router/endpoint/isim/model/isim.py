from typing import List

from pydantic import BaseModel, Field

# ==================== 电费相关模型 ====================


class ElectricityBalance(BaseModel):
    """电费余额信息"""

    remaining_purchased: float = Field(..., description="剩余购电（度）")
    remaining_subsidy: float = Field(..., description="剩余补助（度）")


class ElectricityUsageRecord(BaseModel):
    """用电记录"""

    record_time: str = Field(..., description="记录时间，如：2025-08-29 00:04:58")
    usage_amount: float = Field(..., description="用电量（度）")
    meter_name: str = Field(..., description="电表名称，如：1-101 或 1-101空调")


# ==================== 充值相关模型 ====================


class PaymentRecord(BaseModel):
    """充值记录"""

    payment_time: str = Field(..., description="充值时间，如：2025-02-21 11:30:08")
    amount: float = Field(..., description="充值金额（元）")
    payment_type: str = Field(..., description="充值类型，如：下发补助、一卡通充值")


class UniISIMInfoResponse(BaseModel):
    """寝室电费信息"""

    room_code: str = Field(..., description="寝室代码")
    room_text: str = Field(..., description="寝室显示名称")
    room_display: str = Field(..., description="寝室显示名称")
    balance: ElectricityBalance = Field(..., description="电费余额")
    usage_records: List[ElectricityUsageRecord] = Field(..., description="用电记录")
    payments: List[PaymentRecord] = Field(..., description="充值记录")
