import SwiftUI

struct DietView: View {
    @EnvironmentObject var store: Store
    @State private var newSheet = false
    @State private var title = ""
    var body: some View {
        List {
            Section {
                if let today = store.data.diets.first(where: { Calendar.current.isDateInToday($0.date) }) {
                    NavigationLink { DietDetail(sheetID: today.id) } label: { Label("오늘 식단 이어쓰기", systemImage: "pencil.line").font(.headline) }
                } else {
                    Button("오늘 식단 만들기", systemImage: "plus.circle.fill") { store.update { $0.diets.insert(DietSheet(title: "오늘의 식단"), at: 0) } }
                }
            }
            if store.data.diets.isEmpty { EmptyHint(title: "첫 식단 시트를 만드세요", description: "아침·점심·저녁이 함께 만들어집니다.") }
            ForEach(store.data.diets) { sheet in
                NavigationLink { DietDetail(sheetID: sheet.id) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(sheet.title).font(.headline)
                        Text("\(sheet.date.formatted(date: .abbreviated, time: .omitted)) · \(sheet.kcal, specifier: "%.0f") kcal").foregroundStyle(.secondary)
                    }
                }
            }
        }.navigationTitle("식단")
            .toolbar { Button("시트 추가", systemImage: "plus") { title = "오늘의 식단"; newSheet = true } }
            .alert("식단 시트 추가", isPresented: $newSheet) {
                TextField("제목", text: $title)
                Button("추가") { if Validation.nonempty(title) { store.update { $0.diets.insert(DietSheet(title: title), at: 0) } } }
                Button("취소", role: .cancel) {}
            }
    }
}

struct DietDetail: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    let sheetID: UUID
    @State private var rename = false
    @State private var addMeal = false
    @State private var deleteSheet = false
    @State private var text = ""
    private var sheet: DietSheet? { store.data.diets.first { $0.id == sheetID } }
    var body: some View {
        List {
            if let sheet {
                Section {
                    Text("\(sheet.kcal, specifier: "%.0f") kcal").font(.largeTitle.bold()).foregroundStyle(AppTheme.green)
                    Text("단백질 \(sheet.meals.flatMap(\.entries).reduce(0) { $0 + $1.protein }, specifier: "%.1f") g")
                    DatePicker("기록 날짜", selection: Binding(get: { sheet.date }, set: { date in edit { $0.date = date } }), displayedComponents: .date)
                }
                ForEach(sheet.meals) { meal in
                    Section(meal.title) {
                        ForEach(meal.entries) { entry in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(entry.food.name)
                                    Text("\(entry.grams, specifier: "%.0f")g · \(entry.food.source)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(entry.kcal, specifier: "%.0f") kcal")
                            }.swipeActions { Button("삭제", role: .destructive) { editMeal(meal.id) { $0.entries.removeAll { $0.id == entry.id } } } }
                        }
                        NavigationLink("음식 검색 / 수기 추가") { FoodEntryView(sheetID: sheetID, mealID: meal.id) }
                        NavigationLink("식사 제목 · 매일 알림 설정") { MealSettings(sheetID: sheetID, original: meal) }
                    }
                }
                Button("식사 추가", systemImage: "plus") { text = "간식"; addMeal = true }
                Button("시트 삭제", role: .destructive) { deleteSheet = true }
            }
        }.navigationTitle(sheet?.title ?? "식단")
            .toolbar { Button("제목 수정") { text = sheet?.title ?? ""; rename = true } }
            .alert("제목 수정", isPresented: $rename) {
                TextField("제목", text: $text)
                Button("저장") { if Validation.nonempty(text) { edit { $0.title = text } } }
                Button("취소", role: .cancel) {}
            }
            .alert("식사 추가", isPresented: $addMeal) {
                TextField("식사 이름", text: $text)
                Button("추가") { if Validation.nonempty(text) { edit { $0.meals.append(Meal(title: text)) } } }
                Button("취소", role: .cancel) {}
            }
            .confirmationDialog("식단 시트와 연결된 알림을 삭제할까요?", isPresented: $deleteSheet, titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    let ids = sheet?.meals.map(\.id) ?? []
                    if store.update({ $0.diets.removeAll { $0.id == sheetID } }) {
                        ids.forEach { NotificationService.cancel("meal-\($0)") }; dismiss()
                    }
                }
            }
    }
    private func edit(_ change: (inout DietSheet) -> Void) {
        store.update { if let i = $0.diets.firstIndex(where: { $0.id == sheetID }) { change(&$0.diets[i]) } }
    }
    private func editMeal(_ id: UUID, _ change: (inout Meal) -> Void) {
        edit { if let i = $0.meals.firstIndex(where: { $0.id == id }) { change(&$0.meals[i]) } }
    }
}

struct MealSettings: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    let sheetID: UUID
    @State private var meal: Meal
    @State private var time: Date
    @State private var busy = false
    @State private var deletion = false
    init(sheetID: UUID, original: Meal) {
        self.sheetID = sheetID
        _meal = State(initialValue: original)
        _time = State(initialValue: Calendar.current.date(bySettingHour: original.reminderHour, minute: original.reminderMinute, second: 0, of: Date()) ?? Date())
    }
    var body: some View {
        Form {
            TextField("식사 이름", text: $meal.title)
            Toggle("매일 식단 알림", isOn: $meal.reminderEnabled)
            DatePicker("시간", selection: $time, displayedComponents: .hourAndMinute)
            Text("알림은 이 식사의 날짜와 무관하게 매일 반복합니다. 시트를 삭제하면 해당 알림도 해제됩니다.").font(.caption)
            Button("저장") {
                busy = true
                let components = Calendar.current.dateComponents([.hour, .minute], from: time)
                meal.reminderHour = components.hour ?? 8; meal.reminderMinute = components.minute ?? 0
                Task {
                    defer { busy = false }
                    do {
                        try await NotificationService.meal(meal)
                        let saved = store.update {
                            if let i = $0.diets.firstIndex(where: { $0.id == sheetID }), let j = $0.diets[i].meals.firstIndex(where: { $0.id == meal.id }) { $0.diets[i].meals[j] = meal }
                        }
                        if saved { dismiss() } else { NotificationService.cancel("meal-\(meal.id)") }
                    } catch { store.error = error.localizedDescription }
                }
            }.disabled(busy || !Validation.nonempty(meal.title))
            Button("식사 삭제", role: .destructive) { deletion = true }
        }.navigationTitle("식사 설정")
            .confirmationDialog("이 식사와 음식 기록을 삭제할까요?", isPresented: $deletion, titleVisibility: .visible) {
                Button("삭제", role: .destructive) { store.removeMeal(sheetID: sheetID, mealID: meal.id); dismiss() }
            }
    }
}

struct FoodEntryView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    let sheetID: UUID
    let mealID: UUID
    @State private var query = ""
    @State private var food: Food?
    @State private var grams = "100"
    @State private var manual = false
    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = "0"
    @State private var carbs = "0"
    @State private var fat = "0"
    private var results: [Food] { (store.data.foods + Food.reference).filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } }
    private var manualFood: Food? {
        guard Validation.nonempty(name), let k = Validation.number(kcal), let p = Validation.number(protein), let c = Validation.number(carbs), let f = Validation.number(fat), k <= 1000, p + c + f <= 100 else { return nil }
        return Food(name: name, kcal100: k, protein100: p, carbs100: c, fat100: f)
    }
    private var chosen: Food? { manual ? manualFood : food }
    var body: some View {
        Form {
            Section {
                Text("기본 식품 참고값과 저장한 음식입니다. 제품의 실제 영양표시를 우선해 주세요.").font(.caption).foregroundStyle(.orange)
                Toggle("음식 직접 입력", isOn: $manual)
            }
            if manual {
                Section("제품 표시를 보고 100g 기준으로 입력") {
                    TextField("음식명 · 브랜드 · 조리 상태", text: $name)
                    number("열량 kcal", text: $kcal)
                    number("단백질 g", text: $protein)
                    number("탄수화물 g", text: $carbs)
                    number("지방 g", text: $fat)
                }
            } else {
                if !store.recentFoods.isEmpty {
                    Section("최근 먹은 음식") {
                        ForEach(store.recentFoods) { entry in
                            Button { food = entry.food; grams = String(format: "%g", entry.grams) } label: {
                                HStack { Text(entry.food.name); Spacer(); Text("\(entry.grams, specifier: "%g")g").foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                Section("검색") {
                    TextField("음식 이름", text: $query)
                    ForEach(results) { item in
                        Button { food = item } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.name)
                                    Text("1g당 \(item.kcal100 / 100, specifier: "%.2f") kcal").font(.caption)
                                }
                                Spacer()
                                if food?.id == item.id { Image(systemName: "checkmark.circle.fill") }
                            }
                        }
                    }
                    if results.isEmpty { Text("검색 결과가 없습니다. 직접 입력을 켜 주세요.") }
                }
            }
            Section("섭취량") {
                number("그람 g", text: $grams)
                if let chosen, let amount = Validation.number(grams), amount > 0 {
                    Text("\(chosen.kcal100 * amount / 100, specifier: "%.1f") kcal · 단백질 \(chosen.protein100 * amount / 100, specifier: "%.1f")g").font(.headline)
                }
                Button("식단에 추가") { save() }
                    .disabled(chosen == nil || (Validation.number(grams) ?? 0) <= 0 || (Validation.number(grams) ?? 0) > 10000)
            }
        }.navigationTitle("음식 추가")
    }
    private func number(_ label: String, text: Binding<String>) -> some View {
        HStack { Text(label); TextField(label, text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
    }
    private func save() {
        guard let chosen, let amount = Validation.number(grams), amount > 0, amount <= 10000 else { return }
        if store.update({
            guard let i = $0.diets.firstIndex(where: { $0.id == sheetID }), let j = $0.diets[i].meals.firstIndex(where: { $0.id == mealID }) else { return }
            $0.diets[i].meals[j].entries.append(MealEntry(food: chosen, grams: amount))
            if manual { $0.foods.append(chosen) }
        }) { dismiss() }
    }
}
