import Foundation

private struct PendingClubSubmission {
    let clubId: String
    let previousApplication: LaborClubApplication?
}

@MainActor @Observable
final class LaborClubViewModel {
    var isLoading = false
    var progress: LaborClubProgressInfo?
    var joinedActivities: [LaborClubActivity] = []
    var clubs: [LaborClubInfo] = []
    var membership: LaborClubMembershipState = .notJoined
    var clubStatusError: String?
    var submittedStatusSyncing = false
    var clubDirectory: [LaborClubDirectoryItem] = []
    var isDirectoryLoading = false
    var directoryError: String?
    var clubActionResult: String?
    var clubSubmissionSucceeded = false
    var signInResult: SignInResponse?
    var applyResult: String?
    var error: String?
    var ongoingActivities: [LaborClubActivity] = []
    var finishedActivities: [LaborClubActivity] = []
    var availableActivities: [LaborClubActivity] = []
    var fullActivities: [LaborClubActivity] = []
    var notStartedActivities: [LaborClubActivity] = []
    var expiredActivities: [LaborClubActivity] = []
    private(set) var service: LaborClubService?
    private var activeUserId = ""
    private var loadTask: Task<Void, Never>?
    private var directoryTask: Task<Void, Never>?
    private var clubApplyTask: Task<Void, Never>?
    private var pendingClubSubmission: PendingClubSubmission?

    var isSubmittingClub: Bool { membership.status == .submitting }

    func initialize(service: LaborClubService, userId: String) {
        let normalizedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let userChanged = activeUserId != normalizedUserId
        let serviceChanged = self.service !== service
        if userChanged || serviceChanged {
            let retainedSubmission = userChanged ? nil : pendingClubSubmission
            loadTask?.cancel()
            directoryTask?.cancel()
            clubApplyTask?.cancel()
            activeUserId = normalizedUserId
            resetLoadedData()
            pendingClubSubmission = retainedSubmission
        }
        self.service = service
    }

    func loadAll() {
        guard let service, !activeUserId.isEmpty else { return }
        let userId = activeUserId
        loadTask?.cancel()
        loadTask = Task {
            isLoading = true
            error = nil
            clubStatusError = nil

            async let progressRequest = service.getProgress()
            async let joinedRequest = service.getJoinedActivities()
            async let clubsRequest = service.getJoinedClubs()
            let (progressResult, joinedResult, clubsResult) = await (
                progressRequest,
                joinedRequest,
                clubsRequest
            )
            guard isCurrentUser(userId) else { return }

            var joined = joinedResult.data ?? []
            var currentClubs = clubsResult.data ?? []
            var latestApplication: LaborClubApplication?
            var currentClubStatusError = clubsResult.error
            var applicationStatusLoaded = false

            if clubsResult.success && currentClubs.isEmpty {
                let applicationResult = await service.getLatestClubApplication()
                guard isCurrentUser(userId) else { return }
                if applicationResult.success {
                    applicationStatusLoaded = true
                    latestApplication = applicationResult.data ?? nil
                    if latestApplication?.reviewStatus == .approved {
                        let refreshedClubs = await service.getJoinedClubs()
                        guard isCurrentUser(userId) else { return }
                        if refreshedClubs.success, let data = refreshedClubs.data, !data.isEmpty {
                            currentClubs = data
                        } else if !refreshedClubs.success {
                            currentClubStatusError = refreshedClubs.error
                        }
                    }
                } else {
                    currentClubStatusError = applicationResult.error
                }
            }

            for index in joined.indices {
                guard isCurrentUser(userId) else { return }
                let signResult = await service.getSignList(activityId: joined[index].activityId)
                if signResult.success { joined[index].signList = signResult.data }
            }

            var allActivities: [LaborClubActivity] = []
            for club in currentClubs {
                guard isCurrentUser(userId) else { return }
                let result = await service.getClubActivities(clubId: club.clubInfoId)
                if result.success { allActivities.append(contentsOf: result.data ?? []) }
            }
            var seenActivityIds = Set<String>()
            allActivities = allActivities.filter {
                seenActivityIds.insert($0.activityId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).inserted
            }
            guard isCurrentUser(userId) else { return }

            progress = progressResult.data
            joinedActivities = joined
            clubs = currentClubs
            let unresolvedSubmission = pendingClubSubmission
            if !currentClubs.isEmpty {
                pendingClubSubmission = nil
                membership = resolveLaborClubMembership(
                    joinedClubs: currentClubs,
                    latestApplication: latestApplication
                )
                submittedStatusSyncing = false
            } else if let unresolvedSubmission, applicationStatusLoaded {
                let resolution = resolveLaborClubSubmission(
                    joinedClubs: currentClubs,
                    latestApplication: latestApplication,
                    expectedClubId: unresolvedSubmission.clubId,
                    previousApplication: unresolvedSubmission.previousApplication
                )
                membership = resolution.membership
                submittedStatusSyncing = resolution.isStatusSyncing
                if !resolution.isStatusSyncing { pendingClubSubmission = nil }
            } else if unresolvedSubmission != nil {
                membership = LaborClubMembershipState(status: .pending, latestApplication: nil)
                submittedStatusSyncing = true
            } else {
                membership = resolveLaborClubMembership(
                    joinedClubs: currentClubs,
                    latestApplication: latestApplication
                )
                submittedStatusSyncing = false
            }
            clubStatusError = currentClubStatusError
            error = progressResult.error ?? joinedResult.error
            categorize(joined: joined, all: allActivities)
            isLoading = false
        }
    }

    func loadClubDirectory(force: Bool = false) {
        guard let service, !activeUserId.isEmpty else { return }
        if !force && (!clubDirectory.isEmpty || isDirectoryLoading) { return }
        let userId = activeUserId
        directoryTask?.cancel()
        directoryTask = Task {
            isDirectoryLoading = true
            directoryError = nil
            let result = await service.getClubDirectory()
            guard isCurrentUser(userId) else { return }
            clubDirectory = result.data ?? []
            directoryError = result.error
            isDirectoryLoading = false
        }
    }

    func applyClub(clubId: String, reason: String) {
        guard let service, !activeUserId.isEmpty, !isSubmittingClub else { return }
        guard let club = clubDirectory.first(where: { $0.id.caseInsensitiveCompare(clubId) == .orderedSame }),
              club.canApply else {
            clubActionResult = "当前俱乐部不可申请"
            return
        }
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReason.isEmpty else {
            clubActionResult = "请填写申请理由"
            return
        }

        let userId = activeUserId
        clubApplyTask?.cancel()
        clubApplyTask = Task {
            let previousMembership = membership
            membership = resolveLaborClubMembership(
                joinedClubs: clubs,
                latestApplication: previousMembership.latestApplication,
                isSubmitting: true
            )
            clubActionResult = nil
            clubSubmissionSucceeded = false
            submittedStatusSyncing = false

            let submitResult = await service.applyClub(clubId: club.id, reason: normalizedReason)
            guard isCurrentUser(userId) else { return }
            guard submitResult.success else {
                membership = previousMembership
                clubActionResult = submitResult.error ?? "申请提交失败"
                return
            }

            async let applicationRequest = service.getLatestClubApplication()
            async let refreshedClubsRequest = service.getJoinedClubs()
            let (applicationResult, refreshedClubsResult) = await (
                applicationRequest,
                refreshedClubsRequest
            )
            guard isCurrentUser(userId) else { return }
            let refreshedClubs = refreshedClubsResult.success ? (refreshedClubsResult.data ?? []) : clubs
            let latest = applicationResult.success ? (applicationResult.data ?? nil) : nil
            let resolution = resolveLaborClubSubmission(
                joinedClubs: refreshedClubs,
                latestApplication: latest,
                expectedClubId: club.id,
                previousApplication: previousMembership.latestApplication
            )
            pendingClubSubmission = resolution.isStatusSyncing
                ? PendingClubSubmission(
                    clubId: club.id,
                    previousApplication: previousMembership.latestApplication
                )
                : nil
            clubs = refreshedClubs
            membership = resolution.membership
            submittedStatusSyncing = resolution.isStatusSyncing
            if resolution.isStatusSyncing {
                clubActionResult = "申请已提交，状态同步中"
            } else {
                switch resolution.membership.status {
                case .pending: clubActionResult = "申请已提交，等待审批"
                case .approvedSyncing: clubActionResult = "审核已通过，正在同步俱乐部信息"
                case .joined: clubActionResult = "申请已通过，俱乐部信息已同步"
                case .rejected:
                    let reply = resolution.membership.latestApplication?.replyComment ?? ""
                    clubActionResult = reply.isEmpty ? "申请状态已更新" : reply
                default: clubActionResult = "申请状态已更新"
                }
            }
            clubSubmissionSucceeded = true
            if resolution.membership.status == .joined { loadAll() }
        }
    }

    func consumeClubSubmissionSuccess() { clubSubmissionSucceeded = false }
    func clearClubActionResult() { clubActionResult = nil }

    private func categorize(joined: [LaborClubActivity], all: [LaborClubActivity]) {
        let now = Date()
        let joinedIds = Set(joined.map(\.activityId))

        var ongoing: [LaborClubActivity] = []
        var finished: [LaborClubActivity] = []
        for activity in joined {
            if let start = Self.parseDate(activity.startTime), start > now {
                ongoing.append(activity)
            } else {
                finished.append(activity)
            }
        }

        var available: [LaborClubActivity] = []
        var full: [LaborClubActivity] = []
        var notStarted: [LaborClubActivity] = []
        var expired: [LaborClubActivity] = []
        for activity in all where !joinedIds.contains(activity.activityId) {
            guard let signStart = Self.parseDate(activity.signUpStartTime),
                  let signEnd = Self.parseDate(activity.signUpEndTime),
                  let end = Self.parseDate(activity.endTime) else {
                expired.append(activity)
                continue
            }
            if end < now {
                expired.append(activity)
            } else if signStart > now {
                notStarted.append(activity)
            } else if signEnd > now {
                if activity.memberNum >= activity.peopleNum {
                    full.append(activity)
                } else {
                    available.append(activity)
                }
            } else if activity.memberNum >= activity.peopleNum {
                full.append(activity)
            } else {
                expired.append(activity)
            }
        }
        ongoingActivities = ongoing
        finishedActivities = finished
        availableActivities = available
        fullActivities = full
        notStartedActivities = notStarted.sorted { $0.signUpStartTime < $1.signUpStartTime }
        expiredActivities = expired
    }

    private static func parseDate(_ value: String) -> Date? {
        let cleaned = value.replacingOccurrences(of: "T", with: " ")
            .components(separatedBy: ".").first ?? value
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) { return date }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: value)
    }

    func applyActivity(activityId: String) {
        guard let service else { return }
        Task {
            let result = await service.applyActivity(activityId: activityId)
            applyResult = result.success ? "报名成功" : (result.error ?? "报名失败")
            if result.success { loadAll() }
        }
    }

    func scanSignIn(qrData: String) {
        guard let service else { return }
        let baseLng = 117.424733
        let baseLat = 32.905237
        let jitter = 0.0001
        let lng = baseLng + Double.random(in: -jitter...jitter)
        let lat = baseLat + Double.random(in: -jitter...jitter)
        Task {
            isLoading = true
            signInResult = nil
            let result = await service.scanSignIn(qrData: qrData, location: "\(lng),\(lat)")
            signInResult = result.data
            error = result.error
            isLoading = false
            if result.data?.isSuccess == true { loadAll() }
        }
    }

    func clearSignInResult() { signInResult = nil }
    func clearApplyResult() { applyResult = nil }

    private func isCurrentUser(_ userId: String) -> Bool {
        !Task.isCancelled && activeUserId == userId
    }

    private func resetLoadedData() {
        isLoading = false
        progress = nil
        joinedActivities = []
        clubs = []
        membership = .notJoined
        clubStatusError = nil
        submittedStatusSyncing = false
        pendingClubSubmission = nil
        clubDirectory = []
        isDirectoryLoading = false
        directoryError = nil
        clubActionResult = nil
        clubSubmissionSucceeded = false
        signInResult = nil
        applyResult = nil
        error = nil
        ongoingActivities = []
        finishedActivities = []
        availableActivities = []
        fullActivities = []
        notStartedActivities = []
        expiredActivities = []
    }
}
