import AppKit
import AVFoundation
import CoreGraphics
import ServiceManagement

final class KeyboardMonitor: @unchecked Sendable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var thread: Thread?
    private let handler: @Sendable (UInt16, Bool) -> Void
    private let lock = NSLock()
    private var active = false

    init(handler: @escaping @Sendable (UInt16, Bool) -> Void) {
        self.handler = handler
    }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    func start() {
        guard thread == nil else { return }
        let monitorThread = Thread { [weak self] in self?.run() }
        monitorThread.name = "pt.arqueox.neokeys.keyboard-monitor"
        thread = monitorThread
        monitorThread.start()
    }

    func stop() {
        if let source = runLoopSource { CFRunLoopSourceInvalidate(source) }
        if let tap = eventTap { CFMachPortInvalidate(tap) }
        lock.lock()
        active = false
        lock.unlock()
    }

    private func run() {
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        let info = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = monitor.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                if type == .keyDown {
                    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                    monitor.handler(keyCode, isRepeat)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: info
        ) else {
            NSLog("NeoKeys: não foi possível criar CGEventTap. Verifique Monitorização de entrada.")
            return
        }

        eventTap = tap
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        lock.lock()
        active = true
        lock.unlock()
        CFRunLoopRun()
    }
}

enum SoundProfile: String, CaseIterable {
    case mechanicalReal = "Cherry Real"
    case typewriterReal = "Máquina de escrever real"
    case butterfly = "Butterfly"
    case thock = "Thock"
    case clicky = "Clicky"
    case creamy = "Creamy"
    case typewriter = "Typewriter"
    case soft = "Soft"
    case pain = "Pain Mode"
    case fart = "Fart Mode"

    var symbol: String {
        switch self {
        case .mechanicalReal: return "keyboard.fill"
        case .typewriterReal: return "character.cursor.ibeam"
        case .butterfly: return "rectangle.compress.vertical"
        case .thock: return "waveform"
        case .clicky: return "cursorarrow.click"
        case .creamy: return "drop.fill"
        case .typewriter: return "keyboard"
        case .soft: return "cloud.fill"
        case .pain: return "bolt.heart.fill"
        case .fart: return "wind"
        }
    }

    var isRecorded: Bool {
        self == .mechanicalReal || self == .typewriterReal || self == .pain || self == .fart
    }
}

@MainActor
final class SoundEngine {
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [SoundProfile: [AVAudioPCMBuffer]] = [:]
    private var recordedBanks: [SoundProfile: [String: [AVAudioPlayer]]] = [:]
    private var nextPlayer = 0
    private var nextRecordedVoice = 0
    private var volume: Float = 0.55
    private let format: AVAudioFormat
    private(set) var lastError: String?

    init() {
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 48_000
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        for _ in 0..<16 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        for profile in SoundProfile.allCases where !profile.isRecorded {
            buffers[profile] = (0..<6).compactMap { makeBuffer(profile: profile, variation: $0) }
        }
        loadRecordedProfile(.mechanicalReal, folder: "Mechanical")
        loadRecordedProfile(.typewriterReal, folder: "Typewriter")
        loadRecordedProfile(.pain, folder: "Pain")
        loadRecordedProfile(.fart, folder: "Fart")
        engine.prepare()
        startEngine()
    }

    func setVolume(_ volume: Float) {
        self.volume = volume
        engine.mainMixerNode.outputVolume = volume
        for bank in recordedBanks.values {
            for players in bank.values { players.forEach { $0.volume = volume } }
        }
    }

    @discardableResult
    func play(profile: SoundProfile, keyCode: UInt16) -> Bool {
        if profile.isRecorded { return playRecorded(profile: profile, keyCode: keyCode) }
        if !engine.isRunning { startEngine() }
        guard engine.isRunning, let choices = buffers[profile], !choices.isEmpty else { return false }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        let index: Int
        switch keyCode {
        case 49: index = min(5, choices.count - 1)       // Space
        case 36, 76: index = min(4, choices.count - 1)  // Return / keypad Enter
        case 51, 117: index = min(3, choices.count - 1) // Delete
        default: index = Int.random(in: 0..<min(3, choices.count))
        }
        player.stop()
        player.scheduleBuffer(choices[index], at: nil, options: .interrupts)
        player.play()
        return true
    }

    private func loadRecordedProfile(_ profile: SoundProfile, folder: String) {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("Sounds/\(folder)"),
              let urls = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        var bank: [String: [AVAudioPlayer]] = [:]
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where ["wav", "mp3", "aiff", "caf"].contains(url.pathExtension.lowercased()) {
            let voices = (0..<3).compactMap { _ -> AVAudioPlayer? in
                guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
                player.volume = volume
                player.prepareToPlay()
                return player
            }
            if !voices.isEmpty { bank[url.deletingPathExtension().lastPathComponent] = voices }
        }
        recordedBanks[profile] = bank
    }

    private func playRecorded(profile: SoundProfile, keyCode: UInt16) -> Bool {
        guard let bank = recordedBanks[profile], !bank.isEmpty else {
            lastError = "Os ficheiros de som gravado não foram encontrados no pacote da aplicação."
            return false
        }
        let allNames = bank.keys.sorted()
        let preferred: [String]
        if profile == .fart {
            switch keyCode {
            case 36, 76: preferred = allNames.filter { $0.hasPrefix("enter-") }
            default: preferred = allNames.filter { $0.hasPrefix("key-") }
            }
        } else if profile == .pain {
            switch keyCode {
            case 36, 76: preferred = allNames.filter { $0.hasPrefix("enter-") }
            case 49: preferred = allNames.filter { $0.hasPrefix("space-") }
            case 51, 117: preferred = allNames.filter { $0.hasPrefix("delete-") }
            case 56, 60, 57: preferred = allNames.filter { $0.hasPrefix("shift-") }
            default: preferred = allNames.filter { $0.hasPrefix("key-") }
            }
        } else if profile == .typewriterReal {
            switch keyCode {
            case 49: preferred = allNames.filter { $0.lowercased().contains("space") }
            case 36, 76: preferred = allNames.filter { $0.lowercased().contains("return") }
            case 51, 117: preferred = allNames.filter { $0.lowercased().contains("backspace") || $0.lowercased().contains("delete") }
            default: preferred = allNames.filter { $0.lowercased().hasPrefix("key-") || $0.lowercased().contains("standard") }
            }
        } else {
            preferred = allNames
        }
        let candidates = preferred.isEmpty ? allNames : preferred
        guard let name = candidates.randomElement(), let voices = bank[name], !voices.isEmpty else { return false }
        let player = voices[nextRecordedVoice % voices.count]
        nextRecordedVoice = (nextRecordedVoice + 1) % 10_000
        player.stop()
        player.currentTime = 0
        player.volume = volume
        lastError = player.play() ? nil : "A saída de áudio recusou a reprodução."
        return lastError == nil
    }

    private func startEngine() {
        do {
            try engine.start()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            NSLog("NeoKeys audio error: %@", error.localizedDescription)
        }
    }

    private func makeBuffer(profile: SoundProfile, variation: Int) -> AVAudioPCMBuffer? {
        let duration: Double
        switch profile {
        case .mechanicalReal, .typewriterReal, .pain, .fart: return nil
        case .butterfly: duration = variation == 5 ? 0.070 : 0.048
        case .thock: duration = 0.105
        case .clicky: duration = 0.055
        case .creamy: duration = 0.085
        case .typewriter: duration = 0.075
        case .soft: duration = 0.050
        }
        let count = AVAudioFrameCount(duration * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = count

        var seed = UInt64(variation + 1) &* 0x9E3779B97F4A7C15
        func noise() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float(Int32(truncatingIfNeeded: seed >> 32)) / Float(Int32.max)
        }

        let sr = format.sampleRate
        for i in 0..<Int(count) {
            let t = Double(i) / sr
            let v = Double(variation) - 2.5
            let sample: Double
            switch profile {
            case .mechanicalReal, .typewriterReal, .pain, .fart:
                sample = 0
            case .butterfly:
                // Short, crisp, low-travel response inspired by Apple's butterfly keyboard.
                let attack = Double(noise()) * exp(-t * 260)
                let plate = sin(2 * .pi * (1_850 + v * 85) * t) * exp(-t * 155)
                let body = sin(2 * .pi * (430 + v * 12) * t) * exp(-t * 90)
                let reboundTime = t - 0.0085
                let rebound = reboundTime > 0
                    ? sin(2 * .pi * (2_250 + v * 60) * reboundTime) * exp(-reboundTime * 240)
                    : 0
                let groupBody = variation == 5 ? body * 0.34 : body * 0.20
                sample = attack * 0.34 + plate * 0.38 + groupBody + rebound * 0.16
            case .thock:
                let body = sin(2 * .pi * (118 + v * 4) * t) * exp(-t * 35)
                let tap = Double(noise()) * exp(-t * 95)
                sample = body * 0.78 + tap * 0.24
            case .clicky:
                let snap = Double(noise()) * exp(-t * 145)
                let click = sin(2 * .pi * (2_100 + v * 70) * t) * exp(-t * 110)
                sample = snap * 0.48 + click * 0.42
            case .creamy:
                let body = sin(2 * .pi * (205 + v * 6) * t) * exp(-t * 45)
                let smooth = sin(2 * .pi * (410 + v * 8) * t) * exp(-t * 65)
                sample = body * 0.55 + smooth * 0.23 + Double(noise()) * exp(-t * 130) * 0.12
            case .typewriter:
                let strike = Double(noise()) * exp(-t * 115)
                let metal = sin(2 * .pi * (1_350 + v * 55) * t) * exp(-t * 48)
                sample = strike * 0.45 + metal * 0.32
            case .soft:
                let body = sin(2 * .pi * (285 + v * 5) * t) * exp(-t * 75)
                sample = body * 0.28 + Double(noise()) * exp(-t * 160) * 0.10
            }
            let attack = min(1.0, t * 2_800)
            channel[i] = Float(max(-1, min(1, sample * attack)))
        }
        return buffer
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let defaults = UserDefaults.standard
    private let soundEngine = SoundEngine()
    private var statusItem: NSStatusItem!
    private var keyboardMonitor: KeyboardMonitor?
    private var enabled = true
    private var profile: SoundProfile = .thock
    private var volume: Float = 0.55
    private var painKeyCount = 0
    private var traumatizedEnterCount = 0
    private weak var painKeysItem: NSMenuItem?
    private weak var painEntersItem: NSMenuItem?
    private weak var painWellbeingItem: NSMenuItem?

    private var isMacBookNeo: Bool {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return false }
        var model = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &model, &size, nil, 0) == 0 else { return false }
        let bytes = model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self).hasPrefix("Mac17,5")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true
        profile = SoundProfile(rawValue: defaults.string(forKey: "profile") ?? "") ?? .mechanicalReal
        volume = defaults.object(forKey: "volume") as? Float ?? 0.55
        soundEngine.setVolume(volume)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "keyboard.badge.ellipsis", accessibilityDescription: "NeoKeys")
        statusItem.button?.toolTip = "NeoKeys"
        installKeyboardMonitor()
        rebuildMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.rebuildMenu() }

        if !isMacBookNeo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showUnsupportedMacWarning()
            }
        }

        if !CGPreflightListenEventAccess() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                _ = CGRequestListenEventAccess()
                self?.rebuildMenu()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardMonitor?.stop()
    }

    private func installKeyboardMonitor() {
        let monitor = KeyboardMonitor { [weak self] keyCode, isRepeat in
            DispatchQueue.main.async {
                guard let self, self.enabled, !isRepeat else { return }
                let played = self.soundEngine.play(profile: self.profile, keyCode: keyCode)
                if played, self.profile == .pain { self.recordPain(for: keyCode) }
            }
        }
        keyboardMonitor = monitor
        monitor.start()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let title = NSMenuItem(title: "NeoKeys · exclusivo para MacBook Neo", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let toggle = NSMenuItem(title: enabled ? "Desativar sons" : "Ativar sons", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.image = NSImage(systemSymbolName: enabled ? "speaker.wave.2.fill" : "speaker.slash.fill", accessibilityDescription: nil)
        menu.addItem(toggle)
        menu.addItem(.separator())

        let profiles = NSMenuItem(title: "Perfil sonoro", action: nil, keyEquivalent: "")
        let profileMenu = NSMenu()
        for option in SoundProfile.allCases {
            if option == .pain {
                profileMenu.addItem(.separator())
                let funTitle = NSMenuItem(title: "Fun Lab", action: nil, keyEquivalent: "")
                funTitle.isEnabled = false
                profileMenu.addItem(funTitle)
            }
            let item = NSMenuItem(title: option.rawValue, action: #selector(selectProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = option == profile ? .on : .off
            item.image = NSImage(systemSymbolName: option.symbol, accessibilityDescription: nil)
            profileMenu.addItem(item)
        }
        profiles.submenu = profileMenu
        menu.addItem(profiles)

        let volumeItem = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 245, height: 42))
        let icon = NSImageView(frame: NSRect(x: 16, y: 11, width: 18, height: 18))
        icon.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "Volume")
        let slider = NSSlider(value: Double(volume), minValue: 0.05, maxValue: 1, target: self, action: #selector(changeVolume(_:)))
        slider.frame = NSRect(x: 44, y: 7, width: 185, height: 28)
        slider.isContinuous = true
        container.addSubview(icon)
        container.addSubview(slider)
        volumeItem.view = container
        menu.addItem(volumeItem)

        let testSound = NSMenuItem(title: "Testar som", action: #selector(testSound), keyEquivalent: "")
        testSound.target = self
        testSound.image = NSImage(systemSymbolName: "play.circle", accessibilityDescription: nil)
        menu.addItem(testSound)

        if profile == .pain {
            menu.addItem(.separator())
            let tagline = NSMenuItem(title: "Every key suffers. Enter screams the loudest.", action: nil, keyEquivalent: "")
            tagline.isEnabled = false
            menu.addItem(tagline)

            let keys = NSMenuItem(title: painKeysTitle, action: nil, keyEquivalent: "")
            keys.isEnabled = false
            painKeysItem = keys
            menu.addItem(keys)

            let enters = NSMenuItem(title: painEntersTitle, action: nil, keyEquivalent: "")
            enters.isEnabled = false
            painEntersItem = enters
            menu.addItem(enters)

            let wellbeing = NSMenuItem(title: painWellbeingTitle, action: nil, keyEquivalent: "")
            wellbeing.isEnabled = false
            painWellbeingItem = wellbeing
            menu.addItem(wellbeing)

            let support = NSMenuItem(title: "❤️ Support the Keys", action: #selector(supportTheKeys), keyEquivalent: "")
            support.target = self
            menu.addItem(support)
        } else {
            painKeysItem = nil
            painEntersItem = nil
            painWellbeingItem = nil
        }
        menu.addItem(.separator())

        if !CGPreflightListenEventAccess() {
            let permission = NSMenuItem(title: "Autorizar deteção do teclado…", action: #selector(requestPermission), keyEquivalent: "")
            permission.target = self
            permission.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            menu.addItem(permission)
        } else {
            let status = keyboardMonitor?.isActive == true ? "Deteção global ativa" : "Permissão concedida · reinicie a app"
            let permitted = NSMenuItem(title: status, action: nil, keyEquivalent: "")
            permitted.isEnabled = false
            permitted.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            menu.addItem(permitted)
        }

        if #available(macOS 13.0, *) {
            let login = NSMenuItem(title: "Abrir ao iniciar sessão", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            login.target = self
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(login)
        }

        menu.addItem(.separator())
        let about = NSMenuItem(title: "Sobre o NeoKeys", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: "Sair", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        defaults.set(enabled, forKey: "enabled")
        statusItem.button?.image = NSImage(systemSymbolName: enabled ? "keyboard.badge.ellipsis" : "keyboard", accessibilityDescription: "NeoKeys")
        rebuildMenu()
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let selected = SoundProfile(rawValue: raw) else { return }
        profile = selected
        defaults.set(selected.rawValue, forKey: "profile")
        soundEngine.play(profile: selected, keyCode: UInt16.random(in: 0...100))
        rebuildMenu()
    }

    @objc private func changeVolume(_ sender: NSSlider) {
        volume = Float(sender.doubleValue)
        soundEngine.setVolume(volume)
        defaults.set(volume, forKey: "volume")
    }

    @objc private func testSound() {
        let testKeyCode: UInt16 = (profile == .pain || profile == .fart) ? 36 : 49
        if !soundEngine.play(profile: profile, keyCode: testKeyCode) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Não foi possível reproduzir o som"
            alert.informativeText = soundEngine.lastError ?? "Verifique a saída de áudio selecionada nas Definições do Sistema."
            alert.runModal()
        }
    }

    private var painKeysTitle: String { "Keys hurt this session: \(painKeyCount)" }
    private var painEntersTitle: String { "Enters traumatized: \(traumatizedEnterCount)" }

    private var painWellbeingTitle: String {
        let state: String
        switch painKeyCount {
        case 0..<25: state = "Stable"
        case 25..<100: state = "Concerned"
        case 100..<250: state = "Distressed"
        default: state = "Critical"
        }
        return "Keyboard wellbeing: \(state)"
    }

    private func recordPain(for keyCode: UInt16) {
        painKeyCount += 1
        if keyCode == 36 || keyCode == 76 { traumatizedEnterCount += 1 }
        painKeysItem?.title = painKeysTitle
        painEntersItem?.title = painEntersTitle
        painWellbeingItem?.title = painWellbeingTitle
    }

    @objc private func supportTheKeys() {
        let alert = NSAlert()
        alert.messageText = "Thank you…"
        alert.informativeText = "The keys feel seen. Type gently."
        alert.addButton(withTitle: "I support the keys")
        alert.runModal()
    }

    @objc private func requestPermission() {
        _ = CGRequestListenEventAccess()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.rebuildMenu() }
    }

    @available(macOS 13.0, *)
    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Não foi possível alterar o início automático"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        rebuildMenu()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "NeoKeys — exclusivamente para MacBook Neo"
        alert.informativeText = "App criada especificamente para o MacBook Neo. Inclui gravações reais de teclado físico e máquina de escrever. Não existe suporte oficial para outros modelos Mac.\n\nEscolha um perfil na barra de menus e escreva em qualquer aplicação."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showUnsupportedMacWarning() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Este Mac não é um MacBook Neo"
        alert.informativeText = "NeoKeys foi criada e testada exclusivamente para o MacBook Neo. O funcionamento noutros modelos não é suportado."
        alert.addButton(withTitle: "Compreendo")
        alert.runModal()
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
