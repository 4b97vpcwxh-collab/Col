import Foundation

enum Lift: String, Codable, CaseIterable, Identifiable {
    case bench = "벤치프레스", squat = "스쿼트", deadlift = "데드리프트", press = "오버헤드 프레스", custom = "직접 입력"
    var id: String { rawValue }
    // Product defaults only, not physiological prescriptions. All durations are editable.
    var rests: [Int] {
        switch self {
        case .bench, .press: return [120, 180, 300]
        case .squat, .deadlift: return [180, 240, 300]
        case .custom: return [90, 120, 180]
        }
    }
}

struct Food: Codable, Identifiable {
    var id = UUID()
    var name: String
    var kcal100: Double
    var protein100: Double
    var carbs100: Double
    var fat100: Double
    var source: String = "사용자 입력"
    private static let referenceRows: [(String, Double, Double, Double, Double)] = [
        ("닭가슴살 · 껍질 없이 구운 것", 165.0, 31.0, 0.0, 3.6),
        ("흰쌀밥 · 조리 후", 130, 2.7, 28.2, 0.3),
        ("삶은 계란", 155, 12.6, 1.1, 10.6),
        ("바나나 · 껍질 제외", 89, 1.1, 22.8, 0.3),
        ("고구마 · 생것", 86, 1.6, 20.1, 0.1),
        ("오트밀 · 마른 것", 379, 13.2, 67.7, 6.5),
        ("감자 · 삶은 것", 87, 1.9, 20.1, 0.1),
        ("브로콜리 · 생것", 34, 2.8, 6.6, 0.4),
        ("아몬드", 579, 21.2, 21.6, 49.9),
        ("올리브오일", 884, 0, 0, 100)
    ]
    static let reference: [Food] = referenceRows.enumerated().map { index, item in
        Food(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!, name: item.0, kcal100: item.1, protein100: item.2, carbs100: item.3, fat100: item.4, source: "일반 식품 참고값 · 제품/조리법에 따라 다름")
    }

}

struct MealEntry: Codable, Identifiable {
    var id = UUID()
    var food: Food
    var grams: Double
    var kcal: Double { food.kcal100 * grams / 100 }
    var protein: Double { food.protein100 * grams / 100 }
}
struct Meal: Codable, Identifiable {
    var id = UUID()
    var title: String
    var entries: [MealEntry] = []
    var reminderHour: Int = 8
    var reminderMinute: Int = 0
    var reminderEnabled = false
}
struct DietSheet: Codable, Identifiable {
    var id = UUID()
    var title: String
    var date = Date()
    var meals: [Meal] = [Meal(title: "아침"), Meal(title: "점심", reminderHour: 13), Meal(title: "저녁", reminderHour: 19)]
    var kcal: Double { meals.flatMap(\.entries).reduce(0) { $0 + $1.kcal } }
}
struct SetEntry: Codable, Identifiable {
    var id = UUID()
    var kg: Double = 0
    var reps: Int = 10
    var done = false
}
struct Exercise: Codable, Identifiable {
    var id = UUID()
    var lift: Lift = .bench
    var name = "벤치프레스"
    var restSeconds = 120
    var sets: [SetEntry] = [SetEntry(), SetEntry(), SetEntry()]
}
struct Workout: Codable, Identifiable {
    var id = UUID()
    var title: String
    var date = Date()
    var exercises: [Exercise] = [Exercise()]
}
struct MediaRecord: Codable, Identifiable {
    var id = UUID()
    var filename: String
    var thumbnail: String?
    var isVideo: Bool
    var date = Date()
    var note = ""
}
struct Album: Codable, Identifiable {
    var id = UUID()
    var title: String
    var targetDate = Date()
    var coverID: UUID?
    var items: [MediaRecord] = []
    var cover: MediaRecord? { items.first(where: { $0.id == coverID }) ?? items.first }
    func countdown(at date: Date = Date()) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: targetDate)).day ?? 0
        return days == 0 ? "D-DAY" : days > 0 ? "D-\(days)" : "D+\(-days)"
    }
}
struct ProgressEntry: Codable, Identifiable {
    var id = UUID()
    var lift: Lift
    var name: String
    var date = Date()
    var kg: Double
    var reps: Int
    var note: String
}
struct RestState: Codable {
    var name: String
    var deadline: Date?
    var pausedSeconds: Int?
}
struct AppData: Codable {
    var schemaVersion = 1
    var foods: [Food] = []
    var diets: [DietSheet] = []
    var workouts: [Workout] = []
    var albums: [Album] = []
    var progress: [ProgressEntry] = []
    var timer: RestState?
}

enum Validation {
    static func number(_ text: String) -> Double? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value.isFinite, value >= 0 else { return nil }
        return value
    }
    static func nonempty(_ text: String) -> Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

extension Workout {
    func repeated() -> Workout {
        var copy = Workout(title: title)
        copy.exercises = exercises.map { exercise in
            var result = exercise
            result.id = UUID()
            result.sets = exercise.sets.map { set in
                var item = set; item.id = UUID(); item.done = false; return item
            }
            return result
        }
        return copy
    }
}

