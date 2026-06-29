import SwiftUI
import UIKit

private enum AppTheme {
    static let background = Color(red: 1.0, green: 0.96, blue: 0.91)
    static let card = Color.white
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.12)
    static let pink = Color(red: 1.0, green: 0.28, blue: 0.46)
    static let blue = Color(red: 0.12, green: 0.47, blue: 1.0)
    static let mint = Color(red: 0.1, green: 0.72, blue: 0.55)
    static let yellow = Color(red: 1.0, green: 0.77, blue: 0.2)
}

struct SignInStartView: View {
    @EnvironmentObject private var store: CountdownPosterStore

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "calendar")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(AppTheme.blue)
                .frame(width: 92, height: 92)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: AppTheme.pink.opacity(0.18), radius: 18, y: 10)

            Text("予定ポスター")
                .font(.largeTitle.weight(.black))
                .foregroundStyle(AppTheme.ink)

            Button {
                store.signInWithGoogle()
            } label: {
                if store.isSyncing {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Googleでサインイン", systemImage: "person.crop.circle.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(AppTheme.pink)
            .disabled(store.isSyncing)

            if let statusMessage = store.statusMessage {
                Text(statusMessage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(28)
        .background(AppTheme.background.ignoresSafeArea())
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: CountdownPosterStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("予定")
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(AppTheme.ink)

                    Spacer()

                    if store.isSyncing {
                        ProgressView()
                            .frame(width: 42, height: 42)
                            .tint(AppTheme.pink)
                    }
                }

                ForEach(store.visibleEvents) { event in
                    NavigationLink {
                        PosterDetailView(event: event)
                    } label: {
                        EventCardView(event: event)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EventCardView: View {
    @EnvironmentObject private var store: CountdownPosterStore
    let event: CalendarEvent

    var body: some View {
        let poster = store.currentPoster(for: event)
        let place = poster?.recommendedPlaces.first ?? store.places(for: event).first

        HStack(alignment: .center, spacing: 12) {
            Group {
                if let poster {
                    PosterThumbnailView(poster: poster)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(.tertiarySystemGroupedBackground))
                        .overlay {
                            Image(systemName: "photo")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 72, height: 128)
            .clipped()
            .shadow(color: AppTheme.pink.opacity(0.14), radius: 10, y: 6)

            VStack(alignment: .leading, spacing: 8) {
                CountdownBadge(days: event.daysUntil())

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.headline.weight(.black))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                    Text(event.startAt.formatted(.dateTime.month().day().hour().minute()))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.black))
                    Text(place.map { "\($0.placeName) / \($0.category)" } ?? store.analysis(for: event).displayArea)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.black))
                .foregroundStyle(AppTheme.pink.opacity(0.72))
        }
        .padding(12)
        .frame(minHeight: 148)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct PosterDetailView: View {
    @EnvironmentObject private var store: CountdownPosterStore
    @Environment(\.dismiss) private var dismiss
    let event: CalendarEvent

    @State private var selectedStage: CountdownStage
    @State private var shareImage: UIImage?
    @State private var isSharePresented = false
    @State private var statusMessage: String?
    @State private var posterPagerWidth: CGFloat = 360

    init(event: CalendarEvent) {
        self.event = event
        _selectedStage = State(initialValue: CountdownStage.milestone(for: event.daysUntil()))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                posterPager

                if let poster = store.poster(for: event, stage: selectedStage) {
                    actionBar(for: poster)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("ポスター")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isSharePresented) {
            if let shareImage {
                ShareSheet(items: [shareImage])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var posterPager: some View {
        let posterWidth = min(posterPagerWidth, 430)
        return TabView(selection: $selectedStage) {
            ForEach(CountdownStage.allCases) { stage in
                if let poster = store.poster(for: event, stage: stage) {
                    PosterCanvasView(poster: poster)
                        .frame(width: posterWidth, height: posterWidth * 16 / 9)
                        .shadow(color: .black.opacity(0.22), radius: 20, y: 12)
                        .tag(stage)
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: posterWidth * 16 / 9 + 34)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: PosterPagerWidthPreferenceKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(PosterPagerWidthPreferenceKey.self) { width in
            guard width > 0 else { return }
            posterPagerWidth = width
        }
    }

    private func actionBar(for poster: Poster) -> some View {
        HStack(spacing: 12) {
            Button {
                save(poster)
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.headline.weight(.black))
                    .frame(width: 48, height: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.pink)
            .accessibilityLabel("保存")

            Button {
                share(poster)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.headline.weight(.black))
                    .frame(width: 48, height: 44)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.blue)
            .accessibilityLabel("共有")

            Menu {
                Button {
                    store.regenerateBackground(for: event, stage: selectedStage)
                } label: {
                    Label("背景再生成", systemImage: "sparkles")
                }

                Button {
                    store.regenerateCopy(for: event, stage: selectedStage)
                } label: {
                    Label("コピー再生成", systemImage: "text.badge.star")
                }

                Button(role: .destructive) {
                    store.hide(event)
                    dismiss()
                } label: {
                    Label("非表示", systemImage: "eye.slash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline.weight(.bold))
                    .frame(width: 48, height: 44)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.mint)
        }
    }

    private func save(_ poster: Poster) {
        guard let image = PosterRenderer.image(for: poster) else {
            statusMessage = "画像を生成できませんでした"
            return
        }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        statusMessage = "写真に保存しました"
    }

    private func share(_ poster: Poster) {
        guard let image = PosterRenderer.image(for: poster) else {
            statusMessage = "画像を生成できませんでした"
            return
        }
        shareImage = image
        isSharePresented = true
    }
}

private struct PosterPagerWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 360

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct PosterMetadataView: View {
    let poster: Poster

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("生成内容", systemImage: "wand.and.stars")
                .font(.headline.weight(.bold))

            VStack(alignment: .leading, spacing: 8) {
                metadataRow("タイプ", poster.analysis.eventType.label)
                metadataRow("地域", poster.analysis.displayArea)
                metadataRow("信頼度", "\(Int(poster.analysis.confidence * 100))%")
                metadataRow("テンプレート", poster.templateType)
                metadataRow("背景", poster.backgroundImageURL == nil ? "テンプレート/場所写真" : "AI生成画像")
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func metadataRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }
}

struct RecommendationListView: View {
    @EnvironmentObject private var store: CountdownPosterStore
    let event: CalendarEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("おすすめ場所", systemImage: "mappin.and.ellipse")
                .font(.headline.weight(.bold))

            ForEach(store.places(for: event)) { place in
                RecommendationCard(event: event, place: place)
            }
        }
    }
}

private struct RecommendationCard: View {
    @EnvironmentObject private var store: CountdownPosterStore
    let event: CalendarEvent
    let place: RecommendedPlace

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let imageURL = place.imageURL {
                PosterRecommendationImage(url: imageURL)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: place.selectedForPoster ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(place.selectedForPoster ? .green : .secondary)
                    .onTapGesture {
                        store.togglePlace(place, for: event)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(place.placeName)
                        .font(.headline.weight(.bold))
                    Text("\(place.area) / \(place.category)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(place.aiReason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let imageAttribution = place.imageAttribution {
                        Text("Photo: \(imageAttribution)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }

            HStack {
                Link(destination: place.mapsURL) {
                    Label("Google Maps", systemImage: "map")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    store.togglePlace(place, for: event)
                } label: {
                    Label(place.selectedForPoster ? "外す" : "入れる", systemImage: place.selectedForPoster ? "minus.circle" : "plus.circle")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct PosterGalleryView: View {
    @EnvironmentObject private var store: CountdownPosterStore
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text("ポスター")
                    .font(.largeTitle.weight(.black))
                    .foregroundStyle(AppTheme.ink)

                ForEach(store.visibleEvents) { event in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(event.title)
                            .font(.headline.weight(.black))
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(2)

                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(CountdownStage.allCases) { stage in
                                if let poster = store.poster(for: event, stage: stage) {
                                    NavigationLink {
                                        PosterDetailView(event: event)
                                    } label: {
                                        PosterGalleryTile(poster: poster)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(18)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PosterGalleryTile: View {
    let poster: Poster

    var body: some View {
        PosterCanvasView(poster: poster)
            .frame(maxWidth: .infinity)
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: CountdownPosterStore

    var body: some View {
        Form {
            Section {
                Button {
                    store.signInWithGoogle()
                } label: {
                    Label(store.isGoogleConnected ? "Google連携済み" : "Googleで連携", systemImage: "calendar.badge.checkmark")
                }

                Stepper("読み取り \(store.settings.lookAheadDays)日先", value: $store.settings.lookAheadDays, in: 7...60, step: 1)
                    .onChange(of: store.settings.lookAheadDays) { _, _ in store.syncCalendar() }

                Stepper("生成対象 \(store.settings.targetEventCount)件", value: $store.settings.targetEventCount, in: 1...20, step: 1)
                    .onChange(of: store.settings.targetEventCount) { _, _ in store.syncCalendar() }
            } header: {
                Text("カレンダー")
            }

            Section {
                Toggle("東京デフォルトおすすめ", isOn: $store.settings.useTokyoDefaultRecommendations)
                    .onChange(of: store.settings.useTokyoDefaultRecommendations) { _, _ in store.syncCalendar() }
                Toggle("AI背景生成", isOn: $store.settings.useAIBackground)
                    .onChange(of: store.settings.useAIBackground) { _, _ in store.syncCalendar() }
            } header: {
                Text("生成")
            }

            if let statusMessage = store.statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("設定")
        .scrollContentBackground(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
    }
}

private struct CountdownBadge: View {
    let days: Int

    var body: some View {
        Label(days <= 0 ? "今日" : "あと\(days)日", systemImage: days <= 0 ? "party.popper.fill" : "timer")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(days <= 0 ? AppTheme.pink : AppTheme.blue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct TypePill: View {
    let analysis: EventAnalysis

    var body: some View {
        Label(analysis.eventType.label, systemImage: analysis.eventType.symbolName)
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PosterRecommendationImage: View {
    let url: URL

    var body: some View {
        Group {
            if url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Rectangle()
                            .fill(Color(.tertiarySystemGroupedBackground))
                            .overlay {
                                Image(systemName: "photo")
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
            }
        }
        .clipped()
    }
}
