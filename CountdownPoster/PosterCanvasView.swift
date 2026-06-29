import SwiftUI
import UIKit

struct PosterPalette {
    let background: Color
    let secondary: Color
    let accent: Color
    let highlight: Color
    let ink: Color
    let softInk: Color
}

extension EventType {
    var palette: PosterPalette {
        switch self {
        case .travel:
            PosterPalette(
                background: Color(red: 0.03, green: 0.18, blue: 0.3),
                secondary: Color(red: 0.12, green: 0.62, blue: 0.7),
                accent: Color(red: 0.94, green: 0.34, blue: 0.27),
                highlight: Color(red: 0.98, green: 0.82, blue: 0.25),
                ink: .white,
                softInk: Color.white.opacity(0.76)
            )
        case .meal:
            PosterPalette(
                background: Color(red: 0.22, green: 0.05, blue: 0.11),
                secondary: Color(red: 0.05, green: 0.43, blue: 0.43),
                accent: Color(red: 0.96, green: 0.45, blue: 0.22),
                highlight: Color(red: 1.0, green: 0.76, blue: 0.38),
                ink: .white,
                softInk: Color.white.opacity(0.76)
            )
        case .workOrSchool:
            PosterPalette(
                background: Color(red: 0.08, green: 0.1, blue: 0.13),
                secondary: Color(red: 0.11, green: 0.36, blue: 0.46),
                accent: Color(red: 0.35, green: 0.75, blue: 0.55),
                highlight: Color(red: 0.72, green: 0.86, blue: 0.97),
                ink: .white,
                softInk: Color.white.opacity(0.72)
            )
        case .liveEvent:
            PosterPalette(
                background: Color(red: 0.09, green: 0.05, blue: 0.17),
                secondary: Color(red: 0.42, green: 0.1, blue: 0.66),
                accent: Color(red: 0.95, green: 0.17, blue: 0.45),
                highlight: Color(red: 0.8, green: 0.98, blue: 0.31),
                ink: .white,
                softInk: Color.white.opacity(0.74)
            )
        case .unknown:
            PosterPalette(
                background: Color(red: 0.05, green: 0.18, blue: 0.17),
                secondary: Color(red: 0.18, green: 0.32, blue: 0.5),
                accent: Color(red: 0.92, green: 0.3, blue: 0.5),
                highlight: Color(red: 0.98, green: 0.82, blue: 0.32),
                ink: .white,
                softInk: Color.white.opacity(0.74)
            )
        }
    }
}

extension CountdownStage {
    var visualEnergy: Double {
        switch self {
        case .sevenDays:
            0.34
        case .fiveDays:
            0.48
        case .threeDays:
            0.64
        case .twoDays:
            0.72
        case .oneDay:
            0.84
        case .today:
            1
        }
    }
}

struct PosterCanvasView: View {
    let poster: Poster

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let palette = poster.analysis.eventType.palette
            let place = poster.recommendedPlaces.first
            let design = resolvedTextDesign(for: place)

            ZStack {
                PosterBackgroundView(
                    palette: palette,
                    stage: poster.countdownStage,
                    seed: poster.styleSeed
                )
                .frame(width: width, height: height)

                if let imageURL = featureImageURL {
                    PosterImageLayer(url: imageURL)
                        .frame(width: width, height: height)
                        .opacity(1)
                        .overlay {
                            LinearGradient(
                                colors: [
                                    .black.opacity(0.03),
                                    .black.opacity(0.12),
                                    .black.opacity(0.44)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .clipped()
                }

                LinearGradient(
                    colors: [.black.opacity(0.18), .clear, .black.opacity(0.34)],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                PosterTypographyLayer(
                    design: design,
                    category: place?.category,
                    photoCreditText: photoCreditText,
                    width: width,
                    height: height
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(poster.countdownStage.title)、\(displayPlaceName(for: poster.recommendedPlaces.first))")
    }

    private var featureImageURL: URL? {
        poster.backgroundImageURL ?? poster.recommendedPlaces.first(where: { $0.imageURL != nil })?.imageURL
    }

    private var photoCreditText: String? {
        poster.recommendedPlaces
            .first(where: { $0.imageAttribution?.isBlank == false })?
            .imageAttribution
            .map { "Photo: \($0)" }
    }

    private func displayPlaceName(for place: RecommendedPlace?) -> String {
        guard let place else {
            return "おすすめスポット"
        }

        if let locationText = poster.event.locationText?.nonBlank,
           place.placeName.contains(locationText) {
            return place.category
        }

        if let detectedArea = poster.analysis.detectedArea?.nonBlank,
           detectedArea != "東京",
           detectedArea.count > 2,
           place.placeName.contains(detectedArea) {
            return place.category
        }

        return place.placeName
    }

    private func resolvedTextDesign(for place: RecommendedPlace?) -> PosterTextDesign {
        var design = poster.textDesign ?? PosterTextDesign(
            countdownText: poster.countdownStage.compactTitle,
            placeText: displayPlaceName(for: place),
            mainCopy: poster.mainCopy,
            subCopy: poster.subCopy,
            layoutVariant: .bottomLeft,
            fontMood: .boldPop
        )

        design.placeText = safePosterText(design.placeText, fallback: displayPlaceName(for: place))
        design.mainCopy = safePosterText(design.mainCopy, fallback: poster.mainCopy)
        design.subCopy = safePosterText(design.subCopy, fallback: poster.subCopy)
        if design.countdownText.isBlank {
            design.countdownText = poster.countdownStage.compactTitle
        }
        return design
    }

    private func safePosterText(_ text: String, fallback: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden = [poster.event.title, poster.event.locationText, poster.analysis.detectedArea]
            .compactMap { $0?.nonBlank }
            .filter { $0 != "東京" }

        for term in forbidden {
            cleaned = cleaned.replacingOccurrences(of: term, with: "")
        }

        cleaned = cleaned.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        return cleaned.isBlank ? fallback : cleaned
    }
}

private struct PosterTypographyLayer: View {
    let design: PosterTextDesign
    let category: String?
    let photoCreditText: String?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        switch design.layoutVariant {
        case .bottomLeft:
            VStack(alignment: .leading) {
                Spacer(minLength: 0)
                textStack(alignment: .leading)
            }
            .padding(edgePadding)
        case .topLeft:
            VStack(alignment: .leading) {
                textStack(alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(edgePadding)
        case .topRight:
            HStack {
                Spacer(minLength: width * 0.16)
                VStack(alignment: .trailing) {
                    textStack(alignment: .trailing)
                    Spacer(minLength: 0)
                }
            }
            .padding(edgePadding)
        case .centerStack:
            VStack {
                Spacer(minLength: 0)
                textStack(alignment: .center)
                Spacer(minLength: 0)
            }
            .padding(edgePadding)
        case .splitBands:
            VStack(alignment: .leading) {
                Text(design.countdownText)
                    .font(.system(size: countdownSize * 0.94, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 8)

                Spacer(minLength: 0)

                HStack {
                    Spacer(minLength: width * 0.16)
                    textStack(
                        alignment: .trailing,
                        includeCountdown: false
                    )
                }
            }
            .padding(edgePadding)
        case .bottomCenter:
            VStack {
                Spacer(minLength: 0)
                textStack(alignment: .center)
            }
            .padding(edgePadding)
        }
    }

    private var edgePadding: CGFloat {
        width * 0.072
    }

    private var countdownSize: CGFloat {
        switch design.fontMood {
        case .boldPop:
            return max(26, width * 0.105)
        case .softEditorial:
            return max(23, width * 0.095)
        case .compactLabel:
            return max(20, width * 0.085)
        }
    }

    private var placeSize: CGFloat {
        switch design.fontMood {
        case .boldPop:
            return max(18, width * 0.064)
        case .softEditorial:
            return max(17, width * 0.058)
        case .compactLabel:
            return max(16, width * 0.052)
        }
    }

    private var copySize: CGFloat {
        max(10, width * 0.026)
    }

    private func textStack(
        alignment: PosterTextBlockAlignment,
        includeCountdown: Bool = true
    ) -> some View {
        VStack(alignment: alignment.horizontal, spacing: max(5, height * 0.01)) {
            if includeCountdown {
                Text(design.countdownText)
                    .font(.system(size: countdownSize, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
            }

            Text(design.placeText)
                .font(.system(size: placeSize, weight: .black, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(alignment.text)

            if let category, !category.isBlank {
                Text(category)
                    .font(.system(size: max(8, width * 0.021), weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.12), in: Capsule())
            }

            Text(design.mainCopy)
                .font(.system(size: copySize, weight: .heavy, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.62)
                .multilineTextAlignment(alignment.text)

            Text(design.subCopy)
                .font(.system(size: max(8, width * 0.023), weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
                .minimumScaleFactor(0.64)
                .multilineTextAlignment(alignment.text)

            if let photoCreditText {
                Text(photoCreditText)
                    .font(.system(size: max(8, width * 0.026), weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: width * 0.58, alignment: alignment.frame)
        .shadow(color: .black.opacity(0.58), radius: 10, y: 6)
    }
}

private enum PosterTextBlockAlignment {
    case leading
    case center
    case trailing

    var horizontal: HorizontalAlignment {
        switch self {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    var text: TextAlignment {
        switch self {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    var frame: Alignment {
        switch self {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }
}

struct PosterThumbnailView: View {
    let poster: Poster

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let palette = poster.analysis.eventType.palette
            let place = poster.recommendedPlaces.first

            ZStack {
                PosterBackgroundView(
                    palette: palette,
                    stage: poster.countdownStage,
                    seed: poster.styleSeed
                )
                .frame(width: width, height: height)

                if let imageURL = poster.backgroundImageURL ?? poster.recommendedPlaces.first(where: { $0.imageURL != nil })?.imageURL {
                    PosterImageLayer(url: imageURL)
                        .frame(width: width, height: height)
                        .opacity(1)
                        .overlay(.black.opacity(0.22))
                        .clipped()
                }

                VStack(alignment: .leading, spacing: 7) {
                    Spacer()

                    Text(poster.countdownStage.compactTitle)
                        .font(.system(size: max(15, width * 0.18), weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)

                    Text(displayPlaceName(for: place))
                        .font(.system(size: max(9, width * 0.082), weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                }
                .padding(max(8, width * 0.1))
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            }
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .clipped()
        .accessibilityLabel("\(poster.countdownStage.title)、\(displayPlaceName(for: poster.recommendedPlaces.first))")
    }

    private func displayPlaceName(for place: RecommendedPlace?) -> String {
        guard let place else {
            return "おすすめスポット"
        }

        if let locationText = poster.event.locationText?.nonBlank,
           place.placeName.contains(locationText) {
            return place.category
        }

        if let detectedArea = poster.analysis.detectedArea?.nonBlank,
           detectedArea != "東京",
           detectedArea.count > 2,
           place.placeName.contains(detectedArea) {
            return place.category
        }

        return place.placeName
    }
}

private struct PosterSpotlightView: View {
    let place: RecommendedPlace
    let palette: PosterPalette

    var body: some View {
        HStack(spacing: 10) {
            if let imageURL = place.imageURL {
                PosterImageLayer(url: imageURL)
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    }
            } else {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(palette.highlight)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("おすすめスポット")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(palette.highlight)
                    .textCase(.uppercase)
                    .lineLimit(1)
                Text(place.placeName)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(place.category)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.softInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct PosterImageLayer: View {
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
                        Color.clear
                    }
                }
            }
        }
        .clipped()
    }
}

private struct PosterBackgroundView: View {
    let palette: PosterPalette
    let stage: CountdownStage
    let seed: Int

    var body: some View {
        LinearGradient(
            colors: [
                palette.background,
                palette.secondary.opacity(0.82),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            LinearGradient(
                colors: [.clear, .black.opacity(0.74)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
