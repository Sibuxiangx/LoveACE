import Foundation

// MARK: - UniResponse

struct UniResponse<T> {
    let success: Bool
    let data: T?
    let message: String
    let error: String?
    let retryable: Bool

    static func success(_ data: T, message: String = "操作成功") -> UniResponse {
        UniResponse(success: true, data: data, message: message, error: nil, retryable: false)
    }

    static func failure(_ error: String, message: String = "操作失败", retryable: Bool = false) -> UniResponse {
        UniResponse(success: false, data: nil, message: message, error: error, retryable: retryable)
    }
}

// MARK: - JWC Models

struct AcademicInfo: Codable {
    let completedCourses: Int
    let failedCourses: Int
    let gpa: Double
    let averageScore: Double?
    let averageScoreRank: Int?
    let averageScoreRankPopulation: Int?
    let pendingCourses: Int
    let currentTerm: String

    enum CodingKeys: String, CodingKey {
        case completedCourses = "courseNum"
        case failedCourses = "coursePas"
        case gpa
        case averageScore = "sspjf_jd"
        case averageScoreRank = "sspjf_pm"
        case averageScoreRankPopulation = "sspjf_rs"
        case pendingCourses = "courseNum_bxqyxd"
        case currentTerm = "zxjxjhh"
    }

    init(completedCourses: Int = 0, failedCourses: Int = 0, gpa: Double = 0.0,
         averageScore: Double? = nil, averageScoreRank: Int? = nil,
         averageScoreRankPopulation: Int? = nil, pendingCourses: Int = 0,
         currentTerm: String = "") {
        self.completedCourses = completedCourses
        self.failedCourses = failedCourses
        self.gpa = gpa
        self.averageScore = averageScore
        self.averageScoreRank = averageScoreRank
        self.averageScoreRankPopulation = averageScoreRankPopulation
        self.pendingCourses = pendingCourses
        self.currentTerm = currentTerm
    }
}

struct TermItem: Codable, Identifiable, Hashable {
    var id: String { termCode }
    let termCode: String
    let termName: String
    let isCurrent: Bool

    init(termCode: String, termName: String, isCurrent: Bool = false) {
        self.termCode = termCode
        self.termName = termName
        self.isCurrent = isCurrent
    }
}

struct ScoreRecord: Codable, Identifiable {
    var id: String { "\(termId)_\(courseCode)_\(sequence)" }
    let sequence: Int
    let termId: String
    let courseCode: String
    let courseClass: String
    let courseNameCn: String
    let courseNameEn: String
    let credits: String
    let hours: Int
    let courseType: String?
    let examType: String?
    let score: String
    let retakeScore: String?
    let makeupScore: String?
    let examTime: String

    var hasPublishedScore: Bool { !score.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init(sequence: Int = 0, termId: String = "", courseCode: String = "",
         courseClass: String = "", courseNameCn: String = "", courseNameEn: String = "",
          credits: String = "0", hours: Int = 0, courseType: String? = nil,
          examType: String? = nil, score: String = "", retakeScore: String? = nil,
          makeupScore: String? = nil, examTime: String = "") {
        self.sequence = sequence
        self.termId = termId
        self.courseCode = courseCode
        self.courseClass = courseClass
        self.courseNameCn = courseNameCn
        self.courseNameEn = courseNameEn
        self.credits = credits
        self.hours = hours
        self.courseType = courseType
        self.examType = examType
        self.score = score
        self.retakeScore = retakeScore
        self.makeupScore = makeupScore
        self.examTime = examTime
    }
}

struct ScoreDetailItem: Identifiable {
    var id: String { "\(scoreType)_\(remark)" }
    let scoreType: String
    let usualScore: String
    let midtermScore: String
    let finalScore: String
    let categoryScore: String
    let remark: String
}

struct ScoreDetail {
    let items: [ScoreDetailItem]

    init(items: [ScoreDetailItem] = []) {
        self.items = items
    }
}

struct TermScoreResponse: Codable {
    let totalCount: Int
    let records: [ScoreRecord]

    init(totalCount: Int = 0, records: [ScoreRecord] = []) {
        self.totalCount = totalCount
        self.records = records
    }
}

struct UnifiedExamInfo: Codable, Identifiable {
    var id: String { "\(courseName)_\(examDate)_\(examTime)" }
    let courseName: String
    let examDate: String
    let examTime: String
    let examLocation: String
    let examType: String
    let note: String

    init(courseName: String = "", examDate: String = "", examTime: String = "",
         examLocation: String = "", examType: String = "", note: String = "") {
        self.courseName = courseName
        self.examDate = examDate
        self.examTime = examTime
        self.examLocation = examLocation
        self.examType = examType
        self.note = note
    }
}

struct TrainingPlanInfo: Codable {
    let planName: String
    let majorName: String
    let grade: String

    init(planName: String = "", majorName: String = "", grade: String = "") {
        self.planName = planName
        self.majorName = majorName
        self.grade = grade
    }
}

// MARK: - YKT Models

struct CardBalance: Codable {
    let balance: Double
    let balanceText: String

    init(balance: Double = 0.0, balanceText: String = "") {
        self.balance = balance
        self.balanceText = balanceText
    }
}

struct TransactionRecord: Codable, Identifiable {
    var id: String { "\(accountingTime)_\(transactionTime)_\(operationType)" }
    let accountingTime: String
    let transactionTime: String
    let expense: Double?
    let income: Double?
    let operationType: String
    let balance: Double
    let area: String
    let terminalId: String

    var isExpense: Bool { expense != nil && (expense ?? 0) > 0 }
    var isIncome: Bool { income != nil && (income ?? 0) > 0 }
    var amount: Double { isIncome ? (income ?? 0) : -(expense ?? 0) }
    var amountText: String {
        if isIncome { return "+\(String(format: "%.2f", income ?? 0))元" }
        if isExpense { return "-\(String(format: "%.2f", expense ?? 0))元" }
        return "0.00元"
    }

    init(accountingTime: String = "", transactionTime: String = "",
         expense: Double? = nil, income: Double? = nil, operationType: String = "",
         balance: Double = 0.0, area: String = "", terminalId: String = "") {
        self.accountingTime = accountingTime
        self.transactionTime = transactionTime
        self.expense = expense
        self.income = income
        self.operationType = operationType
        self.balance = balance
        self.area = area
        self.terminalId = terminalId
    }
}

// MARK: - ISIM Models

struct ElectricityBalance: Codable {
    let remainingPurchased: Double
    let remainingSubsidy: Double
    var total: Double { remainingPurchased + remainingSubsidy }

    init(remainingPurchased: Double = 0.0, remainingSubsidy: Double = 0.0) {
        self.remainingPurchased = remainingPurchased
        self.remainingSubsidy = remainingSubsidy
    }
}

struct ElectricityUsageRecord: Codable, Identifiable {
    var id: String { "\(recordTime)_\(meterName)" }
    let recordTime: String
    let usageAmount: Double
    let meterName: String

    init(recordTime: String = "", usageAmount: Double = 0.0, meterName: String = "") {
        self.recordTime = recordTime
        self.usageAmount = usageAmount
        self.meterName = meterName
    }
}

struct PaymentRecord: Codable, Identifiable {
    var id: String { "\(paymentTime)_\(amount)" }
    let paymentTime: String
    let amount: Double
    let paymentType: String

    init(paymentTime: String = "", amount: Double = 0.0, paymentType: String = "") {
        self.paymentTime = paymentTime
        self.amount = amount
        self.paymentType = paymentType
    }
}

struct ElectricityInfo: Codable {
    let balance: ElectricityBalance
    let usageRecords: [ElectricityUsageRecord]
    let payments: [PaymentRecord]

    init(balance: ElectricityBalance = ElectricityBalance(),
         usageRecords: [ElectricityUsageRecord] = [],
         payments: [PaymentRecord] = []) {
        self.balance = balance
        self.usageRecords = usageRecords
        self.payments = payments
    }
}

// MARK: - AAC Models

struct AACCreditInfo: Codable {
    let totalScore: Double
    let isTypeAdopt: Bool
    let typeAdoptResult: String

    enum CodingKeys: String, CodingKey {
        case totalScore = "TotalScore"
        case isTypeAdopt = "IsTypeAdopt"
        case typeAdoptResult = "TypeAdoptResult"
    }

    init(totalScore: Double = 0.0, isTypeAdopt: Bool = false, typeAdoptResult: String = "") {
        self.totalScore = totalScore
        self.isTypeAdopt = isTypeAdopt
        self.typeAdoptResult = typeAdoptResult
    }
}

struct AACCreditItem: Codable, Identifiable {
    var id: String { itemId }
    let itemId: String
    let title: String
    let typeName: String
    let userNo: String
    let score: Double
    let addTime: String

    enum CodingKeys: String, CodingKey {
        case itemId = "ID"
        case title = "Title"
        case typeName = "TypeName"
        case userNo = "UserNo"
        case score = "Score"
        case addTime = "AddTime"
    }

    init(itemId: String = "", title: String = "", typeName: String = "",
         userNo: String = "", score: Double = 0.0, addTime: String = "") {
        self.itemId = itemId
        self.title = title
        self.typeName = typeName
        self.userNo = userNo
        self.score = score
        self.addTime = addTime
    }
}

struct AACCreditCategory: Codable, Identifiable {
    var id: String { categoryId }
    let categoryId: String
    let showNum: Int
    let typeName: String
    let totalScore: Double
    let children: [AACCreditItem]

    enum CodingKeys: String, CodingKey {
        case categoryId = "ID"
        case showNum = "ShowNum"
        case typeName = "TypeName"
        case totalScore = "TotalScore"
        case children
    }

    init(categoryId: String = "", showNum: Int = 0, typeName: String = "",
         totalScore: Double = 0.0, children: [AACCreditItem] = []) {
        self.categoryId = categoryId
        self.showNum = showNum
        self.typeName = typeName
        self.totalScore = totalScore
        self.children = children
    }
}

// MARK: - Competition Models

struct AwardProject: Codable, Identifiable {
    var id: String { projectId }
    let projectId: String
    let projectName: String
    let level: String
    let grade: String
    let awardDate: String
    let applicantId: String
    let applicantName: String
    let order: Int
    let credits: Double
    let bonus: Double
    let status: String
    let verificationStatus: String

    init(projectId: String = "", projectName: String = "", level: String = "",
         grade: String = "", awardDate: String = "", applicantId: String = "",
         applicantName: String = "", order: Int = 0, credits: Double = 0.0,
         bonus: Double = 0.0, status: String = "", verificationStatus: String = "") {
        self.projectId = projectId
        self.projectName = projectName
        self.level = level
        self.grade = grade
        self.awardDate = awardDate
        self.applicantId = applicantId
        self.applicantName = applicantName
        self.order = order
        self.credits = credits
        self.bonus = bonus
        self.status = status
        self.verificationStatus = verificationStatus
    }
}

struct CreditsSummary: Codable {
    let disciplineCompetitionCredits: Double?
    let scientificResearchCredits: Double?
    let transferableCompetitionCredits: Double?
    let innovationPracticeCredits: Double?
    let abilityCertificationCredits: Double?
    let otherProjectCredits: Double?

    var totalCredits: Double {
        [disciplineCompetitionCredits, scientificResearchCredits,
         transferableCompetitionCredits, innovationPracticeCredits,
         abilityCertificationCredits, otherProjectCredits]
            .compactMap { $0 }.reduce(0, +)
    }

    init(disciplineCompetitionCredits: Double? = nil, scientificResearchCredits: Double? = nil,
         transferableCompetitionCredits: Double? = nil, innovationPracticeCredits: Double? = nil,
         abilityCertificationCredits: Double? = nil, otherProjectCredits: Double? = nil) {
        self.disciplineCompetitionCredits = disciplineCompetitionCredits
        self.scientificResearchCredits = scientificResearchCredits
        self.transferableCompetitionCredits = transferableCompetitionCredits
        self.innovationPracticeCredits = innovationPracticeCredits
        self.abilityCertificationCredits = abilityCertificationCredits
        self.otherProjectCredits = otherProjectCredits
    }
}

struct CompetitionFullResponse: Codable {
    let awards: [AwardProject]
    let creditsSummary: CreditsSummary?

    init(awards: [AwardProject] = [], creditsSummary: CreditsSummary? = nil) {
        self.awards = awards
        self.creditsSummary = creditsSummary
    }
}

// MARK: - Labor Club Models

struct LaborClubProgressInfo: Codable {
    let sumScore: Double
    let progress: Double

    enum CodingKeys: String, CodingKey {
        case sumScore = "SumScore"
        case progress = "Progress"
    }

    var isCompleted: Bool { progress >= 100 }
    var finishCount: Int { Int(progress / 10) }

    init(sumScore: Double = 0.0, progress: Double = 0.0) {
        self.sumScore = sumScore
        self.progress = progress
    }
}

struct LaborClubActivity: Codable, Identifiable {
    var id: String { activityId }
    let activityId: String
    let title: String
    let state: Int
    let stateName: String
    let typeId: String
    let typeName: String
    let startTime: String
    let endTime: String
    let clubId: String
    let clubName: String
    let memberNum: Int
    let peopleNum: Int
    let chargeUserNo: String
    let chargeUserName: String
    let signUpStartTime: String
    let signUpEndTime: String
    let addTime: String
    var signList: [SignItem]?

    enum CodingKeys: String, CodingKey {
        case activityId = "ID"
        case title = "Title"
        case state = "State"
        case stateName = "StateName"
        case typeId = "TypeID"
        case typeName = "TypeName"
        case startTime = "StartTime"
        case endTime = "EndTime"
        case clubId = "ClubID"
        case clubName = "ClubName"
        case memberNum = "MemberNum"
        case peopleNum = "PeopleNum"
        case chargeUserNo = "ChargeUserNo"
        case chargeUserName = "ChargeUserName"
        case signUpStartTime = "SignUpStartTime"
        case signUpEndTime = "SignUpEndTime"
        case addTime = "AddTime"
    }

    var isAllSigned: Bool {
        guard let list = signList else { return true }
        return list.isEmpty || list.allSatisfy { $0.isSign }
    }

    var signInStatus: String {
        guard let list = signList, !list.isEmpty else { return "默认签到" }
        let signed = list.filter { $0.isSign }.count
        if list.count == 1 {
            let s = list[0]
            if s.isSign { return "已签到" }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate, .withFullTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
            if let end = formatter.date(from: s.endTime.replacingOccurrences(of: " ", with: "T")),
               Date() > end { return "未签到" }
            return "待签到"
        }
        if signed == list.count { return "已完成签到 (\(signed)/\(list.count))" }
        if signed > 0 { return "部分签到 (\(signed)/\(list.count))" }
        return "未签到 (0/\(list.count))"
    }

    init(activityId: String = "", title: String = "", state: Int = 0, stateName: String = "",
         typeId: String = "", typeName: String = "", startTime: String = "", endTime: String = "",
         clubId: String = "", clubName: String = "", memberNum: Int = 0, peopleNum: Int = 0,
         chargeUserNo: String = "", chargeUserName: String = "", signUpStartTime: String = "",
         signUpEndTime: String = "", addTime: String = "", signList: [SignItem]? = nil) {
        self.activityId = activityId; self.title = title; self.state = state
        self.stateName = stateName; self.typeId = typeId; self.typeName = typeName
        self.startTime = startTime; self.endTime = endTime; self.clubId = clubId
        self.clubName = clubName; self.memberNum = memberNum; self.peopleNum = peopleNum
        self.chargeUserNo = chargeUserNo; self.chargeUserName = chargeUserName
        self.signUpStartTime = signUpStartTime; self.signUpEndTime = signUpEndTime
        self.addTime = addTime; self.signList = signList
    }
}

struct LaborClubInfo: Codable, Identifiable {
    var id: String { clubInfoId }
    let clubInfoId: String
    let name: String
    let typeName: String?
    let ico: String?
    let chairmanName: String?
    let memberNum: Int

    enum CodingKeys: String, CodingKey {
        case clubInfoId = "ID"
        case name = "Name"
        case typeName = "TypeName"
        case ico = "Ico"
        case chairmanName = "CairmanName"
        case memberNum = "MemberNum"
    }

    init(clubInfoId: String = "", name: String = "", typeName: String? = nil,
         ico: String? = nil, chairmanName: String? = nil, memberNum: Int = 0) {
        self.clubInfoId = clubInfoId; self.name = name; self.typeName = typeName
        self.ico = ico; self.chairmanName = chairmanName; self.memberNum = memberNum
    }
}

struct SignItem: Codable, Identifiable {
    var id: String { signItemId }
    let signItemId: String
    let type: Int
    let typeName: String
    let startTime: String
    let endTime: String
    let isSign: Bool
    let signTime: String?

    enum CodingKeys: String, CodingKey {
        case signItemId = "ID"
        case type = "Type"
        case typeName = "TypeName"
        case startTime = "StartTime"
        case endTime = "EndTime"
        case isSign = "IsSign"
        case signTime = "SignTime"
    }

    var statusText: String { isSign ? "已签到" : "未签到" }

    init(signItemId: String = "", type: Int = 0, typeName: String = "",
         startTime: String = "", endTime: String = "", isSign: Bool = false,
         signTime: String? = nil) {
        self.signItemId = signItemId; self.type = type; self.typeName = typeName
        self.startTime = startTime; self.endTime = endTime; self.isSign = isSign
        self.signTime = signTime
    }
}

struct SignInResponse: Codable {
    let code: Int
    let msg: String
    var isSuccess: Bool { code == 0 }

    init(code: Int = 0, msg: String = "") {
        self.code = code; self.msg = msg
    }
}

struct ActivityFormField: Codable, Identifiable {
    var id: String { fieldId }
    let fieldId: String
    let name: String
    let value: String
    let isMust: Bool
    let fieldType: Int

    enum CodingKeys: String, CodingKey {
        case fieldId = "ID"
        case name = "Name"
        case value = "Value"
        case isMust = "IsMust"
        case fieldType = "FieldType"
    }

    init(fieldId: String = "", name: String = "", value: String = "",
         isMust: Bool = false, fieldType: Int = 1) {
        self.fieldId = fieldId; self.name = name; self.value = value
        self.isMust = isMust; self.fieldType = fieldType
    }
}

struct ActivityTeacher: Codable {
    let userName: String
    let userNo: String

    enum CodingKeys: String, CodingKey {
        case userName = "UserName"
        case userNo = "UserNo"
    }

    init(userName: String = "", userNo: String = "") {
        self.userName = userName; self.userNo = userNo
    }
}

struct ActivityDetail {
    let id: String
    let title: String
    let startTime: String
    let endTime: String
    let chargeUserName: String
    let clubName: String
    let memberNum: Int
    let peopleNum: Int
    let signUpStartTime: String
    let signUpEndTime: String
    let formData: [ActivityFormField]
    let teacherList: [ActivityTeacher]
    let signList: [SignItem]

    var location: String {
        formData.first { ["活动地址", "Location", "地点", "活动地点"].contains($0.name) }?.value ?? ""
    }
    var teacherNames: String { teacherList.map { $0.userName }.joined(separator: "、") }

    init(id: String = "", title: String = "", startTime: String = "", endTime: String = "",
         chargeUserName: String = "", clubName: String = "", memberNum: Int = 0, peopleNum: Int = 0,
         signUpStartTime: String = "", signUpEndTime: String = "",
         formData: [ActivityFormField] = [], teacherList: [ActivityTeacher] = [], signList: [SignItem] = []) {
        self.id = id; self.title = title; self.startTime = startTime; self.endTime = endTime
        self.chargeUserName = chargeUserName; self.clubName = clubName
        self.memberNum = memberNum; self.peopleNum = peopleNum
        self.signUpStartTime = signUpStartTime; self.signUpEndTime = signUpEndTime
        self.formData = formData; self.teacherList = teacherList; self.signList = signList
    }
}

// MARK: - Course Schedule Models

struct CourseScheduleRecord: Codable, Identifiable {
    var id: String { "\(kch ?? "")_\(kxh ?? "")_\(skxq ?? 0)_\(skjc ?? 0)" }
    let kch: String?
    let kxh: String?
    let kcm: String?
    let xf: Int?
    let xs: Int?
    let kkxsjc: String?
    let kslxmc: String?
    let skjs: String?
    let bkskrl: Int?
    let bkskyl: Int?
    let xkmssm: String?
    let kkxqm: String?
    let skzc: String?
    let skxq: Int?
    let skjc: Int?
    let cxjc: Int?
    let zcsm: String?
    let kclbmc: String?
    let xqm: String?
    let jxlm: String?
    let jasm: String?
    let mxbj: String?
    let xss: Int?

    var classTimeStr: String? {
        guard let start = skjc, let dur = cxjc else { return nil }
        return "\(start)-\(start + dur - 1)"
    }

    var weekdayStr: String? {
        let weekdays = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        guard let day = skxq, (1...7).contains(day) else { return nil }
        return weekdays[day]
    }

    var scheduleDescription: String {
        var parts: [String] = []
        if let w = weekdayStr { parts.append(w) }
        if let t = classTimeStr { parts.append("第\(t)节") }
        if let z = zcsm, !z.isEmpty { parts.append(z) }
        if let b = jxlm, let r = jasm { parts.append("\(b)\(r)") }
        else if let c = xqm { parts.append(c) }
        return parts.joined(separator: " ")
    }
}

// MARK: - Student Schedule Models

struct ScheduleTimePlace: Codable {
    let classWeek: String
    let classDay: Int
    let classSessions: Int
    let continuingSession: Int
    let campusName: String
    let teachingBuildingName: String
    let classroomName: String
    let weekDescription: String
    let coursePropertiesName: String
    let coureName: String

    var endSession: Int { classSessions + continuingSession - 1 }
    var locationDescription: String {
        "\(campusName) \(teachingBuildingName) \(classroomName)".trimmingCharacters(in: .whitespaces)
    }

    init(classWeek: String = "", classDay: Int = 0, classSessions: Int = 0,
         continuingSession: Int = 0, campusName: String = "", teachingBuildingName: String = "",
         classroomName: String = "", weekDescription: String = "",
         coursePropertiesName: String = "", coureName: String = "") {
        self.classWeek = classWeek; self.classDay = classDay
        self.classSessions = classSessions; self.continuingSession = continuingSession
        self.campusName = campusName; self.teachingBuildingName = teachingBuildingName
        self.classroomName = classroomName; self.weekDescription = weekDescription
        self.coursePropertiesName = coursePropertiesName; self.coureName = coureName
    }
}

struct ScheduleCourseId: Codable, Hashable {
    let executiveEducationPlanNumber: String
    let coureNumber: String
    let coureSequenceNumber: String
    let studentNumber: String

    init(executiveEducationPlanNumber: String = "", coureNumber: String = "",
         coureSequenceNumber: String = "", studentNumber: String = "") {
        self.executiveEducationPlanNumber = executiveEducationPlanNumber
        self.coureNumber = coureNumber; self.coureSequenceNumber = coureSequenceNumber
        self.studentNumber = studentNumber
    }
}

struct ScheduleCourse: Codable, Identifiable {
    var id: String { uniqueKey }
    let courseId: ScheduleCourseId
    let programPlanNumber: String
    let courseName: String
    let unit: Double
    let programPlanName: String
    let attendClassTeacher: String
    let studyModeName: String
    let coursePropertiesName: String
    let examTypeName: String
    let courseCategoryName: String?
    let restrictedCondition: String?
    let timeAndPlaceList: [ScheduleTimePlace]
    let selectCourseStatusName: String

    var courseCode: String { courseId.coureNumber }
    var courseSequence: String { courseId.coureSequenceNumber }
    var uniqueKey: String { "\(courseId.coureNumber)_\(courseId.coureSequenceNumber)" }

    enum CodingKeys: String, CodingKey {
        case courseId = "id"
        case programPlanNumber, courseName, unit, programPlanName
        case attendClassTeacher, studyModeName, coursePropertiesName
        case examTypeName, courseCategoryName, restrictedCondition
        case timeAndPlaceList, selectCourseStatusName
    }

    init(courseId: ScheduleCourseId = ScheduleCourseId(), programPlanNumber: String = "",
         courseName: String = "", unit: Double = 0.0, programPlanName: String = "",
         attendClassTeacher: String = "", studyModeName: String = "",
         coursePropertiesName: String = "", examTypeName: String = "",
         courseCategoryName: String? = nil, restrictedCondition: String? = nil,
         timeAndPlaceList: [ScheduleTimePlace] = [], selectCourseStatusName: String = "") {
        self.courseId = courseId; self.programPlanNumber = programPlanNumber
        self.courseName = courseName; self.unit = unit; self.programPlanName = programPlanName
        self.attendClassTeacher = attendClassTeacher; self.studyModeName = studyModeName
        self.coursePropertiesName = coursePropertiesName; self.examTypeName = examTypeName
        self.courseCategoryName = courseCategoryName; self.restrictedCondition = restrictedCondition
        self.timeAndPlaceList = timeAndPlaceList; self.selectCourseStatusName = selectCourseStatusName
    }
}

struct ScheduleDateInfo: Codable {
    let programPlanCode: String
    let programPlanName: String
    let totalUnits: Double
    let selectCourseList: [ScheduleCourse]

    init(programPlanCode: String = "", programPlanName: String = "",
         totalUnits: Double = 0.0, selectCourseList: [ScheduleCourse] = []) {
        self.programPlanCode = programPlanCode; self.programPlanName = programPlanName
        self.totalUnits = totalUnits; self.selectCourseList = selectCourseList
    }
}

struct StudentScheduleResponse: Codable {
    let allUnits: Double
    let errorMessage: String
    let showSite: Bool
    let dateList: [ScheduleDateInfo]

    var courses: [ScheduleCourse] { dateList.flatMap { $0.selectCourseList } }

    init(allUnits: Double = 0.0, errorMessage: String = "", showSite: Bool = true,
         dateList: [ScheduleDateInfo] = []) {
        self.allUnits = allUnits; self.errorMessage = errorMessage
        self.showSite = showSite; self.dateList = dateList
    }
}

// MARK: - Plan Completion Models

struct PlanCourse: Identifiable {
    var id: String { "\(courseCode)_\(courseName)" }
    let courseCode: String
    let courseName: String
    let credits: Double?
    let score: String?
    let examDate: String?
    let courseType: String
    let isPassed: Bool
    let statusDescription: String

    init(courseCode: String = "", courseName: String = "", credits: Double? = nil,
         score: String? = nil, examDate: String? = nil, courseType: String = "",
         isPassed: Bool = false, statusDescription: String = "未修读") {
        self.courseCode = courseCode; self.courseName = courseName
        self.credits = credits; self.score = score; self.examDate = examDate
        self.courseType = courseType; self.isPassed = isPassed
        self.statusDescription = statusDescription
    }
}

struct PlanCategory: Identifiable {
    let categoryId: String
    let categoryName: String
    let minCredits: Double
    let completedCredits: Double
    let totalCourses: Int
    let passedCourses: Int
    let failedCourses: Int
    let missingRequiredCourses: Int
    let subcategories: [PlanCategory]
    let courses: [PlanCourse]

    var id: String { categoryId }
    var completionPercentage: Double {
        guard minCredits > 0 else { return 0 }
        return min(max(completedCredits / minCredits * 100, 0), 100)
    }
    var isCompleted: Bool { completedCredits >= minCredits }

    init(categoryId: String = "", categoryName: String = "", minCredits: Double = 0.0,
         completedCredits: Double = 0.0, totalCourses: Int = 0, passedCourses: Int = 0,
         failedCourses: Int = 0, missingRequiredCourses: Int = 0,
         subcategories: [PlanCategory] = [], courses: [PlanCourse] = []) {
        self.categoryId = categoryId; self.categoryName = categoryName
        self.minCredits = minCredits; self.completedCredits = completedCredits
        self.totalCourses = totalCourses; self.passedCourses = passedCourses
        self.failedCourses = failedCourses; self.missingRequiredCourses = missingRequiredCourses
        self.subcategories = subcategories; self.courses = courses
    }
}

struct PlanCompletionInfo {
    let planName: String
    let major: String
    let grade: String
    let categories: [PlanCategory]
    let totalCategories: Int
    let totalCourses: Int
    let passedCourses: Int
    let failedCourses: Int
    let unreadCourses: Int
    let missingRequiredCourses: Int
    let estimatedGraduationCredits: Double

    init(planName: String = "", major: String = "", grade: String = "",
         categories: [PlanCategory] = [], totalCategories: Int = 0,
         totalCourses: Int = 0, passedCourses: Int = 0, failedCourses: Int = 0,
         unreadCourses: Int = 0, missingRequiredCourses: Int = 0,
         estimatedGraduationCredits: Double = 0.0) {
        self.planName = planName; self.major = major; self.grade = grade
        self.categories = categories; self.totalCategories = totalCategories
        self.totalCourses = totalCourses; self.passedCourses = passedCourses
        self.failedCourses = failedCourses; self.unreadCourses = unreadCourses
        self.missingRequiredCourses = missingRequiredCourses
        self.estimatedGraduationCredits = estimatedGraduationCredits
    }
}

struct PlanOption: Identifiable {
    var id: String { planId }
    let planId: String
    let planName: String
    let planType: String
    let isCurrent: Bool

    init(planId: String, planName: String, planType: String = "主修", isCurrent: Bool = false) {
        self.planId = planId; self.planName = planName
        self.planType = planType; self.isCurrent = isCurrent
    }
}

struct PlanSelectionResponse {
    let options: [PlanOption]
    let hint: String?

    init(options: [PlanOption] = [], hint: String? = nil) {
        self.options = options; self.hint = hint
    }
}

// MARK: - User Credentials

struct UserCredentials: Codable {
    let userId: String
    let ecPassword: String
    let password: String
}

// MARK: - YKT Electricity Payment Models

struct SelectOption: Identifiable, Hashable {
    var id: String { value }
    let value: String
    let name: String

    static func parseList(_ response: String) -> [SelectOption] {
        guard !response.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return response.split(separator: "|").compactMap { item in
            let parts = item.trimmingCharacters(in: .whitespaces).split(separator: ",", maxSplits: 1)
            guard parts.count >= 2 else { return nil }
            return SelectOption(value: String(parts[0]).trimmingCharacters(in: .whitespaces),
                              name: String(parts[1]).trimmingCharacters(in: .whitespaces))
        }
    }
}

struct StudentInfo {
    let studentId: String
    let name: String
    let accountStatus: String
    let cardStatus: String
    let balance: Double
    let accId: String

    init(studentId: String = "", name: String = "", accountStatus: String = "",
         cardStatus: String = "", balance: Double = 0.0, accId: String = "") {
        self.studentId = studentId; self.name = name
        self.accountStatus = accountStatus; self.cardStatus = cardStatus
        self.balance = balance; self.accId = accId
    }

    static func fromHTML(_ html: String) -> StudentInfo {
        func extract(_ pattern: String) -> String {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: html) else { return "" }
            return String(html[range]).trimmingCharacters(in: .whitespaces)
        }
        let balanceStr = extract("校园余额</label>\\s*<label>([\\d.]+)</label>")
        let accId = extract("name=\"accId\"\\s+value\\s*=\\s*\"(\\d+)\"")
        return StudentInfo(
            studentId: extract("编号</label>\\s*<label>(\\d+)</label>"),
            name: extract("姓名</label>\\s*<label>([^<]+)</label>"),
            accountStatus: extract("账户状态</label>\\s*<label>([^<]+)</label>"),
            cardStatus: extract("卡状态</label>\\s*<label>([^<]+)</label>"),
            balance: Double(balanceStr) ?? 0.0,
            accId: accId
        )
    }
}

struct UtilityPaymentRequest {
    let roomId: String
    let dormId: String
    let dormName: String
    let buildName: String
    let floorName: String
    let roomName: String
    let accId: String
    let balances: String
    let payType: String
    let choosePayType: String
    let money: Int

    init(roomId: String, dormId: String, dormName: String, buildName: String,
         floorName: String, roomName: String, accId: String, balances: String,
         payType: String = "2", choosePayType: String = "1", money: Int) {
        self.roomId = roomId; self.dormId = dormId; self.dormName = dormName
        self.buildName = buildName; self.floorName = floorName; self.roomName = roomName
        self.accId = accId; self.balances = balances; self.payType = payType
        self.choosePayType = choosePayType; self.money = money
    }

    func toFormData() -> [String: String] {
        ["roomId": roomId, "dormId": dormId, "dormName": dormName,
         "buildName": buildName, "floorName": floorName, "roomName": roomName,
         "accId": accId, "balances": balances, "payType": payType,
         "choosePayType": choosePayType, "money": String(money)]
    }
}

struct UtilityPaymentResult {
    let success: Bool
    let message: String

    static func fromHTML(_ html: String) -> UtilityPaymentResult {
        let msgPattern = "id=\"message\"[^>]*value\\s*=\\s*\"([^\"]*)\""
        if let regex = try? NSRegularExpression(pattern: msgPattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           match.numberOfRanges > 1,
           let range = Range(match.range(at: 1), in: html) {
            let msg = String(html[range])
            if msg.contains("成功") { return UtilityPaymentResult(success: true, message: msg) }
            if !msg.isEmpty { return UtilityPaymentResult(success: false, message: msg) }
        }
        if html.contains("缴费成功") || html.contains("充值成功") {
            return UtilityPaymentResult(success: true, message: "充值成功")
        }
        return UtilityPaymentResult(success: false, message: "未知结果")
    }
}

struct ElectricPurchaseRecord: Identifiable {
    var id: String { "\(name)_\(purchaseDate)_\(amount)" }
    let name: String
    let studentId: String
    let area: String
    let roomInfo: String
    let amount: Double
    let purchaseDate: String
    let department: String

    init(name: String = "", studentId: String = "", area: String = "",
         roomInfo: String = "", amount: Double = 0.0, purchaseDate: String = "",
         department: String = "") {
        self.name = name; self.studentId = studentId; self.area = area
        self.roomInfo = roomInfo; self.amount = amount; self.purchaseDate = purchaseDate
        self.department = department
    }
}

struct ElectricPurchaseQueryResult {
    let startDate: String
    let endDate: String
    let records: [ElectricPurchaseRecord]

    var totalAmount: Double { records.reduce(0) { $0 + $1.amount } }
}
