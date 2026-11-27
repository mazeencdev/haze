import SwiftUI
import ScreenCaptureKit
import AVFoundation

/// Scripted product tour used to produce the demo video.
///
///     HAZE_DEMO=autoplay HAZE_SKY_HOUR=13 HAZE_RECORD=/path/tour.mov open Haze.app
///
/// Runs on sample data, records the Haze window to HAZE_RECORD and writes a
/// timeline of cues (clicks, keystrokes, chapter changes) to HAZE_RECORD.log
/// so sound effects and captions can be lined up afterwards.
@MainActor
enum DemoDirector {
    private static var t0 = CACurrentMediaTime()
    private static var cues: [String] = []

    static func mark(_ cue: String) {
        cues.append(String(format: "%.3f %@", CACurrentMediaTime() - t0, cue))
    }

    static func runIfRequested(app: AppModel) async {
        let env = ProcessInfo.processInfo.environment
        guard env["HAZE_DEMO"] == "autoplay" else { return }
        try? await Task.sleep(for: .seconds(2))

        var recorder: WindowRecorder?
        if let path = env["HAZE_RECORD"] {
            let r = WindowRecorder(url: URL(fileURLWithPath: path))
            do {
                try await r.start()
                recorder = r
            } catch {
                try? "error \(error.localizedDescription)\n".write(toFile: path + ".log", atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
        t0 = CACurrentMediaTime()
        mark("start")

        await tour(app)

        try? await Task.sleep(for: .seconds(1))
        if let recorder, let path = env["HAZE_RECORD"] {
            await recorder.stop()
            let header = String(format: "offset %.3f\n", t0 - recorder.firstFrameTime)
            try? (header + cues.joined(separator: "\n") + "\n").write(toFile: path + ".log", atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }

    private static func wait(_ s: Double) async { try? await Task.sleep(for: .milliseconds(Int(s * 1000))) }

    private static func type(_ text: String, into set: (String) -> Void) async {
        var typed = ""
        for ch in text {
            typed.append(ch)
            set(typed)
            mark(ch == " " ? "space" : "key")
            await wait(Double.random(in: 0.055...0.11))
        }
    }

    private static func tour(_ app: AppModel) async {
        let store = app.store
        let week = weekDays(containing: Date())

        // 01 — Week
        mark("chapter week")
        await wait(3.2)
        let today = week.firstIndex { $0.isToday } ?? 4
        mark("click")
        app.focusedDay = today
        await wait(2.3)
        mark("click")
        app.focusedDay = nil
        await wait(1.3)
        if let ev = store.events.first(where: { $0.title == "Design review" }) {
            mark("click")
            app.select(ev)
        }
        await wait(2.6)

        // drag "Brand moodboard" one day later and 90 minutes down
        if let mb = store.events.first(where: { $0.title == "Brand moodboard" }),
           let day = week.firstIndex(where: { $0.isSameDay(mb.start) }) {
            app.select(nil)
            await wait(0.5)
            mark("lift")
            app.dragDay = day
            app.dragMin = 0
            withAnimation(Haze.snappy) { app.dragID = mb.id + "#\(day)" }
            await wait(0.45)
            for step in 1...6 {
                mark("tick")
                withAnimation(.spring(response: 0.2, dampingFraction: 0.78)) {
                    app.dragMin = step * 15
                    if step == 3 { app.dragDay = min(6, day + 1) }
                }
                await wait(0.17)
            }
            await wait(0.45)
            mark("drop")
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) {
                app.commitMove(mb, days: app.dragDay - day, minutes: app.dragMin)
                app.dragID = nil
                app.dragMin = 0
            }
        }
        await wait(2.6)

        // 02 — Compose
        mark("chapter compose")
        await wait(0.6)
        mark("whoosh")
        app.newEvent()
        await wait(1.2)
        await type("Coffee with Ana tomorrow 9am") { app.demoTitle = $0 }
        mark("sparkle")
        await wait(1.5)
        mark("click")
        app.demoPlace = DemoPlace(name: "Sightglass Coffee, 270 7th St", lat: 37.7771, lon: -122.4085)
        await wait(2.0)
        mark("save")
        app.demoSaveTick += 1
        await wait(3.0)
        app.select(nil)
        app.demoTitle = nil
        app.demoPlace = nil

        // 03 — To-dos
        mark("chapter todo")
        await wait(1.2)
        await type("Call mom tomorrow 5pm") { app.demoTodoText = $0 }
        await wait(0.9)
        mark("pop")
        app.demoTodoSubmit += 1
        app.demoTodoText = nil
        await wait(1.5)
        for title in ["Pick up flowers for dinner", "Book flights for December"] {
            if let t = store.todos.first(where: { $0.title == title }) {
                mark("check")
                store.setCompleted(t, true)
            }
            await wait(1.5)
        }
        await wait(0.8)

        // 04 — Month
        mark("chapter month")
        app.setPage(.month)
        await wait(1.8)
        let path: [(CGFloat, CGFloat)] = [(90, 60), (420, 200), (760, 260), (900, 420), (520, 460)]
        mark("hover")
        for i in 0..<(path.count - 1) {
            let (a, b) = (path[i], path[i + 1])
            for f in 0...24 {
                let k = CGFloat(f) / 24
                let e = k * k * (3 - 2 * k)
                withAnimation(.linear(duration: 0.04)) {
                    app.demoPointer = CGPoint(x: a.0 + (b.0 - a.0) * e, y: a.1 + (b.1 - a.1) * e)
                }
                await wait(1.0 / 40)
            }
        }
        withAnimation(.easeOut(duration: 0.3)) { app.demoPointer = nil }
        await wait(0.8)
        mark("whoosh")
        app.shift(1)
        await wait(1.8)
        mark("whoosh")
        app.shift(-1)
        await wait(1.6)

        // 05 — Agenda + search
        mark("chapter agenda")
        app.setPage(.agenda)
        await wait(2.2)
        await type("design") { app.demoSearch = $0 }
        await wait(2.2)
        app.demoSearch = ""
        await wait(1.2)

        // 06 — Places
        mark("chapter places")
        app.setPage(.places)
        await wait(2.0)
        for title in ["Farmers market", "Lunch with Ana"] {
            if let ev = store.events.first(where: { $0.title == title }) {
                mark("whoosh")
                app.placeFocusID = ev.id
            }
            await wait(3.8)
        }

        // Outro
        mark("chapter end")
        app.select(nil)
        app.placeFocusID = nil
        app.setPage(.week)
        await wait(3.0)
        mark("end")
    }
}

/// Records one of Haze's own windows with ScreenCaptureKit.
final class WindowRecorder: NSObject, SCStreamOutput {
    private let url: URL
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private let queue = DispatchQueue(label: "haze.recorder")
    private var started = false
    private(set) var firstFrameTime: Double = 0

    init(url: URL) { self.url = url }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let pid = ProcessInfo.processInfo.processIdentifier
        guard let win = content.windows
            .filter({ $0.owningApplication?.processID == pid && $0.frame.width > 600 })
            .max(by: { $0.frame.width < $1.frame.width }) else {
            throw NSError(domain: "Haze", code: 1, userInfo: [NSLocalizedDescriptionKey: "Haze window not found"])
        }
        let w = Int(win.frame.width * 2) & ~1, h = Int(win.frame.height * 2) & ~1
        let cfg = SCStreamConfiguration()
        cfg.width = w
        cfg.height = h
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        cfg.showsCursor = false
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.queueDepth = 8
        cfg.ignoreShadowsSingleWindow = true

        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 45_000_000],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        writer.startWriting()
        self.writer = writer
        self.input = input

        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: win), configuration: cfg, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid,
              let att = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = att.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let writer, let input else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        if !started {
            writer.startSession(atSourceTime: pts)
            firstFrameTime = pts.seconds
            started = true
        }
        if input.isReadyForMoreMediaData { input.append(sb) }
    }

    func stop() async {
        try? await stream?.stopCapture()
        queue.sync {}
        input?.markAsFinished()
        await writer?.finishWriting()
    }
}
