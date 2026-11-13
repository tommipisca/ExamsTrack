import Foundation
import Testing
@testable import ExamsCore

@Suite struct ProvisioningProfileTests {
    /// Un profilo vero è un plist XML dentro una firma CMS binaria: lo simuliamo con byte attorno.
    func profile(expiration: String) -> Data {
        var data = Data([0x30, 0x82, 0x1F, 0x00, 0xFF, 0x01])
        data.append(Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>AppIDName</key><string>XTool ExamsTrack</string>
            <key>ExpirationDate</key><date>\(expiration)</date>
        </dict>
        </plist>
        """.utf8))
        data.append(Data([0xA0, 0x82, 0x00, 0x13]))
        return data
    }

    @Test func readsExpirationDate() {
        let date = ProvisioningProfile.expirationDate(from: profile(expiration: "2026-10-20T08:15:00Z"))
        #expect(date == ISO8601DateFormatter().date(from: "2026-10-20T08:15:00Z"))
    }

    @Test func nilForGarbage() {
        #expect(ProvisioningProfile.expirationDate(from: Data("niente".utf8)) == nil)
    }
}

@Suite struct ExpirationNotificationTests {
    let settings = NotificationSettings(examReminders: [], dailyTaskSummary: false, hour: 9, minute: 30)

    @Test func dayBeforeExpirationEvenWithRemindersOff() {
        let plan = NotificationPlanner.plan(
            exams: [], settings: settings, now: date(2026, 10, 14, 10), calendar: rome,
            appExpiration: date(2026, 10, 20, 8, 15)
        )
        #expect(plan.map(\.id) == ["app-expiration"])
        #expect(plan.first?.fireDate == date(2026, 10, 19, 9, 30))
        #expect(plan.first?.title == "ExamsTrack scade domani")
    }

    @Test func expiringTomorrowMorningWarnsToday() {
        // Il giorno prima alle 9:30 è già passato: avvisa subito, entro un minuto.
        let now = date(2026, 10, 19, 18, 0)
        let plan = NotificationPlanner.plan(exams: [], settings: settings, now: now, calendar: rome,
                                            appExpiration: date(2026, 10, 20, 8, 15))
        #expect(plan.first?.fireDate == now.addingTimeInterval(60))
    }

    @Test func noWarningWhenAlreadyExpiredOrUnknown() {
        #expect(NotificationPlanner.plan(exams: [], settings: settings, now: date(2026, 10, 21), calendar: rome,
                                         appExpiration: date(2026, 10, 20)).isEmpty)
        #expect(NotificationPlanner.plan(exams: [], settings: settings, now: date(2026, 10, 14), calendar: rome,
                                         appExpiration: nil).isEmpty)
    }
}

@Suite struct ExamLinkTests {
    @Test func roundTrip() throws {
        let id = UUID()
        let url = ExamLink.url(for: id)
        #expect(url.absoluteString == "examstrack://exam/\(id.uuidString)")
        #expect(ExamLink.examID(from: url) == id)
    }

    @Test func taskLinkRoundTrip() {
        let exam = UUID()
        let task = UUID()
        let url = ExamLink.url(for: exam, taskID: task)
        #expect(ExamLink.examID(from: url) == exam)
        #expect(ExamLink.taskID(from: url) == task)
        #expect(ExamLink.taskID(from: ExamLink.url(for: exam)) == nil)
    }

    @Test func todayLink() {
        #expect(ExamLink.isToday(ExamLink.todayURL))
        #expect(ExamLink.examID(from: ExamLink.todayURL) == nil)
        #expect(!ExamLink.isToday(ExamLink.url(for: UUID())))
    }

    @Test func rejectsOtherURLs() {
        #expect(ExamLink.examID(from: URL(string: "https://example.com/exam/1")!) == nil)
        #expect(ExamLink.examID(from: URL(string: "examstrack://exam/non-un-id")!) == nil)
    }

    @Test func summaryCarriesIDs() throws {
        let next = Exam(name: "A", date: date(2026, 11, 20))
        let following = Exam(name: "B", date: date(2026, 12, 1))
        let summary = try #require(NextExamSummary.make(from: [next, following], today: date(2026, 11, 10), calendar: rome))
        #expect(summary.examID == next.id)
        #expect(summary.followingExams.first?.examID == following.id)
    }
}
