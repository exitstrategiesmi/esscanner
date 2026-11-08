//  RoomScanViewController.swift
//  ESScanner — Exit Strategies Field Estimator (native shell)
//
//  Full-screen RoomPlan capture. The framework draws its own scanning
//  UI (live mesh, coaching prompts, and its own Done button); this
//  controller adds the one control the framework does not provide —
//  a Cancel button — and reports exactly one outcome back to the
//  shell: completed payload, cancellation, or failure.

import UIKit
import RoomPlan

enum ScanOutcome {
    case completed(ScanPayload)
    case cancelled
    case failed(code: String, message: String)
}

final class RoomScanViewController: UIViewController, RoomCaptureViewDelegate {

    private let completion: (ScanOutcome) -> Void
    private var captureView: RoomCaptureView!
    private var didFinish = false

    init(completion: @escaping (ScanOutcome) -> Void) {
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let captureView = RoomCaptureView(frame: view.bounds)
        captureView.delegate = self
        captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(captureView)
        self.captureView = captureView

        // Cancel sits in the top-left safe area; RoomPlan's own
        // controls live at the bottom of its capture UI.
        var cancelConfig = UIButton.Configuration.filled()
        cancelConfig.title = "Cancel scan"
        cancelConfig.cornerStyle = .capsule
        cancelConfig.baseBackgroundColor = UIColor.black.withAlphaComponent(0.55)
        cancelConfig.baseForegroundColor = .white
        let cancelButton = UIButton(configuration: cancelConfig)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelButton)
        NSLayoutConstraint.activate([
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        var configuration = RoomCaptureSession.Configuration()
        configuration.isCoachingEnabled = true
        captureView.captureSession.run(configuration: configuration)
    }

    @objc private func cancelTapped() {
        finish(.cancelled)
    }

    // MARK: RoomCaptureViewDelegate

    /// The user tapped Done in the capture UI. Returning true lets
    /// RoomPlan process the raw capture into a CapturedRoom.
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData,
                     error: Error?) -> Bool {
        if let error {
            finish(.failed(code: "scan-failed", message: error.localizedDescription))
            return false
        }
        return true
    }

    /// Processing finished: this is the final scan result.
    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        if let error {
            finish(.failed(code: "scan-failed", message: error.localizedDescription))
        } else {
            finish(.completed(CapturedRoomConverter.payload(from: processedResult)))
        }
    }

    // MARK: Outcome

    /// Stops the session, dismisses, and reports the outcome exactly
    /// once (both the Cancel button and the delegate can race here).
    private func finish(_ outcome: ScanOutcome) {
        guard !didFinish else { return }
        didFinish = true
        captureView.captureSession.stop()
        dismiss(animated: true) { [completion] in
            completion(outcome)
        }
    }
}
