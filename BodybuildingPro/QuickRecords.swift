import Foundation

extension Store {
    func previousSet(workout: Workout, exercise: Exercise, index: Int) -> (Date, SetEntry)? {
        for previous in data.workouts.filter({ $0.id != workout.id && $0.date < workout.date }).sorted(by: { $0.date > $1.date }) {
            guard let match = previous.exercises.first(where: { $0.lift == exercise.lift && $0.name == exercise.name }) else { continue }
            if match.sets.indices.contains(index), match.sets[index].done { return (previous.date, match.sets[index]) }
            if let last = match.sets.last(where: { $0.done }) { return (previous.date, last) }
        }
        return nil
    }
    var recentFoods: [MealEntry] {
        var ids = Set<UUID>()
        var entries: [MealEntry] = []
        for sheet in data.diets.filter({ $0.date <= Date() }).sorted(by: { $0.date > $1.date }) {
            for entry in sheet.meals.flatMap(\.entries).reversed() {
                if ids.insert(entry.food.id).inserted { entries.append(entry) }
                if entries.count == 6 { return entries }
            }
        }
        return entries
    }
}
