def convert_zxjxjhh_to_term_format(zxjxjhh: str) -> str:
    """
    转换学期格式
    xxxx-yyyy-1-1 -> xxxx-yyyy秋季学期
    xxxx-yyyy-2-1 -> xxxx-yyyy春季学期

    Args:
        zxjxjhh: 学期代码，如 "2025-2026-1-1"

    Returns:
        str: 转换后的学期名称，如 "2025-2026秋季学期"
    """
    try:
        parts = zxjxjhh.split("-")
        if len(parts) >= 3:
            year_start = parts[0]
            year_end = parts[1]
            semester_num = parts[2]

            if semester_num == "1":
                return f"{year_start}-{year_end}秋季学期"
            elif semester_num == "2":
                return f"{year_start}-{year_end}春季学期"

        return zxjxjhh  # 如果格式不匹配，返回原值
    except Exception:
        return zxjxjhh
