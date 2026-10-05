import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let bodybuildingBackup = UTType(exportedAs: "com.bodybuildingpro.backup", conformingTo: .package)
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.bodybuildingBackup] }
    private let records: Data
    private let media: [String: Data]
    // Cross-task document values contain immutable Data, not mutable FileWrapper instances.
    var wrapper: FileWrapper {
        FileWrapper(directoryWithFileWrappers: [
            "records.json": FileWrapper(regularFileWithContents: records),
            "media": FileWrapper(directoryWithFileWrappers: media.mapValues { FileWrapper(regularFileWithContents: $0) })
        ])
    }
    init(wrapper: FileWrapper) throws {
        guard let records = wrapper.fileWrappers?["records.json"]?.regularFileContents,
              let entries = wrapper.fileWrappers?["media"]?.fileWrappers else { throw CocoaError(.fileReadCorruptFile) }
        var media: [String: Data] = [:]
        for (name, file) in entries {
            guard BackupFiles.validName(name), let contents = file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
            media[name] = contents
        }
        self.records = records
        self.media = media
    }
    init(configuration: ReadConfiguration) throws { try self.init(wrapper: configuration.file) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { wrapper }
}

enum BackupFiles {
    static let maximumBytes = 256 * 1024 * 1024
    static func validName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\")
    }
    static func make(state: AppData, mediaRoot: URL) throws -> BackupDocument {
        var state = state
        state.timer = nil
        let encoded = try JSONEncoder().encode(state)
        var total = encoded.count
        var files: [String: FileWrapper] = [:]
        let names = Set(state.albums.flatMap(\.items).flatMap { [$0.filename, $0.thumbnail].compactMap { $0 } })
        for name in names {
            guard validName(name) else { throw CocoaError(.fileReadCorruptFile) }
            let url = mediaRoot.appendingPathComponent(name)
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
            total += info.fileSize ?? maximumBytes + 1
            guard total <= maximumBytes else { throw NSError(domain: "Backup", code: 1, userInfo: [NSLocalizedDescriptionKey: "전체 백업은 256MB까지 지원합니다. 큰 영상은 개별 내보내기로 보관해 주세요."]) }
            files[name] = FileWrapper(regularFileWithContents: try Data(contentsOf: url))
        }
        return try BackupDocument(wrapper: FileWrapper(directoryWithFileWrappers: ["records.json": FileWrapper(regularFileWithContents: encoded), "media": FileWrapper(directoryWithFileWrappers: files)]))
    }
    static func read(_ url: URL) throws -> BackupDocument {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey]) else { throw CocoaError(.fileReadCorruptFile) }
        var total = 0
        for case let file as URL in enumerator {
            let info = try file.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey])
            guard info.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
            if info.isRegularFile == true { total += info.fileSize ?? maximumBytes + 1 }
            guard total <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        }
        return try BackupDocument(wrapper: try FileWrapper(url: url, options: .immediate))
    }
}

extension Store {
    func restore(_ document: BackupDocument) throws {
        guard !readOnly else { throw CocoaError(.fileWriteNoPermission) }
        guard let bytes = document.wrapper.fileWrappers?["records.json"]?.regularFileContents,
              let files = document.wrapper.fileWrappers?["media"]?.fileWrappers else { throw CocoaError(.fileReadCorruptFile) }
        var restored = try JSONDecoder().decode(AppData.self, from: bytes)
        guard restored.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
        let oldItems = data.albums.flatMap(\.items)
        var created: [URL] = []
        var committed = false
        defer { if !committed { created.forEach { try? FileManager.default.removeItem(at: $0) } } }
        var mappings: [String: String] = [:]
        let names = Set(restored.albums.flatMap(\.items).flatMap { [$0.filename, $0.thumbnail].compactMap { $0 } })
        for name in names {
            guard BackupFiles.validName(name), let contents = files[name]?.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
            let suffix = (name as NSString).pathExtension
            let newName = UUID().uuidString + (suffix.isEmpty ? "" : "." + suffix)
            let destination = mediaURL(newName)
            try contents.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            created.append(destination); mappings[name] = newName
        }
        for a in restored.albums.indices {
            for m in restored.albums[a].items.indices {
                let original = restored.albums[a].items[m]
                restored.albums[a].items[m].filename = mappings[original.filename]!
                restored.albums[a].items[m].thumbnail = original.thumbnail.flatMap { mappings[$0] }
            }
        }
        restored.timer = nil
        // A restored plan never silently schedules multiple daily reminders.
        for d in restored.diets.indices { for m in restored.diets[d].meals.indices { restored.diets[d].meals[m].reminderEnabled = false } }
        let oldReminders = data.diets.flatMap(\.meals).map(\.id)
        guard update({ $0 = restored }) else { throw CocoaError(.fileWriteUnknown) }
        committed = true
        NotificationService.cancel("rest")
        oldReminders.forEach { NotificationService.cancel("meal-\($0)") }
        for item in oldItems { for name in [item.filename, item.thumbnail].compactMap({ $0 }) where BackupFiles.validName(name) { try? FileManager.default.removeItem(at: mediaURL(name)) } }
    }
}

struct BackupView: View {
    @EnvironmentObject var store: Store
    @State private var document: BackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var busy = false
    @State private var candidate: BackupDocument?
    @State private var confirming = false
    @State private var resultMessage: String?
    var body: some View {
        List {
            Section {
                Text("기록과 사진·영상을 파일 앱에 보관합니다. 앱을 삭제하기 전에 백업해 주세요.")
                Button("전체 백업 저장", systemImage: "square.and.arrow.up") {
                    busy = true
                    let state = store.data, mediaRoot = store.mediaRoot
                    Task {
                        defer { busy = false }
                        do {
                            document = try await Task.detached(priority: .userInitiated) { try BackupFiles.make(state: state, mediaRoot: mediaRoot) }.value
                            exporting = true
                        } catch { store.error = error.localizedDescription }
                    }
                }
                Button("백업 파일로 복원", systemImage: "square.and.arrow.down") { importing = true }
                if busy { ProgressView("파일 처리 중") }
                if let resultMessage { Text(resultMessage).foregroundStyle(AppTheme.green) }
            }
            Section { Text("복원하면 현재 기록이 백업 내용으로 교체됩니다. 미리 현재 기록을 백업하세요. 복원 후 식단 알림은 다시 켜야 합니다. 백업 파일에는 개인 사진이 포함되므로 공유 대상을 확인하세요.").font(.caption).foregroundStyle(.secondary) }
        }
        .disabled(busy)
        .navigationTitle("백업과 복원")
        .fileExporter(isPresented: $exporting, document: document, contentType: .bodybuildingBackup, defaultFilename: "BodybuildingPro-" + Date().formatted(.iso8601.year().month().day())) { result in
            switch result { case .success: resultMessage = "백업 파일을 저장했습니다."; case .failure(let error): store.error = error.localizedDescription }
            document = nil
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.bodybuildingBackup]) { result in
            switch result {
            case .success(let url):
                busy = true
                Task {
                    defer { busy = false }
                    do { candidate = try await Task.detached(priority: .userInitiated) { try BackupFiles.read(url) }.value; confirming = true }
                    catch { store.error = error.localizedDescription }
                }
            case .failure(let error): store.error = error.localizedDescription
            }
        }
        .confirmationDialog("현재 기록을 백업 내용으로 교체할까요?", isPresented: $confirming, titleVisibility: .visible) {
            Button("교체하고 복원", role: .destructive) {
                guard let candidate else { return }
                do { try store.restore(candidate); resultMessage = "복원했습니다. 식단 알림은 다시 켜 주세요." }
                catch { store.error = error.localizedDescription }
                self.candidate = nil
            }
            Button("취소", role: .cancel) { candidate = nil }
        }
    }
}
