import AVFoundation
import SwiftUI
import VisionKit

/// Scan des cartes par leur code imprimé (« SDBE-FR001 », sous l'illustration) : la caméra lit
/// les codes à la chaîne et chaque carte reconnue rejoint une file. On enchaîne les cartes sans
/// rien valider, puis on relit la file (`ScanReviewView`) pour corriger les éditions, les
/// quantités, en ajouter à la main, et tout envoyer en collection d'un coup.
struct CardScannerView: View {
    /// Durée d'absence du viseur au bout de laquelle un code redevient comptable.
    private static let cooldown: TimeInterval = 1.5

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var batch = ScanBatch()
    @State private var lookingUp: String?
    /// Dernière fois qu'un code a été vu, et ceux déjà comptés (anti-rafale, voir `lookup`).
    @State private var lastSeen: [String: Date] = [:]
    @State private var counted: Set<String> = []
    @State private var notFound: String?
    @State private var cameraReady = false
    @State private var cameraError = false
    /// La relecture est poussée sur la pile : pendant ce temps la caméra s'arrête.
    @State private var reviewing = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if DataScannerViewController.isSupported && cameraReady && !cameraError {
                    DataScannerRepresentable(scanning: !reviewing, onFailure: { cameraError = true }) { codes in
                        Task { await lookup(codes) }
                    }
                    .ignoresSafeArea()
                } else {
                    ContentUnavailableView(
                        t("ios.scan.unavailable"), systemImage: "camera.metering.unknown",
                        description: Text(t("ios.scan.unavailableHint")))
                }

                panel
                    .padding()
            }
            .navigationTitle(t("ios.scan.title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $reviewing) {
                ScanReviewView(batch: batch) { dismiss() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.actions.close"), systemImage: "xmark") { dismiss() }
                }
                if !batch.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Text(t("ios.scan.queued", ["count": batch.totalCopies]))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.success)
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: batch.totalCopies)
        .sensoryFeedback(.warning, trigger: notFound)
        .task {
            // isAvailable reste faux tant que l'accès à la caméra n'est pas accordé
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            cameraReady = DataScannerViewController.isAvailable
        }
    }

    @ViewBuilder
    private var panel: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if let last = batch.last {
                HStack(spacing: Spacing.m) {
                    CardArt(card: last.card, width: .thumb)
                        .frame(width: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(last.card.name).font(.headline).lineLimit(2)
                        Text(last.subtitle).font(.caption.monospaced()).foregroundStyle(.secondary)
                        if last.quantity > 1 {
                            Text(t("ios.scan.copies", ["count": last.quantity]))
                                .font(.caption)
                                .foregroundStyle(Theme.success)
                        } else if last.card.owned > 0 {
                            Text(t("ios.scan.alreadyOwned", ["count": last.card.owned]))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Button(t("ios.scan.undo"), systemImage: "arrow.uturn.backward") {
                        batch.undoLast()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                }
            } else if let lookingUp {
                HStack {
                    ProgressView()
                    Text(lookingUp).font(.subheadline.monospaced())
                }
            } else if let notFound {
                Label(t("ios.scan.notFound", ["code": notFound]), systemImage: "questionmark.circle")
                    .font(.subheadline)
            } else {
                Label(t("ios.scan.hint"), systemImage: "viewfinder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                reviewing = true
            } label: {
                Label(
                    batch.isEmpty
                        ? t("ios.scan.review.openEmpty")
                        : t("ios.scan.review.open", ["count": batch.totalCopies]),
                    systemImage: "checklist")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.l)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.l, style: .continuous))
        .animation(.snappy, value: batch.last?.id)
    }

    /// Premier code pas encore compté parmi ceux lus → carte correspondante, ajoutée à la file.
    /// Un code compté le reste tant qu'il est dans le viseur : une carte posée devant
    /// l'objectif ne s'ajoute pas en boucle. Il redevient comptable après avoir disparu
    /// pendant `cooldown`, donc repasser la même carte ajoute bien un deuxième exemplaire.
    /// Deux cartes côte à côte sont comptées l'une après l'autre, à la lecture suivante.
    private func lookup(_ codes: [String]) async {
        let now = Date()
        for (code, seenAt) in lastSeen where now.timeIntervalSince(seenAt) > Self.cooldown {
            lastSeen[code] = nil
            counted.remove(code)
        }
        let fresh = codes.first { !counted.contains($0) }
        for code in codes { lastSeen[code] = now }
        guard lookingUp == nil, let code = fresh else { return }
        counted.insert(code)
        lookingUp = code
        notFound = nil
        defer { lookingUp = nil }
        do {
            var query = CardSearchQuery()
            query.q = code
            query.pageSize = 5
            guard let card = try await app.api.searchCards(query).items.first else {
                notFound = code
                return
            }
            let detail = try? await app.api.card(card.id)
            let scanned = PrintCode(code)
            batch.add(
                card: detail?.summary ?? card,
                prints: detail?.prints ?? [],
                code: code,
                printId: scanned.flatMap { p in detail?.prints.first { p.matches($0.printCode) }?.id },
                language: scanned?.language)
        } catch {
            notFound = code
        }
    }
}

/// Extraction des codes imprimés dans le texte lu par la caméra (tolère O/0 et I/1).
nonisolated enum PrintCodeReader {
    static func codes(in text: String) -> [String] {
        let upper = text.uppercased().replacingOccurrences(of: " ", with: "")
        let pattern = #/([A-Z0-9]{2,5})-([A-Z]{0,2})([0-9OIL]{3,4})/#
        return upper.matches(of: pattern).compactMap { match in
            let digits = String(match.3)
                .replacingOccurrences(of: "O", with: "0")
                .replacingOccurrences(of: "I", with: "1")
                .replacingOccurrences(of: "L", with: "1")
            let code = "\(match.1)-\(match.2)\(digits)"
            return PrintCode(code) != nil ? code : nil
        }
    }
}

/// Caméra VisionKit (reconnaissance de texte en direct).
private struct DataScannerRepresentable: UIViewControllerRepresentable {
    /// Faux quand on est passé sur la relecture : la caméra se met en pause.
    var scanning: Bool
    var onFailure: () -> Void
    let onCodes: ([String]) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        guard scanning != controller.isScanning else { return }
        guard scanning else {
            controller.stopScanning()
            return
        }
        do {
            try controller.startScanning()
        } catch {
            // La vue n'est pas encore dans une fenêtre : on retente hors du cycle de mise à
            // jour, et on ne déclare la caméra inutilisable que si ça rate encore.
            Task { @MainActor in
                guard !controller.isScanning else { return }
                do { try controller.startScanning() } catch { onFailure() }
            }
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCodes: onCodes) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCodes: ([String]) -> Void

        init(onCodes: @escaping ([String]) -> Void) { self.onCodes = onCodes }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(allItems)
        }

        private func handle(_ items: [RecognizedItem]) {
            let codes = items.flatMap { item -> [String] in
                if case .text(let text) = item { return PrintCodeReader.codes(in: text.transcript) }
                return []
            }
            if !codes.isEmpty { onCodes(codes) }
        }
    }
}
