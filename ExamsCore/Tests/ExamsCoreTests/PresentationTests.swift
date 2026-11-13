import Foundation
import Testing
@testable import ExamsCore

@Suite struct BalancedColorTests {
    @Test func picksLeastUsedThenLowestIndex() {
        #expect(Palette.balancedColorIndex(used: []) == 0)
        #expect(Palette.balancedColorIndex(used: [0]) == 1)
        #expect(Palette.balancedColorIndex(used: [0, 0, 1]) == 2)
        #expect(Palette.balancedColorIndex(used: Array(0..<Palette.examColors.count)) == 0)
    }

    @Test func ignoresOutOfRangeIndices() {
        #expect(Palette.balancedColorIndex(used: [-1, 99]) == 0)
    }

    @Test func paletteIsLargeAndDistinct() {
        #expect(Palette.examColors.count >= 12)
        #expect(Set(Palette.examColors).count == Palette.examColors.count)
        // Rosso e oro restano riservati a urgenza e lode.
        #expect(!Palette.examColors.contains(Palette.danger))
        #expect(!Palette.examColors.contains(Palette.gold))
    }
}

@Suite struct UrgencyTests {
    @Test func levels() {
        #expect(Urgency(days: 30) == .calm)
        #expect(Urgency(days: 8) == .calm)
        #expect(Urgency(days: 7) == .soon)
        #expect(Urgency(days: 3) == .soon)
        #expect(Urgency(days: 2) == .urgent)
        #expect(Urgency(days: 0) == .urgent)
    }
}

@Suite struct TodayMarkerTests {
    let today = date(2026, 11, 10, 15)

    func exam(_ days: [Int], examDay: Int = 30) -> Exam {
        Exam(name: "A", date: date(2026, 11, examDay), tasks: days.enumerated().map { i, day in
            StudyTask(title: "T\(i)", dueDate: date(2026, 11, day))
        })
    }

    @Test func betweenPastAndFutureTasks() {
        #expect(exam([5, 8, 12, 20]).todayMarkerIndex(today: today, calendar: rome) == 2)
    }

    @Test func taskDueTodayComesAfterMarker() {
        #expect(exam([5, 10, 12]).todayMarkerIndex(today: today, calendar: rome) == 1)
    }

    @Test func allTasksPastPutsMarkerBeforeExam() {
        #expect(exam([1, 2]).todayMarkerIndex(today: today, calendar: rome) == 2)
    }

    @Test func noTasksPutsMarkerFirst() {
        #expect(exam([]).todayMarkerIndex(today: today, calendar: rome) == 0)
    }

    @Test func noMarkerForPastExam() {
        #expect(exam([1], examDay: 5).todayMarkerIndex(today: today, calendar: rome) == nil)
    }
}
