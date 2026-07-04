import SwiftUI
import ReplayKit

/// 画面録画（ReplayKit）。録画→停止でプレビュー（写真/ファイルへ保存）を表示。
@MainActor
final class ScreenRecorder: NSObject, ObservableObject, RPPreviewViewControllerDelegate {
    @Published var recording = false
    @Published var message = ""

    func start() {
        let rec = RPScreenRecorder.shared()
        guard rec.isAvailable else { message = "この端末では画面録画を利用できません"; return }
        rec.isMicrophoneEnabled = false
        rec.startRecording { [weak self] error in
            Task { @MainActor in
                if let error { self?.message = "録画開始エラー: \(error.localizedDescription)" }
                else { self?.recording = true; self?.message = "画面録画中…" }
            }
        }
    }

    func stop() {
        let rec = RPScreenRecorder.shared()
        rec.stopRecording { [weak self] preview, error in
            Task { @MainActor in
                self?.recording = false
                if let error { self?.message = "停止エラー: \(error.localizedDescription)"; return }
                guard let preview else { self?.message = "録画データがありません"; return }
                preview.previewControllerDelegate = self
                self?.present(preview)
            }
        }
    }

    private func present(_ vc: RPPreviewViewController) {
        vc.modalPresentationStyle = .fullScreen
        var top = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController
        while let p = top?.presentedViewController { top = p }
        top?.present(vc, animated: true)
    }

    nonisolated func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
        Task { @MainActor in previewController.dismiss(animated: true) }
    }
}
