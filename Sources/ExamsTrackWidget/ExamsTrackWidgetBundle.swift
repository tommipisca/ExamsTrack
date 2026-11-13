import SwiftUI
import WidgetKit

@main
struct ExamsTrackWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextExamWidget()
        TodayTasksWidget()
        CareerWidget()
        ExamLiveActivity()
        StudySessionLiveActivity()
        if #available(iOS 18.0, *) {
            NextTaskControl()
            StudySessionControl()
        }
    }
}
