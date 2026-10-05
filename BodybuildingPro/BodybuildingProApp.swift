import SwiftUI
import UIKit

@main
struct BodybuildingProApp: App {
    @StateObject private var store = Store()
    init() { NotificationService.shared.install() }
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).tint(AppTheme.green).preferredColorScheme(.light)
                .alert("확인해 주세요", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("확인") { store.error = nil }
                } message: { Text(store.error ?? "") }
        }
    }
}

enum AppTheme {
    static let green = Color(red: 0.10, green: 0.48, blue: 0.30)
    static let background = Color(red: 0.96, green: 0.97, blue: 0.96)
}

enum AppRoute: String, Hashable, CaseIterable {
    case workout, diet, vault, progress, community, settings
    var title: String {
        switch self {
        case .workout: return "운동 시작"
        case .diet: return "식단 기록"
        case .vault: return "사진 보관함"
        case .progress: return "증량 일기"
        case .community: return "커뮤니티"
        case .settings: return "내 정보"
        }
    }
    var icon: String {
        switch self {
        case .workout: return "dumbbell.fill"
        case .diet: return "fork.knife"
        case .vault: return "photo.stack"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .community: return "bubble.left.and.bubble.right"
        case .settings: return "person.crop.circle"
        }
    }
    var color: Color {
        switch self {
        case .workout: return AppTheme.green
        case .diet: return .brown
        case .vault: return .blue
        case .progress: return .purple
        case .community: return .teal
        case .settings: return .gray
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if typeSize.isAccessibilitySize || geometry.size.height < 380 {
                    ScrollView { menu.padding(.vertical, 16) }
                } else {
                    menu.padding(.vertical, 16)
                }
            }
            .padding(.horizontal, 20)
            .background(AppTheme.background)
            .navigationTitle("보디빌딩Pro")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .workout: WorkoutView()
                case .diet: DietView()
                case .vault: VaultView()
                case .progress: ProgressViewScreen()
                case .community: CommunityView()
                case .settings: SettingsView()
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("입력 완료") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
        }
    }
    private var menu: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("오늘도, 한 세트 더.").font(.title2.bold())
                Spacer()
                Image(systemName: store.readOnly ? "exclamationmark.circle" : "iphone.gen3.radiowaves.left.and.right")
                    .foregroundStyle(AppTheme.green)
                    .accessibilityLabel(store.readOnly ? "저장 오류" : "기기에 기록 저장")
            }
            ForEach(0..<3) { row in
                HStack(spacing: 14) {
                    tile(AppRoute.allCases[row * 2])
                    tile(AppRoute.allCases[row * 2 + 1])
                }.frame(maxHeight: .infinity)
            }
            if store.data.timer != nil { HomeRestBar() }
            Label("기기에 자동 저장", systemImage: "checkmark.shield").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func tile(_ route: AppRoute) -> some View {
        NavigationLink(value: route) {
            VStack(spacing: 13) {
                Image(systemName: route.icon).font(.system(size: 30, weight: .medium))
                    .frame(width: 60, height: 60).background(route.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                Text(route.title).font(.headline).foregroundStyle(Color.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 112, maxHeight: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(route.color)
            .background(route == .workout ? AppTheme.green.opacity(0.07) : Color.white, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(route.color.opacity(0.12), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

struct HomeRestBar: View {
    @EnvironmentObject var store: Store
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let timer = store.data.timer {
                let seconds = timer.pausedSeconds ?? max(0, Int(ceil((timer.deadline ?? context.date).timeIntervalSince(context.date))))
                NavigationLink(value: AppRoute.workout) {
                    HStack {
                        Image(systemName: "timer")
                        Text(timer.name).lineLimit(1)
                        Spacer()
                        Text(seconds == 0 ? "휴식 끝" : String(format: "%02d:%02d", seconds / 60, seconds % 60)).monospacedDigit().bold()
                    }.padding(14).background(AppTheme.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }
}

struct EmptyHint: View {
    let title: String
    let description: String
    var body: some View { ContentUnavailableView(title, systemImage: "plus.circle", description: Text(description)) }
}

struct CommunityView: View {
    var body: some View {
        ContentUnavailableView("커뮤니티 연결 준비 중", systemImage: "person.3", description: Text("iOS 앱의 계정 로그인과 서버 연결이 아직 완료되지 않았습니다. 현재 앱에서는 게시글을 보내거나 볼 수 없습니다."))
            .navigationTitle("커뮤니티")
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        List {
            Section("내 기록") {
                Label("이 아이폰에 자동 저장", systemImage: "iphone")
                Text("앱을 종료해도 기록은 유지됩니다. 계정 동기화는 아직 연결되지 않았습니다.").font(.subheadline).foregroundStyle(.secondary)
                NavigationLink { BackupView() } label: { Label("백업과 복원", systemImage: "externaldrive") }
            }
            Section("알림") {
                Button("타이머·식단 알림 허용") { Task { do { try await NotificationService.permission() } catch { store.error = error.localizedDescription } } }
                Button("아이폰 알림 설정 열기") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                Text("무음·집중 모드에서는 소리가 제한될 수 있습니다.").font(.caption).foregroundStyle(.secondary)
            }
            Section("앱 정보") {
                LabeledContent("버전", value: "0.2 · 개발 빌드")
                Text("결제·구독·커뮤니티·계정 동기화는 연결 전입니다. 이 버전에서 요금은 청구되지 않습니다.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("내 정보")
    }
}
