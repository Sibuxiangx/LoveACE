from typing import List, Optional

from pydantic import BaseModel, Field


class LDJLBProgressInfo(BaseModel):
    """劳动俱乐部修课进度信息"""

    finish_count: int = Field(0, alias="data", description="已完成的活动数量")

    @property
    def progress_percentage(self) -> float:
        """计算修课进度百分比（满分10次）"""
        return min((self.finish_count / 10.0) * 100, 100.0)


class LDJLBPageInfo(BaseModel):
    """分页信息"""

    total_item_count: int = Field(0, alias="TotalItemCount", description="总条目数")
    page_size: int = Field(20, alias="PageSize", description="每页大小")
    current_page_index: int = Field(1, alias="CurrentPageIndex", description="当前页码")


class LDJLBActivity(BaseModel):
    """劳动俱乐部活动信息"""

    id: str = Field("", alias="ID", description="活动ID")
    ico: Optional[str] = Field(None, alias="Ico", description="活动图标")
    state: int = Field(0, alias="State", description="活动状态代码")
    state_name: str = Field("", alias="StateName", description="活动状态名称")
    type_id: str = Field("", alias="TypeID", description="活动类型ID")
    type_name: str = Field("", alias="TypeName", description="活动类型名称")
    title: str = Field("", alias="Title", description="活动标题")
    start_time: str = Field("", alias="StartTime", description="活动开始时间")
    end_time: str = Field("", alias="EndTime", description="活动结束时间")
    charge_user_no: str = Field("", alias="ChargeUserNo", description="负责人工号")
    charge_user_name: str = Field("", alias="ChargeUserName", description="负责人姓名")
    club_id: str = Field("", alias="ClubID", description="所属俱乐部ID")
    club_name: str = Field("", alias="ClubName", description="所属俱乐部名称")
    member_num: int = Field(0, alias="MemberNum", description="已报名人数")
    add_time: str = Field("", alias="AddTime", description="活动添加时间")
    people_num: int = Field(0, alias="PeopleNum", description="活动人数限制")
    people_num_min: Optional[int] = Field(None, alias="PeopleNumMin", description="最小人数限制")
    is_join: Optional[bool] = Field(None, alias="IsJson", description="是否已加入")
    is_close: Optional[bool] = Field(None, alias="IsClose", description="是否已关闭")
    sign_up_start_time: str = Field("", alias="SignUpStartTime", description="报名开始时间")
    sign_up_end_time: str = Field("", alias="SignUpEndTime", description="报名结束时间")


class LDJLBActivityListResponse(BaseModel):
    """劳动俱乐部活动列表响应"""

    activities: List[LDJLBActivity] = Field([], alias="data", description="活动列表")
    page_info: LDJLBPageInfo = Field(..., alias="pageInfo", description="分页信息")


class LDJLBClub(BaseModel):
    """劳动俱乐部信息"""

    id: str = Field("", alias="ID", description="俱乐部ID")
    name: str = Field("", alias="Name", description="俱乐部名称")
    type_id: str = Field("", alias="TypeID", description="俱乐部类型ID")
    people_num: int = Field(0, alias="PeopleNum", description="俱乐部总人数")
    project_id: str = Field("", alias="ProjectID", description="项目ID")
    project_name: str = Field("", alias="PorjectName", description="项目名称")
    type_name: str = Field("", alias="TypeName", description="类型名称")
    ico: str = Field("", alias="Ico", description="俱乐部图标")
    desc: Optional[str] = Field(None, alias="Desc", description="俱乐部描述")
    chairman_no: str = Field("", alias="ChairmanNo", description="主席工号")
    chairman_name: str = Field("", alias="CairmanName", description="主席姓名")
    depart_code: str = Field("", alias="DepartCode", description="部门代码")
    contact: Optional[str] = Field(None, alias="Contact", description="联系方式")
    is_enable: bool = Field(True, alias="IsEnable", description="是否启用")
    depart_name: str = Field("", alias="DpeartName", description="部门名称")
    member_num: int = Field(0, alias="MemberNum", description="俱乐部成员数")


class LDJLBClubListResponse(BaseModel):
    """劳动俱乐部列表响应"""

    clubs: List[LDJLBClub] = Field([], alias="data", description="俱乐部列表")


class LDJLBApplyResponse(BaseModel):
    """劳动俱乐部报名响应"""

    code: int = Field(0, description="响应代码")
    msg: str = Field("", description="响应消息")


class ScanSignRequest(BaseModel):
    """扫码签到请求模型"""

    content: str = Field(..., description="扫码结果内容")
    location: str = Field(..., description="位置信息,格式: 经度,纬度")


class ScanSignResponse(BaseModel):
    """扫码签到响应模型"""

    code: int = Field(..., description="响应码,0表示成功")
    msg: Optional[str] = Field(None, description="响应消息")
    data: Optional[dict] = Field(None, description="响应数据")


class SignItem(BaseModel):
    """签到项信息"""

    id: str = Field("", alias="ID", description="签到项ID")
    type: int = Field(1, alias="Type", description="类型，1=签到")
    type_name: str = Field("", alias="TypeName", description="类型名称")
    start_time: str = Field("", alias="StartTime", description="签到开始时间")
    end_time: str = Field("", alias="EndTime", description="签到结束时间")
    is_sign: bool = Field(False, alias="IsSign", description="是否已签到")
    sign_time: str = Field("", alias="SignTime", description="签到时间")


class SignListResponse(BaseModel):
    """签到列表响应模型"""

    code: int = Field(0, description="响应码,0表示成功")
    data: List[SignItem] = Field(default_factory=list, description="签到列表数据")


class FormField(BaseModel):
    """活动表单字段"""

    id: str = Field("", alias="ID", description="字段ID")
    name: str = Field("", alias="Name", description="字段名称")
    is_must: bool = Field(False, alias="IsMust", description="是否必填")
    field_type: int = Field(1, alias="FieldType", description="字段类型")
    value: str = Field("", alias="Value", description="字段值")


class FlowData(BaseModel):
    """活动审批流程数据"""

    id: str = Field("", alias="ID", description="流程ID")
    is_adopt: bool = Field(False, alias="IsAdopt", description="是否通过")
    flow_type: int = Field(0, alias="FlowType", description="流程类型")
    flow_type_name: str = Field("", alias="FlowTypeName", description="流程类型名称")
    user_no: Optional[str] = Field(None, alias="UserNo", description="用户工号")
    user_name: str = Field("", alias="UserName", description="用户姓名")
    exam_user_no: str = Field("", alias="ExamUserNo", description="审批人工号")
    exam_user_name: str = Field("", alias="ExamUserName", description="审批人姓名")
    exam_comment: str = Field("", alias="ExamComment", description="审批意见")
    add_time: str = Field("", alias="AddTime", description="提交时间")
    exam_time: str = Field("", alias="ExamTime", description="审批时间")


class Teacher(BaseModel):
    """活动教师信息"""

    user_name: str = Field("", alias="UserName", description="教师姓名")
    id: str = Field("", alias="ID", description="记录ID")
    activity_id: str = Field("", alias="ActivityID", description="活动ID")
    user_no: str = Field("", alias="UserNo", description="教师工号")
    add_time: str = Field("", alias="AddTime", description="添加时间")
    add_user_no: str = Field("", alias="AddUserNo", description="添加人工号")


class ActivityDetailData(BaseModel):
    """活动详细信息数据"""

    id: str = Field("", alias="ID", description="活动ID")
    title: str = Field("", alias="Title", description="活动标题")
    state: int = Field(0, alias="State", description="活动状态")
    ico: Optional[str] = Field(None, alias="Ico", description="活动图标")
    type_id: str = Field("", alias="TypeID", description="活动类型ID")
    type_name: str = Field("", alias="TypeName", description="活动类型名称")
    start_time: str = Field("", alias="StartTime", description="活动开始时间")
    end_time: str = Field("", alias="EndTime", description="活动结束时间")
    charge_user_no: str = Field("", alias="ChargeUserNo", description="负责人工号")
    charge_user_name: str = Field("", alias="ChargeUserName", description="负责人姓名")
    club_id: str = Field("", alias="ClubID", description="所属俱乐部ID")
    club_name: str = Field("", alias="ClubName", description="所属俱乐部名称")
    member_num: int = Field(0, alias="MemberNum", description="已报名人数")
    add_time: str = Field("", alias="AddTime", description="活动添加时间")
    apply_is_need_exam: bool = Field(False, alias="ApplyIsNeedExam", description="报名是否需要审批")
    is_member: bool = Field(False, alias="IsMember", description="是否为成员")
    is_manager: bool = Field(False, alias="IsManager", description="是否为管理员")
    people_num: int = Field(0, alias="PeopleNum", description="活动人数限制")
    people_num_min: Optional[int] = Field(None, alias="PeopleNumMin", description="最小人数限制")
    is_close: Optional[bool] = Field(None, alias="IsClose", description="是否已关闭")
    sign_up_start_time: str = Field("", alias="SignUpStartTime", description="报名开始时间")
    sign_up_end_time: str = Field("", alias="SignUpEndTime", description="报名结束时间")


class ActivityDetailResponse(BaseModel):
    """活动详情响应模型"""

    code: int = Field(0, description="响应码,0表示成功")
    data: Optional[ActivityDetailData] = Field(None, description="活动详细信息")
    form_data: List[FormField] = Field(default_factory=list, alias="formData", description="表单数据")
    flow_data: List[FlowData] = Field(default_factory=list, alias="flowData", description="审批流程数据")
    venue_reserve_data: List = Field(default_factory=list, alias="VenueReserveData", description="场地预约数据")
    teacher_list: List[Teacher] = Field(default_factory=list, alias="teacherList", description="教师列表")
