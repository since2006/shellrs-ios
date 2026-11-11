import AVFoundation
import SwiftUI
import VisionKit

/// The camera, reading QR codes: each one's text is handed to `found`,
/// which says whether it is the one looked for. The system's scanner
/// (VisionKit) does the reading, the guidance and the highlight.
struct CodeScanner: UIViewControllerRepresentable {
    /// Called with the text of each QR code that comes into view. `true`
    /// takes it and ends the scanning; `false` passes it over.
    let found: (String) -> Bool

    /// What stands between the app and the camera.
    enum Access {
        /// This device has no camera the scanner works with (an iPad of
        /// before 2018, the simulator).
        case unsupported
        /// The user said no, or may not say yes.
        case denied
        case granted
    }

    /// Whether the camera can be used, asking the user the first time.
    static func access() async -> Access {
        guard DataScannerViewController.isSupported else {
            return .unsupported
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .granted
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
        default:
            return .denied
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(found: found)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.found = found
        // Started here, once the scanner is in the view, and again after
        // the camera was taken away for a while; not once a code is taken.
        if !context.coordinator.taken, !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(
        _ scanner: DataScannerViewController, coordinator: Coordinator
    ) {
        scanner.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var found: (String) -> Bool
        /// A code was taken: the scanning is over.
        var taken = false

        init(found: @escaping (String) -> Bool) {
            self.found = found
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                guard !taken, case .barcode(let code) = item, let text = code.payloadStringValue
                else {
                    continue
                }
                if found(text) {
                    taken = true
                    dataScanner.stopScanning()
                }
            }
        }
    }
}
