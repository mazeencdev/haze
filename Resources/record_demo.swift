// Records the scripted Haze tour.
// Usage: swift Resources/record_demo.swift <out.mov>
// Writes <out.mov>, <out.mov>.cues (from the app) and <out.mov>.t0 (host time of first frame).
import AppKit
import ScreenCaptureKit
import AVFoundation

final class Recorder: NSObject, SCStreamOutput {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let queue = DispatchQueue(label: "rec")
    var started = false
    var firstFrame: Double = 0

    init(url: URL, w: Int, h: Int) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 45_000_000],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        writer.startWriting()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid,
              let att = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = att.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        if !started { writer.startSession(atSourceTime: pts); firstFrame = pts.seconds; started = true }
        if input.isReadyForMoreMediaData { input.append(sb) }
    }
}

_ = NSApplication.shared   // connect to the window server
_ = CGMainDisplayID()

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let appURL = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Haze.app")
let goFile = out.path + ".go"
try? FileManager.default.removeItem(atPath: goFile)

// Launch Haze in autoplay mode on sample data
let cfgOpen = NSWorkspace.OpenConfiguration()
cfgOpen.environment = ["HAZE_DEMO": "autoplay", "HAZE_SKY_HOUR": "13", "HAZE_GO_FILE": goFile, "HAZE_CUES": out.path + ".cues"]
cfgOpen.createsNewApplicationInstance = true
let haze: NSRunningApplication = try await withCheckedThrowingContinuation { cont in
    NSWorkspace.shared.openApplication(at: appURL, configuration: cfgOpen) { app, err in
        if let app { cont.resume(returning: app) } else { cont.resume(throwing: err ?? NSError(domain: "rec", code: 1)) }
    }
}
try await Task.sleep(for: .seconds(3))

let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
guard let win = content.windows.filter({ $0.owningApplication?.processID == haze.processIdentifier && $0.frame.width > 600 })
        .max(by: { $0.frame.width < $1.frame.width }) else { fatalError("Haze window not found") }
let w = Int(win.frame.width * 2) & ~1, h = Int(win.frame.height * 2) & ~1
let cfg = SCStreamConfiguration()
cfg.width = w; cfg.height = h
cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
cfg.showsCursor = false
cfg.queueDepth = 8
cfg.ignoreShadowsSingleWindow = true
let rec = try Recorder(url: out, w: w, h: h)
let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: win), configuration: cfg, delegate: nil)
try stream.addStreamOutput(rec, type: SCStreamOutputType.screen, sampleHandlerQueue: rec.queue)
try await stream.startCapture()
FileManager.default.createFile(atPath: goFile, contents: nil)

while !haze.isTerminated { try await Task.sleep(for: .milliseconds(250)) }
try? await stream.stopCapture()
rec.queue.sync {}
rec.input.markAsFinished()
await rec.writer.finishWriting()
try String(format: "%.4f\n", rec.firstFrame).write(toFile: out.path + ".t0", atomically: true, encoding: .utf8)
try? FileManager.default.removeItem(atPath: goFile)
print("recorded", out.path)
