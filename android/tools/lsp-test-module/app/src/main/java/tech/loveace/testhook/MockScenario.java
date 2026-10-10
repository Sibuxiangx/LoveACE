package tech.loveace.testhook;

enum MockScenario {
    TODAY_ACTIVE("today_active", "今日进行中"),
    THIS_WEEK("this_week", "本周待考"),
    UPCOMING("upcoming", "最近考试"),
    JUST_ENDED("just_ended", "刚刚结束"),
    ALL_FINISHED("all_finished", "全部结束"),
    EMPTY("empty", "空数据"),
    MALFORMED("malformed", "异常格式"),
    SERVER_ERROR("server_error", "服务错误"),
    CUSTOM("custom", "自定义");

    final String wireName;
    final String displayName;

    MockScenario(String wireName, String displayName) {
        this.wireName = wireName;
        this.displayName = displayName;
    }

    static MockScenario fromWireName(String value) {
        if (value != null) {
            for (MockScenario scenario : values()) {
                if (scenario.wireName.equals(value)) return scenario;
            }
        }
        return TODAY_ACTIVE;
    }
}
