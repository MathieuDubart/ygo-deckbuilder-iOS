import AVFoundation
import SwiftUI
import VisionKit

/// Scan des cartes par leur code imprimé (« SDBE-FR001 », sous l'illustration) : la caméra lit
/// le code, l'API retrouve la carte (recherche par code), et on peut l'ajouter d'un geste
/// avec la bonne impression et la bonne langue, puis enchaîner avec la suivante.
struct CardScannerView: View {
    /// Ouvre la fiche de la carte (code scanné, id de la carte).
    var onOpen: (String, Int) -> Void

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var hit: ScanHit?
    @State private var lookingUp: String?
    @State private var lastCode: String?
    @State private var notFound: String?
    @State private var addedCount = 0
    @State private var adding = false
    @State private var failure: String?
    @State private var cameraReady = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if DataScannerViewController.isSupported && cameraReady {
                    DataScannerRepresentable { codes in
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.actions.close"), systemImage: "xmark") { dismiss() }
                }
                if addedCount > 0 {
                    ToolbarItem(placement: .primaryAction) {
                        Text(t("ios.scan.addedCount", ["count": addedCount]))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.success)
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: addedCount)
        .sensoryFeedback(.selection, trigger: hit?.code)
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
            if let hit {
                HStack(spacing: Spacing.m) {
                    CardArt(card: hit.card, width: .thumb)
                        .frame(width: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.card.name).font(.headline).lineLimit(2)
                        Text(hit.code).font(.caption.monospaced()).foregroundStyle(.secondary)
                        if hit.card.owned > 0 {
                            Text(t("ios.scan.alreadyOwned", ["count": hit.card.owned]))
                                .font(.caption)
                                .foregroundStyle(Theme.success)
                        }
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: Spacing.m) {
                    Button(t("ios.scan.details"), systemImage: "info.circle") {
                        onOpen(hit.code, hit.card.id)
                    }
                    .buttonStyle(.glass)
                    Button {
                        Task { await quickAdd(hit) }
                    } label: {
                        Label(t("ios.scan.addOne"), systemImage: adding ? "hourglass" : "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(adding)
                }
                if let failure {
                    Text(failure).font(.footnote).foregroundStyle(Theme.danger)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.l)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.l, style: .continuous))
        .animation(.snappy, value: hit?.code)
    }

    /// Premier code nouveau parmi ceux lus → carte correspondante.
    private func lookup(_ codes: [String]) async {
        guard lookingUp == nil, let code = codes.first(where: { $0 != lastCode }) else { return }
        lastCode = code
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
            hit = ScanHit(
                code: code,
                card: detail?.summary ?? card,
                printId: scanned.flatMap { p in detail?.prints.first { p.matches($0.printCode) }?.id },
                language: scanned?.language)
        } catch {
            notFound = code
        }
    }

    private func quickAdd(_ hit: ScanHit) async {
        adding = true
        failure = nil
        defer { adding = false }
        do {
            try await app.api.addToCollection(AddCollectionItemBody(
                cardId: hit.card.id, printId: hit.printId, quantity: 1,
                language: hit.language ?? L10n.shared.current.cardLanguage))
            addedCount += 1
            app.collectionChanged()
            // Prêt pour la carte suivante (le même code peut être rescanné pour un 2e exemplaire)
            self.hit = nil
            lastCode = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}

struct ScanHit: Equatable {
    let code: String
    let card: CardSummary
    let printId: String?
    let language: CardLanguage?
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
        if !controller.isScanning { try? controller.startScanning() }
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
