import SwiftUI
import AVKit
import UIKit
import UniformTypeIdentifiers

struct VaultView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false
    @State private var title = ""
    var body: some View {
        List {
            Section {
                NavigationLink { ProgressViewScreen() } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("나의 3대 중량").font(.headline)
                        let values = [Lift.squat, .bench, .deadlift].compactMap { store.oneRepMax($0) }
                        Text(values.count == 3 ? String(format: "%.1f kg", values.reduce(0, +)) : "1회 수행 기록을 추가하세요").font(.title2.bold()).foregroundStyle(AppTheme.green)
                        Text("서로 다른 날짜의 개인 최고 1회 기록 합계 · 증량 일기 보기").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("나만의 보관함") {
                if store.data.albums.isEmpty { EmptyHint(title: "변화를 모아 보세요", description: "PCA 대회 준비, 벌크업 1개월차처럼 이름을 붙이세요.") }
                ForEach(store.data.albums) { album in
                    NavigationLink { AlbumDetail(albumID: album.id) } label: {
                        HStack(spacing: 16) {
                            MediaThumb(item: album.cover).frame(width: 78, height: 88).clipShape(RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 8) {
                                Text(album.title).font(.headline)
                                Text("\(album.countdown()) · \(album.items.count)개").foregroundStyle(AppTheme.green)
                                Text("개인 보관 · 공개되지 않음").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 6)
                    }
                }
            }
        }.navigationTitle("성장 기록")
            .toolbar { Button("보관함 추가", systemImage: "plus") { title = "PCA 대회 준비"; adding = true } }
            .alert("새 보관함", isPresented: $adding) {
                TextField("제목", text: $title)
                Button("만들기") { if Validation.nonempty(title) { store.update { $0.albums.insert(Album(title: title), at: 0) } } }
                Button("취소", role: .cancel) {}
            }
    }
}

struct MediaThumb: View {
    @EnvironmentObject var store: Store
    let item: MediaRecord?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07))
            if let item, let name = item.thumbnail ?? (item.isVideo ? nil : item.filename), let image = UIImage(contentsOfFile: store.mediaURL(name).path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else { Image(systemName: "photo.on.rectangle.angled").foregroundStyle(.secondary) }
            if item?.isVideo == true { Image(systemName: "play.circle.fill").font(.title).foregroundStyle(.white) }
        }.clipped()
    }
}

struct AlbumDetail: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    let albumID: UUID
    @State private var picker = false
    @State private var camera = false
    @State private var rename = false
    @State private var title = ""
    @State private var deleting = false
    private var album: Album? { store.data.albums.first { $0.id == albumID } }
    var body: some View {
        List {
            if let album {
                Section {
                    Text(album.countdown()).font(.largeTitle.bold()).foregroundStyle(AppTheme.green)
                    DatePicker("목표 날짜", selection: Binding(get: { album.targetDate }, set: { date in edit { $0.targetDate = date } }), displayedComponents: .date)
                    Button("사진·동영상 가져오기", systemImage: "photo.badge.plus") { camera = false; picker = true }
                    Button("앱에서 촬영", systemImage: "camera") {
                        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { store.error = "이 기기에서는 카메라를 사용할 수 없습니다."; return }
                        camera = true; picker = true
                    }
                }
                ForEach(album.items.sorted { $0.date > $1.date }) { item in
                    NavigationLink { MediaDetail(albumID: albumID, itemID: item.id) } label: {
                        HStack {
                            MediaThumb(item: item).frame(width: 80, height: 90).clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.note.isEmpty ? "메모를 남겨 보세요" : item.note)
                                Text(item.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                if album.cover?.id == item.id { Text("대표 사진").font(.caption).foregroundStyle(AppTheme.green) }
                            }
                        }
                    }
                }
                Button("보관함 삭제", role: .destructive) { deleting = true }
            }
        }.navigationTitle(album?.title ?? "보관함")
            .toolbar { Button("제목 수정") { title = album?.title ?? ""; rename = true } }
            .alert("보관함 이름", isPresented: $rename) {
                TextField("제목", text: $title)
                Button("저장") { if Validation.nonempty(title) { edit { $0.title = title } } }
                Button("취소", role: .cancel) {}
            }
            .sheet(isPresented: $picker) {
                MediaPicker(camera: camera) { result in
                    picker = false
                    do {
                        let media = try importMedia(result, store: store)
                        let saved = store.update { data in if let i = data.albums.firstIndex(where: { $0.id == albumID }) { data.albums[i].items.insert(media, at: 0) } }
                        if !saved { removeMediaFiles([media], store: store) }
                    } catch { store.error = "가져오기 실패: \(error.localizedDescription)" }
                } cancel: { picker = false }
            }
            .confirmationDialog("보관함과 앱 내부의 사진·영상을 삭제할까요? 원래 사진 앱의 자료는 유지됩니다.", isPresented: $deleting, titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    let items = album?.items ?? []
                    if store.update({ $0.albums.removeAll { $0.id == albumID } }) { removeMediaFiles(items, store: store); dismiss() }
                }
            }
    }
    private func edit(_ change: (inout Album) -> Void) { store.update { if let i = $0.albums.firstIndex(where: { $0.id == albumID }) { change(&$0.albums[i]) } } }
}

struct MediaDetail: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    let albumID: UUID
    let itemID: UUID
    @State private var note = ""
    @State private var deleting = false
    @State private var player: AVPlayer?
    private var item: MediaRecord? { store.data.albums.first { $0.id == albumID }?.items.first { $0.id == itemID } }
    var body: some View {
        Form {
            if let item {
                if item.isVideo { VideoPlayer(player: player).frame(height: 320) }
                else if let image = UIImage(contentsOfFile: store.mediaURL(item.filename).path) { Image(uiImage: image).resizable().scaledToFit() }
                TextField("예: D-1 · 아침 공복 · 등 포징", text: $note, axis: .vertical)
                Button("메모 저장") { store.update { data in
                    if let i = data.albums.firstIndex(where: { $0.id == albumID }), let j = data.albums[i].items.firstIndex(where: { $0.id == itemID }) { data.albums[i].items[j].note = note }
                } }
                Button("대표 사진으로 지정") { store.update { if let i = $0.albums.firstIndex(where: { $0.id == albumID }) { $0.albums[i].coverID = itemID } } }
                ShareLink(item: store.mediaURL(item.filename)) { Label("원본 내보내기", systemImage: "square.and.arrow.up") }
                Button("기록 삭제", role: .destructive) { deleting = true }
            }
        }.navigationTitle("개인 기록")
            .onAppear { note = item?.note ?? ""; if let item, item.isVideo { player = AVPlayer(url: store.mediaURL(item.filename)) } }
            .onDisappear { player?.pause() }
            .confirmationDialog("이 기록을 삭제할까요?", isPresented: $deleting, titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    guard let item else { return }
                    if store.update({ data in if let i = data.albums.firstIndex(where: { $0.id == albumID }) {
                        data.albums[i].items.removeAll { $0.id == itemID }
                        if data.albums[i].coverID == itemID { data.albums[i].coverID = nil }
                    } }) { player?.pause(); removeMediaFiles([item], store: store); dismiss() }
                }
            }
    }
}

enum PickedMedia { case image(UIImage), video(URL) }

struct MediaPicker: UIViewControllerRepresentable {
    let camera: Bool
    let receive: (PickedMedia) -> Void
    let cancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = camera ? .camera : .photoLibrary
        controller.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        controller.videoMaximumDuration = 60
        controller.videoQuality = .typeMedium
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: MediaPicker
        init(_ parent: MediaPicker) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.cancel() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL { parent.receive(.video(url)) }
            else if let image = info[.originalImage] as? UIImage { parent.receive(.image(image)) }
            else { parent.cancel() }
        }
    }
}

@MainActor
func importMedia(_ media: PickedMedia, store: Store) throws -> MediaRecord {
    let id = UUID().uuidString
    switch media {
    case .image(let image):
        guard let bytes = image.jpegData(compressionQuality: 0.9) else { throw CocoaError(.fileWriteUnknown) }
        let name = id + ".jpg"
        try bytes.write(to: store.mediaURL(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return MediaRecord(filename: name, thumbnail: nil, isVideo: false)
    case .video(let url):
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size <= 200 * 1024 * 1024 else { throw NSError(domain: "Media", code: 2, userInfo: [NSLocalizedDescriptionKey: "개발 버전은 영상 한 개당 200MB까지 가져올 수 있습니다."]) }
        let name = id + "." + (url.pathExtension.isEmpty ? "mov" : url.pathExtension)
        let destination = store.mediaURL(name)
        try FileManager.default.copyItem(at: url, to: destination)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: destination))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        var thumbnail: String?
        if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil), let jpeg = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8) {
            let thumb = id + "-thumb.jpg"
            if (try? jpeg.write(to: store.mediaURL(thumb), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil { thumbnail = thumb }
        }
        return MediaRecord(filename: name, thumbnail: thumbnail, isVideo: true)
    }
}

@MainActor
func removeMediaFiles(_ items: [MediaRecord], store: Store) {
    for item in items {
        for name in [item.filename, item.thumbnail].compactMap({ $0 }) {
            do { try FileManager.default.removeItem(at: store.mediaURL(name)) }
            catch { store.error = "기록은 삭제했지만 일부 미디어 파일 정리가 실패했습니다: \(error.localizedDescription)" }
        }
    }
}

struct ProgressViewScreen: View {
    @EnvironmentObject var store: Store
    @State private var add = false
    @State private var filter = "전체"
    var body: some View {
        List {
            Section("직접 수행한 최고 1회 중량") {
                ForEach([Lift.squat, .bench, .deadlift]) { lift in
                    LabeledContent(lift.rawValue, value: store.oneRepMax(lift).map { String(format: "%.1f kg", $0) } ?? "기록 없음")
                }
                Text("자기 기록이며 대회 공인 기록이 아닙니다. 여러 회 반복 기록을 1RM으로 환산하지 않습니다.").font(.caption)
            }
            Section("증량 일기") {
                TextField("종목 검색 · 전체", text: $filter)
                ForEach(store.data.progress.filter { filter.isEmpty || filter == "전체" || $0.name.localizedCaseInsensitiveContains(filter) }.sorted { $0.date > $1.date }) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(entry.name) · \(entry.kg, specifier: "%.1f")kg × \(entry.reps)회").font(.headline)
                        Text(entry.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                        Text(entry.note)
                    }.swipeActions { Button("삭제", role: .destructive) { store.update { $0.progress.removeAll { $0.id == entry.id } } } }
                }
            }
        }.navigationTitle("증량 일기").toolbar { Button("기록 추가", systemImage: "plus") { add = true } }
            .sheet(isPresented: $add) { NavigationStack { ProgressEditor() } }
    }
}

struct ProgressEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var lift = Lift.bench
    @State private var name = Lift.bench.rawValue
    @State private var kg = ""
    @State private var reps = "1"
    @State private var note = ""
    @State private var date = Date()
    var body: some View {
        Form {
            Picker("종목", selection: $lift) { ForEach(Lift.allCases) { Text($0.rawValue).tag($0) } }
                .onChange(of: lift) { _, value in name = value == .custom ? "" : value.rawValue }
            TextField("종목 이름", text: $name)
            TextField("중량 kg", text: $kg).keyboardType(.decimalPad)
            TextField("횟수", text: $reps).keyboardType(.numberPad)
            DatePicker("기록 날짜", selection: $date, displayedComponents: .date)
            TextField("예: 14일차 · 지난주보다 2.5kg 증량", text: $note, axis: .vertical)
            Button("저장") {
                guard Validation.nonempty(name), let weight = Validation.number(kg), weight > 0, weight <= 1500, let count = Int(reps), count > 0, count <= 1000 else { store.error = "운동명, 중량 0 초과~1500kg, 횟수 1~1000회를 입력해 주세요."; return }
                if store.update({ $0.progress.append(ProgressEntry(lift: lift, name: name, date: date, kg: weight, reps: count, note: note)) }) { dismiss() }
            }
        }.navigationTitle("증량 기록").toolbar { Button("닫기") { dismiss() } }
    }
}
