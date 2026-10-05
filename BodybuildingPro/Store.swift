import SwiftUI
import UserNotifications

@MainActor
final class Store: ObservableObject {
    @Published private(set) var data = AppData()
    @Published var error: String?
    @Published private(set) var readOnly = false
    let root: URL
    var stateURL: URL { root.appendingPathComponent("records.json") }
    var mediaRoot: URL { root.appendingPathComponent("media", isDirectory: true) }

    init() {
        root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("BodybuildingPro", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: mediaRoot, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: stateURL.path) {
                data = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: stateURL))
                guard data.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
            }
        } catch {
            // Never silently overwrite an unreadable database with an empty one.
            readOnly = true
            self.error = "기존 기록을 열지 못했습니다. 원본 보호를 위해 저장을 중단했습니다. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func update(_ change: (inout AppData) -> Void) -> Bool {
        guard !readOnly else { error = "기록 보호 모드입니다. 기존 파일을 복구한 뒤 다시 열어 주세요."; return false }
        var candidate = data
        change(&candidate)
        do {
            let encoded = try JSONEncoder().encode(candidate)
            try encoded.write(to: stateURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            data = candidate
            return true
        } catch { self.error = "저장 실패: \(error.localizedDescription)"; return false }
    }

    func mediaURL(_ name: String) -> URL { mediaRoot.appendingPathComponent(name) }

    func oneRepMax(_ lift: Lift) -> Double? {
        let manual = data.progress.filter { $0.lift == lift && $0.reps == 1 && $0.kg > 0 }.map(\.kg)
        var logged: [Double] = []
        for workout in data.workouts {
            for exercise in workout.exercises where exercise.lift == lift {
                for set in exercise.sets where set.done && set.reps == 1 && set.kg > 0 { logged.append(set.kg) }
            }
        }
        return (manual + logged).max()
    }

    func removeMeal(sheetID: UUID, mealID: UUID) {
        if update({ state in
            guard let i = state.diets.firstIndex(where: { $0.id == sheetID }) else { return }
            state.diets[i].meals.removeAll { $0.id == mealID }
        }) { NotificationService.cancel("meal-\(mealID)") }
    }
}

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    func install() { UNUserNotificationCenter.current().delegate = self }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }
    static func cancel(_ id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }
    static func permission() async throws {
        let center = UNUserNotificationCenter.current()
        let accepted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        if !accepted { throw NSError(domain: "알림", code: 1, userInfo: [NSLocalizedDescriptionKey: "알림이 꺼져 있습니다. 설정에서 보디빌딩Pro의 알림과 소리를 허용해 주세요."]) }
    }
    static func rest(name: String, seconds: Int) async throws {
        try await permission()
        let content = UNMutableNotificationContent()
        content.title = "휴식 끝 · \(name)"
        content.body = "다음 세트를 준비하세요."
        content.sound = .default
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "rest", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: Double(max(1, seconds)), repeats: false)))
    }
    static func meal(_ meal: Meal) async throws {
        if !meal.reminderEnabled { cancel("meal-\(meal.id)"); return }
        try await permission()
        let content = UNMutableNotificationContent()
        content.title = "\(meal.title) 식단 알림"
        content.body = "오늘의 식사를 기록해 보세요."
        content.sound = .default
        let components = DateComponents(hour: meal.reminderHour, minute: meal.reminderMinute)
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "meal-\(meal.id)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
    }
}
