//
//  BarcodeScannerView.swift
//  VinylVault
//
//  Barcode scanner using AVFoundation
//

import SwiftUI
import AVFoundation

struct BarcodeScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = BarcodeScannerViewModel()
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Camera Preview
                CameraPreview(session: viewModel.session)
                    .edgesIgnoringSafeArea(.all)
                
                // Scanning Overlay
                VStack {
                    Spacer()
                    
                    // Scanning frame
                    Rectangle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 250, height: 150)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(viewModel.isScanning ? Color.green : Color.white, lineWidth: 2)
                        )
                    
                    Text(viewModel.isScanning ? "Scanning..." : "Align barcode within frame")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                        .padding()
                    
                    Spacer()
                }
                
                // Loading overlay
                if viewModel.isLoading {
                    Color.black.opacity(0.5)
                        .edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        
                        Text("Searching Discogs...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .onAppear {
                viewModel.startScanning()
            }
            .onDisappear {
                viewModel.stopScanning()
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {
                    viewModel.showError = false
                }
            } message: {
                Text(viewModel.errorMessage)
            }
            .sheet(isPresented: $viewModel.showResults) {
                if let results = viewModel.searchResults {
                    SearchResultsView(results: results, searchType: .barcode)
                }
            }
        }
    }
}

// MARK: - Camera Preview

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        context.coordinator.previewLayer = previewLayer
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.previewLayer?.frame = uiView.bounds
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

// MARK: - ViewModel

class BarcodeScannerViewModel: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var showResults = false
    @Published var searchResults: [DiscogsRelease]?
    
    let session = AVCaptureSession()
    private var lastScannedCode: String?
    private var lastScanTime: Date?
    
    func startScanning() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            requestCameraPermission()
            return
        }
        
        setupCaptureSession()
    }
    
    func stopScanning() {
        if session.isRunning {
            session.stopRunning()
        }
    }
    
    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.setupCaptureSession()
                } else {
                    self?.errorMessage = "Camera permission is required to scan barcodes"
                    self?.showError = true
                }
            }
        }
    }
    
    private func setupCaptureSession() {
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            errorMessage = "Unable to access camera"
            showError = true
            return
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }
            
            let metadataOutput = AVCaptureMetadataOutput()
            
            if session.canAddOutput(metadataOutput) {
                session.addOutput(metadataOutput)
                
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = [.ean8, .ean13, .upce]
            }
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
            
            isScanning = true
        } catch {
            errorMessage = "Failed to set up camera: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func searchBarcode(_ barcode: String) {
        // Prevent duplicate scans within 3 seconds
        if let lastCode = lastScannedCode,
           let lastTime = lastScanTime,
           lastCode == barcode,
           Date().timeIntervalSince(lastTime) < 3 {
            return
        }
        
        lastScannedCode = barcode
        lastScanTime = Date()
        isLoading = true
        isScanning = false
        
        Task {
            do {
                let results = try await DiscogsService.shared.searchByBarcode(barcode)
                
                await MainActor.run {
                    isLoading = false
                    
                    if results.count == 1 {
                        // Auto-select if only one result
                        // Navigate to add copy view
                        searchResults = results
                        showResults = true
                    } else {
                        // Show results list
                        searchResults = results
                        showResults = true
                    }
                }
            } catch DiscogsError.noResults {
                await MainActor.run {
                    isLoading = false
                    isScanning = true
                    errorMessage = "No results found for this barcode"
                    showError = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    isScanning = true
                    errorMessage = "Failed to search: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate

extension BarcodeScannerViewModel: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard isScanning,
              let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let barcode = metadataObject.stringValue else {
            return
        }
        
        searchBarcode(barcode)
    }
}

#Preview {
    BarcodeScannerView()
}