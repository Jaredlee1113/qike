import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    @Binding var isRunning: Bool
    
    func makeUIView(context: Context) -> CameraPreviewView {
        let previewView = CameraPreviewView()
        previewView.session = session
        return previewView
    }
    
    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        if isRunning && !uiView.isRunning {
            uiView.startRunning()
        } else if !isRunning && uiView.isRunning {
            uiView.stopRunning()
        }
    }
}

class CameraPreviewView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?
    var session: AVCaptureSession? {
        didSet {
            setupPreviewLayer()
        }
    }
    
    var isRunning: Bool {
        return previewLayer?.session?.isRunning ?? false
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupPreviewLayer()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPreviewLayer()
    }
    
    private func setupPreviewLayer() {
        guard let session = session else { return }
        
        if previewLayer == nil {
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = bounds
            self.layer.insertSublayer(layer, at: 0)
            self.previewLayer = layer
        } else {
            previewLayer?.session = session
        }
    }
    
    func startRunning() {
        session?.startRunning()
    }
    
    func stopRunning() {
        session?.stopRunning()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}