import Foundation
import Capacitor
import Photos
import PhotosUI

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(PreviewCameraPlugin)
public class PreviewCameraPlugin: CAPPlugin {

    private var call: CAPPluginCall?
    private var previewCamera: PreviewCamera?
    private let defaultDirection = CameraDirection.rear
    private let defaultResultType = CameraResultType.base64

    // MARK: - Capacitor override methods
    override public func load() {
        guard let parentView = bridge?.viewController?.view else {
            CAPLog.print("⚡️ ", self.pluginId, "-", "CAPPlugin.bridge?.viewController.view is not available. Please file an issue")
            return
        }
        guard let webView = bridge?.webView else {
            CAPLog.print("⚡️ ", self.pluginId, "-", "CAPPlugin.bridge?.webView is not available. Please file an issue")
            return
        }
        
        
        previewCamera = PreviewCamera(webView: webView, parentView: parentView, settings: CameraSettings(), notifyListeners: notifyListeners)
    }

    @objc override public func checkPermissions(_ call: CAPPluginCall) {
        var result: [String: Any] = [:]
        for permission in CameraPermissionType.allCases {
            let state: String
            switch permission {
            case .camera:
                state = AVCaptureDevice.authorizationStatus(for: .video).authorizationState
            }
            result[permission.rawValue] = state
        }
        call.resolve(result)
    }

    @objc override public func requestPermissions(_ call: CAPPluginCall) {
        // get the list of desired types, if passes
        let typeList = call.getArray("permissions", String.self)?.compactMap({ (type) -> CameraPermissionType? in
            return CameraPermissionType(rawValue: type)
        }) ?? []
        // otherwise check everything
        let permissions: [CameraPermissionType] = (typeList.count > 0) ? typeList : CameraPermissionType.allCases
        // request the permissions
        let group = DispatchGroup()
        for permission in permissions {
            switch permission {
            case .camera:
                group.enter()
                AVCaptureDevice.requestAccess(for: .video) { _ in
                    group.leave()
                }
            }
        }
        group.notify(queue: DispatchQueue.main) { [weak self] in
            self?.checkPermissions(call)
        }
    }

    // MARK: - PreviewCamera Plugin methods
    @objc func echo(_ call: CAPPluginCall) {
        let value = call.getString("value") ?? ""
        if let implementation = previewCamera {
            call.resolve([
                "value": implementation.echo(value)
            ])
        }
    }

    @objc func startPreview(_ call: CAPPluginCall) {
        self.call = call
        // check if we have missing descriptions in Info.plist
        if let missingUsageDescription = checkUsageDescriptions() {
            CAPLog.print("⚡️ ", self.pluginId, "-", missingUsageDescription)
            call.reject(missingUsageDescription)
            bridge?.alert("Camera Error", "Missing required usage description. See console for more information")
            return
        }
        // check if we have a camera
        if bridge?.isSimEnvironment ?? false {
            CAPLog.print("⚡️ ", self.pluginId, "-", "Camera not available in simulator")
            bridge?.alert("Camera Error", "Camera not available in Simulator")
            call.reject("Camera not available while running in Simulator")
            return
        }
        // check for permission
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if authStatus == .restricted || authStatus == .denied {
            call.reject("User denied access to camera")
            return
        }
        // we either already have permission or can prompt
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            if granted {
                do {
                    try self?.previewCamera?.startCameraPreview(settings: self?.cameraSettings(from: call))
                    self?.hideBackground()
                    call.resolve()
                } catch {
                    if let err = error as? PreviewCameraError { call.reject(err.message) } else { call.reject("Unknow error on startPreview") }
                }

            }
        }
    }
    
    private func hideBackground() {
        DispatchQueue.main.async {
            self.bridge?.webView!.isOpaque = false
            self.bridge?.webView!.backgroundColor = UIColor.clear
            self.bridge?.webView!.scrollView.backgroundColor = UIColor.clear

            let javascript = "document.documentElement.style.backgroundColor = 'transparent'"

            self.bridge?.webView!.evaluateJavaScript(javascript)
        }
    }

    private func showBackground() {
        DispatchQueue.main.async {
            let javascript = "document.documentElement.style.backgroundColor = ''"

            self.bridge?.webView!.evaluateJavaScript(javascript) { (result, error) in
                self.bridge?.webView!.isOpaque = true
                self.bridge?.webView!.backgroundColor = UIColor.white
                self.bridge?.webView!.scrollView.backgroundColor = UIColor.white
            }
        }
    }

    @objc func stopPreview(_ call: CAPPluginCall) {
        // TODO: ask ionic team if is overkill check
        guard let implementation = previewCamera else {
            call.reject("Preview Camera not initialized")
            return
        }
        do {
            try implementation.stopPreviewCamera()
            self.showBackground()
            call.resolve()
        } catch let error as PreviewCameraError { call.reject(error.message) } catch { call.reject("Unknow error on stopPreview") }
    }

    @objc func takePhoto(_ call: CAPPluginCall) {
        do {
            try self.previewCamera?.takePhoto()
            call.resolve()
        } catch let error as PreviewCameraError {
            print("takePhoto")
            print(error)
            call.reject(error.message)
            
        } catch {
            call.reject("Unknow error on capture")
        }
    }

    @objc func startRecord(_ call: CAPPluginCall) {
        do {
            try self.previewCamera?.startRecord()
            call.resolve()
        } catch let error as PreviewCameraError { call.reject(error.message) } catch { call.reject("Unknow error on startRecord")}
    }

    @objc func stopRecord(_ call: CAPPluginCall) {
        do {
            try self.previewCamera?.stopRecord()
            call.resolve()
        } catch let error as PreviewCameraError { call.reject(error.message) } catch { call.reject("Unknow error on stopRecord")}
    }

    @objc func flipCamera(_ call: CAPPluginCall) {
        do {
            try self.previewCamera?.flipCamera()
            call.resolve()
        } catch let error as PreviewCameraError { call.reject(error.message) } catch { call.reject("Unknow error on flipCamera")}
    }

    @objc func getFlashModes(_ call: CAPPluginCall) {
        do {
            try self.previewCamera?.getFlashModes()
            call.resolve()
        } catch let error as PreviewCameraError { call.reject(error.message) } catch { call.reject("Unknow error getFlashModes")}

    }

    @objc func setFlashModes(_ call: CAPPluginCall) {
        do {
            try self.previewCamera?.getFlashModes()
            call.resolve()
        } catch let error as PreviewCameraError { call.reject(error.message) } catch { call.reject("Unknow error setFlashModes")}
    }
    
    @objc func isTorchOn(_ call: CAPPluginCall){
        let result = self.previewCamera?.isTorchOn()
        call.resolve([
            "result": result
        ])
    }
    
    @objc public func enableTorch(_ call: CAPPluginCall) {
        print("enable = \(call.getBool("enable"))")
        let value = call.getBool("enable") ?? false
        self.previewCamera?.enableTorch(enable: value)
        call.resolve()
    }
    
    @objc func isTorchAvailable(_ call: CAPPluginCall) {
        let result = self.previewCamera?.isTorchAvailable() ?? false
        call.resolve([
            "result": result
        ])
    }
    
    @objc func focus(_ call: CAPPluginCall) {
        guard let x = call.getFloat("x") else {
            return call.resolve()
        }
        guard let y = call.getFloat("y") else {
            return call.resolve()
        }
        self.previewCamera?.focus(x, y)
    }
    
    @objc func minAvailableZoom(_ call: CAPPluginCall) {
        let result = self.previewCamera?.minAvailableZoom() ?? 1.0
        call.resolve([
            "result": result
        ])
    }
    
    @objc func maxAvailableZoom(_ call: CAPPluginCall) {
        let result = self.previewCamera?.maxAvailableZoom() ?? 1.0
        call.resolve([
            "result": result
        ])
    }
    
    @objc func zoom(_ call: CAPPluginCall) {
        guard let zoomFactor = call.getFloat("factor") else {
            return call.resolve()
        }
        self.previewCamera?.zoom(zoomFactor)
        
    }
    
    @objc func setQuality(_ call: CAPPluginCall) {
        let quality = call.getString("quality") ?? "hq"
        self.previewCamera?.setQuality(quality)
        call.resolve()
    }

    // MARK: - Helper methods
    func checkUsageDescriptions() -> String? {
        if let dict = Bundle.main.infoDictionary {
            for key in CameraPropertyListKeys.allCases where dict[key.rawValue] == nil {
                return key.missingMessage
            }
        }
        return nil
    }

    func cameraSettings(from call: CAPPluginCall) -> CameraSettings {
        var settings = CameraSettings()
        settings.jpegQuality = min(abs(CGFloat(call.getFloat("quality", 100.0) / 100.0)), 1.0)
        settings.direction = CameraDirection(rawValue: call.getString("direction", defaultDirection.rawValue)) ?? defaultDirection
        settings.resultType = CameraResultType(rawValue: call.getString("resultType", defaultResultType.rawValue)) ?? defaultResultType
        settings.width = CGFloat(call.getInt("width") ?? 0)
        settings.height = CGFloat(call.getInt("height") ?? 0)
        if settings.width > 0 || settings.height > 0 {
            settings.shouldResize = true
        }
        settings.shouldCorrectOrientation = call.getBool("correctOrientation", true)
        settings.forcePortraitOrientation = call.getBool("forcePortraitOrientation", true)
        settings.mirrorFrontCameraResult = call.getBool("mirrorFrontCameraResult", true)
        return settings
    }
    
}
