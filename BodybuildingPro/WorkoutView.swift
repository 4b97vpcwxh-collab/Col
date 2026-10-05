import SwiftUI

struct WorkoutView: View {
    @EnvironmentObject var store: Store
    @State private var add = false
    @State private var title = ""
    @State private var selected: UUID?
    @State private var deleteID: UUID?
    private var todayWorkout: Workout? {
        store.data.workouts.first { Calendar.current.isDateInToday($0.date) && $0.exercises.flatMap(\.sets).contains { !$0.done } }
    }
    var body: some View {
        List {
            if store.data.timer != nil { Section { TimerCard() } }
            Section {
                if let todayWorkout {
                    NavigationLink { WorkoutDetail(workoutID: todayWorkout.id) } label: {
                        Label("하던 운동 이어하기 · " + todayWorkout.title, systemImage: "play.fill").font(.headline)
                    }
                }
                if let previous = store.data.workouts.filter({ $0.date <= Date() }).sorted(by: { $0.date > $1.date }).first {
                    Button { let copy = previous.repeated(); if store.update({ $0.workouts.insert(copy, at: 0) }) { selected = copy.id } } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Label("지난 운동 그대로 시작", systemImage: "arrow.clockwise").font(.headline)
                            Text(previous.title).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(Lift.allCases.filter { $0 != .custom }) { lift in
                    Button { begin(lift) } label: { Label(lift.rawValue, systemImage: "plus.circle.fill") }
                }
            } header: { Text("바로 시작") } footer: { Text("중량과 횟수 입력 → 완료 체크 → 자동 휴식") }
            Section("내 운동 시트") {
                ForEach(store.data.workouts.sorted { $0.date > $1.date }) { workout in
                    HStack {
                        NavigationLink { WorkoutDetail(workoutID: workout.id) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(workout.title).font(.headline)
                                let sets = workout.exercises.flatMap(\.sets)
                                Text("\(workout.date.formatted(date: .abbreviated, time: .omitted)) · \(sets.filter(\.done).count)/\(sets.count)세트").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Button("삭제", systemImage: "trash", role: .destructive) { deleteID = workout.id }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44)
                    }
                }
                Button("시트 추가", systemImage: "plus") { title = "오늘의 운동"; add = true }
            }
            Section { NavigationLink("자유 타이머", systemImage: "timer") { FreeTimerView() } }
        }.navigationTitle("운동")
            .navigationDestination(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) { if let selected { WorkoutDetail(workoutID: selected) } }
            .alert("운동 시트 추가", isPresented: $add) {
                TextField("제목", text: $title)
                Button("추가") { if Validation.nonempty(title) { let workout = Workout(title: title); if store.update({ $0.workouts.insert(workout, at: 0) }) { selected = workout.id } } }
                Button("취소", role: .cancel) {}
            }
            .confirmationDialog("이 시트와 세트를 삭제할까요?", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } }), titleVisibility: .visible) {
                Button("삭제", role: .destructive) { if let id = deleteID { store.update { $0.workouts.removeAll { $0.id == id } } }; deleteID = nil }
            }
    }
    private func begin(_ lift: Lift) {
        var exercise = Exercise(lift: lift, name: lift.rawValue, restSeconds: lift.rests[0])
        if let previous = store.data.workouts.filter({ $0.date <= Date() }).sorted(by: { $0.date > $1.date }).flatMap(\.exercises).first(where: { $0.lift == lift && $0.name == lift.rawValue }) {
            exercise.restSeconds = previous.restSeconds
            exercise.sets = previous.sets.map { SetEntry(kg: $0.kg, reps: $0.reps) }
            if exercise.sets.isEmpty { exercise.sets = [SetEntry(), SetEntry(), SetEntry()] }
        }
        let workout = Workout(title: lift.rawValue, exercises: [exercise])
        if store.update({ $0.workouts.insert(workout, at: 0) }) { selected = workout.id }
    }
}

@MainActor
func startRest(store: Store, name: String, seconds: Int) async {
    guard seconds > 0, seconds <= 3600 else { return }
    // One active rest timer; replacing it also replaces the pending notification.
    guard store.update({ $0.timer = RestState(name: name, deadline: Date().addingTimeInterval(Double(seconds)), pausedSeconds: nil) }) else { return }
    NotificationService.cancel("rest")
    do { try await NotificationService.rest(name: name, seconds: seconds) }
    catch { store.error = "화면 타이머는 실행 중입니다. \(error.localizedDescription)" }
}

struct TimerCard: View {
    @EnvironmentObject var store: Store
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let timer = store.data.timer {
                let left = timer.pausedSeconds ?? max(0, Int(ceil((timer.deadline ?? context.date).timeIntervalSince(context.date))))
                VStack(alignment: .leading, spacing: 12) {
                    Text(timer.name).font(.headline)
                    Text(String(format: "%02d:%02d", left / 60, left % 60)).font(.system(size: 52, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(AppTheme.green)
                    if left == 0 { Text("휴식 끝 · 다음 세트를 준비하세요") }
                    HStack {
                        if left > 0 {
                            Button(timer.pausedSeconds == nil ? "일시정지" : "계속") {
                                if timer.pausedSeconds == nil {
                                    if store.update({ $0.timer = RestState(name: timer.name, deadline: nil, pausedSeconds: left) }) { NotificationService.cancel("rest") }
                                } else { Task { await startRest(store: store, name: timer.name, seconds: left) } }
                            }
                        }
                        Button("종료", role: .destructive) { if store.update({ $0.timer = nil }) { NotificationService.cancel("rest") } }
                    }.buttonStyle(.bordered)
                }
            } else { Label("세트를 체크하면 휴식이 시작됩니다", systemImage: "timer").foregroundStyle(.secondary) }
        }
    }
}

struct FreeTimerView: View {
    @EnvironmentObject var store: Store
    @State private var name = "자유 휴식"
    @State private var seconds = 120
    var body: some View {
        Form {
            TextField("타이머 이름", text: $name)
            Stepper("\(seconds)초", value: $seconds, in: 15...3600, step: 15)
            Button("시작") { Task { await startRest(store: store, name: name, seconds: seconds) } }.disabled(!Validation.nonempty(name))
            TimerCard()
            Text("동시에 하나의 휴식 타이머를 사용합니다. 시작하면 이전 타이머가 대체됩니다.").font(.caption)
        }.navigationTitle("프리 타이머")
    }
}

struct WorkoutDetail: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    let workoutID: UUID
    @State private var rename = false
    @State private var title = ""
    @State private var deleting = false
    private var workout: Workout? { store.data.workouts.first { $0.id == workoutID } }
    var body: some View {
        List {
            Section { TimerCard() }
            if let workout {
                DatePicker("운동 날짜", selection: Binding(get: { workout.date }, set: { date in edit { $0.date = date } }), displayedComponents: .date)
                ForEach(workout.exercises) { exercise in
                    Section(exercise.name) {
                        NavigationLink("운동 이름 · 휴식 설정") { ExerciseSettings(workoutID: workoutID, original: exercise) }
                        ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                            VStack(alignment: .leading, spacing: 7) {
                                if let previous = store.previousSet(workout: workout, exercise: exercise, index: index) {
                                    Text("지난 기록 · \(previous.0.formatted(date: .abbreviated, time: .omitted)) · \(previous.1.kg, specifier: "%g")kg × \(previous.1.reps)회")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                HStack {
                                    SetRow(workoutID: workoutID, exerciseID: exercise.id, index: index, set: set)
                                    Button("세트 삭제", systemImage: "minus.circle", role: .destructive) {
                                        edit { w in if let i = w.exercises.firstIndex(where: { $0.id == exercise.id }) { w.exercises[i].sets.removeAll { $0.id == set.id } } }
                                    }.labelStyle(.iconOnly).buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44)
                                }
                            }
                                .swipeActions { Button("삭제", role: .destructive) { edit { w in if let i = w.exercises.firstIndex(where: { $0.id == exercise.id }) { w.exercises[i].sets.removeAll { $0.id == set.id } } } } }
                        }
                        Button("세트 추가", systemImage: "plus") {
                            edit { w in
                                if let i = w.exercises.firstIndex(where: { $0.id == exercise.id }) {
                                    let last = w.exercises[i].sets.last
                                    w.exercises[i].sets.append(SetEntry(kg: last?.kg ?? 0, reps: last?.reps ?? 10))
                                }
                            }
                        }
                    }
                }
                Button("운동 추가", systemImage: "plus.circle") { edit { $0.exercises.append(Exercise(lift: .custom, name: "새 운동", restSeconds: 90)) } }
                Button("시트 복제 · 완료 체크 초기화") {
                    var copy = Workout(title: workout.title + " 복사")
                    copy.exercises = workout.exercises.map { e in
                        var item = e; item.id = UUID()
                        item.sets = e.sets.map { s in var set = s; set.id = UUID(); set.done = false; return set }
                        return item
                    }
                    store.update { $0.workouts.insert(copy, at: 0) }
                }
                Button("운동 시트 삭제", role: .destructive) { deleting = true }
            }
        }.navigationTitle(workout?.title ?? "운동")
            .toolbar { Button("제목 수정") { title = workout?.title ?? ""; rename = true } }
            .alert("제목 수정", isPresented: $rename) {
                TextField("제목", text: $title)
                Button("저장") { if Validation.nonempty(title) { edit { $0.title = title } } }
                Button("취소", role: .cancel) {}
            }
            .confirmationDialog("시트와 세트 기록을 삭제할까요?", isPresented: $deleting, titleVisibility: .visible) {
                Button("삭제", role: .destructive) { if store.update({ $0.workouts.removeAll { $0.id == workoutID } }) { dismiss() } }
            }
    }
    private func edit(_ change: (inout Workout) -> Void) {
        store.update { if let i = $0.workouts.firstIndex(where: { $0.id == workoutID }) { change(&$0.workouts[i]) } }
    }
}

struct SetRow: View {
    @EnvironmentObject var store: Store
    let workoutID: UUID
    let exerciseID: UUID
    let index: Int
    let set: SetEntry
    @State private var kg = ""
    @State private var reps = ""
    @FocusState private var focused: Bool
    var body: some View {
        HStack {
            Text("\(index + 1)").frame(width: 20)
            TextField("kg", text: $kg).keyboardType(.decimalPad).focused($focused).multilineTextAlignment(.center).textFieldStyle(.roundedBorder).frame(minWidth: 44)
            Text("kg").font(.caption)
            TextField("회", text: $reps).keyboardType(.numberPad).focused($focused).multilineTextAlignment(.center).textFieldStyle(.roundedBorder).frame(minWidth: 32)
            Text("회").font(.caption)
            Button { save(toggle: true); focused = false } label: {
                Image(systemName: set.done ? "checkmark.circle.fill" : "circle").font(.title).foregroundStyle(set.done ? AppTheme.green : Color.secondary)
            }.buttonStyle(.borderless).accessibilityLabel(set.done ? "세트 완료 취소" : "세트 완료 후 휴식 시작")
        }.onAppear { kg = String(format: "%g", set.kg); reps = "\(set.reps)" }
            .onChange(of: kg) { _, _ in saveValidDraft() }
            .onChange(of: reps) { _, _ in saveValidDraft() }
            .onChange(of: focused) { _, newValue in if !newValue { save(toggle: false) } }
    }
    private func saveValidDraft() {
        guard focused, let weight = Validation.number(kg), weight <= 1500, let count = Int(reps), (1...1000).contains(count) else { return }
        save(toggle: false)
    }
    private func save(toggle: Bool) {
        guard let weight = Validation.number(kg), weight <= 1500, let count = Int(reps), count > 0, count <= 1000 else { store.error = "중량 0~1500kg, 횟수 1~1000회를 입력해 주세요."; return }
        var duration: Int?
        var name = ""
        let saved = store.update { data in
            guard let i = data.workouts.firstIndex(where: { $0.id == workoutID }), let j = data.workouts[i].exercises.firstIndex(where: { $0.id == exerciseID }), let k = data.workouts[i].exercises[j].sets.firstIndex(where: { $0.id == set.id }) else { return }
            data.workouts[i].exercises[j].sets[k].kg = weight
            data.workouts[i].exercises[j].sets[k].reps = count
            if toggle {
                data.workouts[i].exercises[j].sets[k].done.toggle()
                if data.workouts[i].exercises[j].sets[k].done {
                    duration = data.workouts[i].exercises[j].restSeconds; name = data.workouts[i].exercises[j].name
                }
            }
        }
        if saved, let duration { Task { await startRest(store: store, name: name, seconds: duration) } }
    }
}

struct ExerciseSettings: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    let workoutID: UUID
    @State private var exercise: Exercise
    @State private var deleting = false
    init(workoutID: UUID, original: Exercise) { self.workoutID = workoutID; _exercise = State(initialValue: original) }
    var body: some View {
        Form {
            Picker("종류", selection: $exercise.lift) { ForEach(Lift.allCases) { Text($0.rawValue).tag($0) } }
                .onChange(of: exercise.lift) { _, lift in if lift != .custom { exercise.name = lift.rawValue }; exercise.restSeconds = lift.rests[0] }
            TextField("운동 이름", text: $exercise.name)
            Section("휴식 프리셋 · 모두 수정 가능") {
                let labels = ["기본 휴식", "빡센 세트 후", "느긋한 휴식"]
                ForEach(0..<3) { i in Button("\(labels[i]) · \(exercise.lift.rests[i])초") { exercise.restSeconds = exercise.lift.rests[i] } }
                Stepper("\(exercise.restSeconds)초", value: $exercise.restSeconds, in: 15...3600, step: 15)
                Text("프리셋은 편의용 초기값입니다. 빡센 세트 후에는 회복 시간을 더 주는 의미로 설정했습니다.").font(.caption)
            }
            Button("저장") {
                if store.update({ data in
                    if let i = data.workouts.firstIndex(where: { $0.id == workoutID }), let j = data.workouts[i].exercises.firstIndex(where: { $0.id == exercise.id }) { data.workouts[i].exercises[j] = exercise }
                }) { dismiss() }
            }.disabled(!Validation.nonempty(exercise.name))
            Button("운동 삭제", role: .destructive) { deleting = true }
        }.navigationTitle("운동 설정")
            .confirmationDialog("이 운동과 세트를 삭제할까요?", isPresented: $deleting, titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    if store.update({ data in if let i = data.workouts.firstIndex(where: { $0.id == workoutID }) { data.workouts[i].exercises.removeAll { $0.id == exercise.id } } }) { dismiss() }
                }
            }
    }
}
