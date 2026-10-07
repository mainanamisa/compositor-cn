import AppKit
import SwiftUI

struct ShortcutChord: Codable, Equatable, Hashable {
    var key: String
    var modifiers: Int
    init(_ key: String, _ modifiers: Int = 0) { self.key = key; self.modifiers = modifiers }
    // Stable stored bits: Command, Option, Control, Shift.
    init(_ event: NSEvent) {
        let flags = event.modifierFlags
        modifiers = (flags.contains(.command) ? 1 : 0) | (flags.contains(.option) ? 2 : 0)
            | (flags.contains(.control) ? 4 : 0) | (flags.contains(.shift) ? 8 : 0)
        switch event.keyCode {
        case 51, 117: key = "\u{7f}"
        case 36, 76: key = "\r"
        case 53: key = "\u{1b}"
        case 48: key = "\t"
        case 49: key = " "
        case 123: key = "\u{f702}"
        case 124: key = "\u{f703}"
        case 125: key = "\u{f701}"
        case 126: key = "\u{f700}"
        default:
            let typed = event.charactersIgnoringModifiers?.lowercased() ?? ""
            key = ["{": "[", "}": "]", "+": "=", "_": "-" ][typed] ?? typed
        }
    }
    var eventModifiers: EventModifiers {
        var flags: EventModifiers = []
        if modifiers & 1 != 0 { flags.insert(.command) }
        if modifiers & 2 != 0 { flags.insert(.option) }
        if modifiers & 4 != 0 { flags.insert(.control) }
        if modifiers & 8 != 0 { flags.insert(.shift) }
        return flags
    }
    var cocoaModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & 1 != 0 { flags.insert(.command) }
        if modifiers & 2 != 0 { flags.insert(.option) }
        if modifiers & 4 != 0 { flags.insert(.control) }
        if modifiers & 8 != 0 { flags.insert(.shift) }
        return flags
    }
    var label: String {
        let special = ["\u{7f}": "Delete", "\r": "Return", "\u{1b}": "Esc", "\t": "Tab", " ": "Space",
                       "\u{f702}": "←", "\u{f703}": "→", "\u{f701}": "↓", "\u{f700}": "↑"]
        return (modifiers & 4 != 0 ? "⌃" : "") + (modifiers & 2 != 0 ? "⌥" : "")
            + (modifiers & 8 != 0 ? "⇧" : "") + (modifiers & 1 != 0 ? "⌘" : "")
            + (special[key] ?? key.uppercased())
    }
    func event(like event: NSEvent) -> NSEvent? {
        let codes: [String: UInt16] = ["\u{7f}": 51, "\r": 36, "\u{1b}": 53, "\t": 48, " ": 49,
                                       "\u{f702}": 123, "\u{f703}": 124, "\u{f701}": 125, "\u{f700}": 126,
                                       "=": 24, "-": 27]
        let shifted = modifiers & 8 != 0 ? (["[": "{", "]": "}", "=": "+", "-": "_"][key] ?? key) : key
        return NSEvent.keyEvent(with: event.type, location: event.locationInWindow, modifierFlags: cocoaModifiers,
            timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil,
            characters: shifted, charactersIgnoringModifiers: shifted, isARepeat: event.isARepeat,
            keyCode: codes[key] ?? 0xffff)
    }
}

struct ShortcutDefinition: Identifiable {
    let title: String
    let group: String
    let original: ShortcutChord
    var id: String { "\(group):\(title)" }
    var isMenu: Bool { group == "菜单" }

    static let all: [ShortcutDefinition] = {
        func entry(_ title: String, _ key: String, _ modifiers: Int = 0, menu: Bool = false) -> ShortcutDefinition {
            .init(title: title, group: menu ? "菜单" : "画布与图层", original: ShortcutChord(key, modifiers))
        }
        var result: [ShortcutDefinition] = [
            entry("撤销", "z", 1, menu: true), entry("重做", "z", 9, menu: true),
            entry("新建画布", "n", 1, menu: true), entry("打开项目", "o", 1, menu: true),
            entry("存储", "s", 1, menu: true), entry("存储为", "s", 9, menu: true),
            entry("导出 PNG", "e", 9, menu: true), entry("导出 JPEG", "s", 11, menu: true),
            entry("导出为", "e", 3, menu: true),
            entry("关闭项目", "w", 1, menu: true), entry("适合画布", "0", 1, menu: true),
            entry("实际像素", "1", 1, menu: true), entry("放大", "=", 1, menu: true),
            entry("缩小", "-", 1, menu: true), entry("显示变换控件", "h", 1, menu: true),
            entry("隐藏 Compositor", "h", 3, menu: true), entry("剪切", "x", 1, menu: true),
            entry("拷贝", "c", 1, menu: true), entry("合并拷贝", "c", 9, menu: true),
            entry("粘贴", "v", 1, menu: true), entry("填充前景色", "\u{7f}", 2, menu: true),
            entry("填充背景色", "\u{7f}", 1, menu: true), entry("内容识别填充", "\u{7f}", 8, menu: true),
            entry("全选", "a", 1, menu: true), entry("取消选择", "d", 1, menu: true),
            entry("反向选择", "i", 9, menu: true), entry("选择主体", "a", 3, menu: true),
            entry("曲线", "m", 1, menu: true), entry("色阶", "l", 1, menu: true),
            entry("色相/饱和度", "u", 1, menu: true), entry("反相像素 / 蒙版", "i", 1, menu: true),
            entry("画布大小", "c", 3, menu: true), entry("图像大小", "i", 3, menu: true),
            entry("变换图层 / 选区", "t", 1, menu: true), entry("复制 / 通过拷贝新建图层", "j", 1, menu: true),
            entry("切换剪贴蒙版", "g", 3, menu: true), entry("图层编组", "g", 1, menu: true),
            entry("取消图层编组", "g", 9, menu: true),
            entry("新建空白图层", "n", 9, menu: true), entry("上移图层", "]", 1, menu: true),
            entry("下移图层", "[", 1, menu: true), entry("合并图层", "e", 1, menu: true),
            entry("显示网格", "'", 1, menu: true), entry("显示参考线", ";", 1, menu: true),
            entry("显示标尺", "r", 1, menu: true), entry("对齐", ";", 9, menu: true),
            entry("锁定参考线", ";", 3, menu: true)
        ]
        for (title, key) in [("选择工具", "a"), ("移动 / 变换工具", "v"), ("抓手工具", "h"),
            ("缩放工具", "z"), ("画笔工具", "b"), ("橡皮擦", "e"), ("污点修复", "j"),
            ("仿制图章", "s"), ("文字工具", "t"), ("渐变工具", "g"), ("形状工具", "u"),
            ("吸管工具", "i"), ("选框 / 循环形状", "m"), ("魔棒", "w"),
            ("套索 / 循环模式", "l"), ("模糊 / 涂抹 / 液化", "r"), ("裁剪工具", "c"),
            ("交换前景色/背景色", "x"), ("复位颜色", "d"), ("循环工具模式", "\t"),
            ("临时抓手工具（按住）", " "), ("删除选区 / 图层 / 效果 / 套索锚点", "\u{7f}"),
            ("应用当前画布操作", "\r"), ("取消当前画布操作", "\u{1b}"),
            ("减小画笔大小", "["), ("增大画笔大小", "]")] {
            result.append(entry(title, key))
        }
        result += [entry("减小画笔硬度", "[", 8), entry("增大画笔硬度", "]", 8),
                   entry("上一个混合模式", "-", 8), entry("下一个混合模式", "=", 8),
                   entry("循环形状类型", "u", 8)]
        for digit in 0...9 { result.append(entry("不透明度数字 \(digit)（连按两位为精确百分比）", String(digit))) }
        for (direction, key) in [("左", "\u{f702}"), ("右", "\u{f703}"), ("上", "\u{f700}"), ("下", "\u{f701}")] {
            result += [entry("微移\(direction) 1 像素", key), entry("微移\(direction) 10 像素", key, 8),
                       entry("移动所选像素\(direction) 1 像素", key, 1), entry("移动所选像素\(direction) 10 像素", key, 9)]
        }
        result.append(.init(title: "完成文字编辑", group: "文字编辑", original: ShortcutChord("\r", 1)))
        for (title, key) in [("减小字距", "\u{f702}"), ("增大字距", "\u{f703}"),
                             ("减小行距", "\u{f700}"), ("增大行距", "\u{f701}")] {
            result.append(.init(title: title, group: "文字编辑", original: ShortcutChord(key, 2)))
            result.append(.init(title: title + "（10 倍）", group: "文字编辑", original: ShortcutChord(key, 10)))
        }
        result.append(entry("切换色阶预览", "p", 2))
        return result
    }()
}

@MainActor @Observable
final class ShortcutSettings {
    static let shared = ShortcutSettings()
    private(set) var overrides: [String: ShortcutChord] = [:]
    @ObservationIgnored private let panel = FloatingPanelController(name: "keyboardShortcuts")
    private static let storageKey = "keyboardShortcuts.v1"
    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([String: ShortcutChord].self, from: data),
           Self.problem(in: saved) == nil { overrides = saved }
    }
    func chord(_ definition: ShortcutDefinition) -> ShortcutChord { overrides[definition.id] ?? definition.original }
    func menu(_ key: KeyEquivalent, modifiers: EventModifiers) -> ShortcutChord {
        let bits = (modifiers.contains(.command) ? 1 : 0) | (modifiers.contains(.option) ? 2 : 0)
            | (modifiers.contains(.control) ? 4 : 0) | (modifiers.contains(.shift) ? 8 : 0)
        let original = ShortcutChord(String(key.character), bits)
        guard let definition = ShortcutDefinition.all.first(where: { $0.isMenu && $0.original == original }) else { return original }
        return chord(definition)
    }
    func native(_ key: KeyEquivalent, modifiers: EventModifiers = []) -> ShortcutChord {
        let bits = (modifiers.contains(.command) ? 1 : 0) | (modifiers.contains(.option) ? 2 : 0)
            | (modifiers.contains(.control) ? 4 : 0) | (modifiers.contains(.shift) ? 8 : 0)
        let original = ShortcutChord(String(key.character), bits)
        guard let definition = ShortcutDefinition.all.first(where: { !$0.isMenu && $0.original == original }) else { return original }
        return chord(definition)
    }
    func show() {
        panel.show(title: "键盘快捷键", content: KeyboardShortcutsSheet(settings: self))
    }
    func close() { panel.close() }
    func save(_ values: [String: ShortcutChord]) {
        guard Self.problem(in: values) == nil, let data = try? JSONEncoder().encode(values) else { return }
        overrides = values
        UserDefaults.standard.set(data, forKey: Self.storageKey)
        close()
    }
    static func problem(in values: [String: ShortcutChord]) -> String? {
        var assigned: [ShortcutChord: String] = [:]
        for definition in ShortcutDefinition.all {
            let chord = values[definition.id] ?? definition.original
            guard chord.key.count == 1, (0...15).contains(chord.modifiers) else { return "请选择一个按键，可带修饰键。" }
            if definition.group == "文字编辑", chord.modifiers & 7 == 0 {
                return "文字编辑快捷键需要 Command、Option 或 Control，以免取代正常输入。"
            }
            if [ShortcutChord("q", 1), ShortcutChord(",", 1), ShortcutChord("m", 3)].contains(chord) {
                return "\(chord.label) 是 macOS 保留的快捷键。"
            }
            if let other = assigned[chord] { return "\(chord.label) 同时分配给了\(other)和\(definition.title)。" }
            assigned[chord] = definition.title
        }
        return nil
    }

    /// Translate only at the existing canvas/layer responder boundary. Native text
    /// fields and dialog controls retain their normal typing and navigation behavior.
    func canvasEvent(_ event: NSEvent) -> NSEvent? {
        guard !overrides.isEmpty else { return event }
        let input = ShortcutChord(event)
        if let definition = ShortcutDefinition.all.first(where: { $0.group == "画布与图层" && chord($0) == input }) {
            return definition.original == input ? event : definition.original.event(like: event)
        }
        if ShortcutDefinition.all.contains(where: { $0.group != "文字编辑" && $0.original == input && chord($0) != input }) { return nil }
        // Letter tool shortcuts traditionally also accept Shift. Follow the base
        // assignment unless Shift has its own explicit command (e.g. cycle shape).
        if input.modifiers == 8 {
            let plain = ShortcutChord(input.key)
            if let definition = ShortcutDefinition.all.first(where: { !$0.isMenu && $0.original.modifiers == 0 && chord($0) == plain }) {
                return ShortcutChord(definition.original.key, 8).event(like: event)
            }
            if ShortcutDefinition.all.contains(where: { !$0.isMenu && $0.original == plain && chord($0) != plain }) { return nil }
        }
        return event
    }

    func textEvent(_ event: NSEvent) -> NSEvent? {
        guard !overrides.isEmpty else { return event }
        let definitions = ShortcutDefinition.all.filter { $0.group == "文字编辑" || $0.original == ShortcutChord("\u{1b}") }
        let input = ShortcutChord(event)
        if let definition = definitions.first(where: { chord($0) == input }) {
            return definition.original == input ? event : definition.original.event(like: event)
        }
        if definitions.contains(where: { $0.original == input && chord($0) != input }) { return nil }
        return event
    }
}

extension View {
    func configuredNativeShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = []) -> some View {
        let chord = ShortcutSettings.shared.native(key, modifiers: modifiers)
        guard let first = chord.key.first else { return keyboardShortcut(key, modifiers: modifiers) }
        return keyboardShortcut(KeyEquivalent(first), modifiers: chord.eventModifiers)
    }
    func configuredKeyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
        let chord = ShortcutSettings.shared.menu(key, modifiers: modifiers)
        guard let first = chord.key.first else { return keyboardShortcut(key, modifiers: modifiers) }
        return keyboardShortcut(KeyEquivalent(first), modifiers: chord.eventModifiers)
    }
}

private struct KeyboardShortcutsSheet: View {
    let settings: ShortcutSettings
    @State private var draft: [String: ShortcutChord]
    @State private var search = ""
    @State private var recording: String?
    init(settings: ShortcutSettings) { self.settings = settings; _draft = State(initialValue: settings.overrides) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("点击一个快捷键，然后按下新的组合键。存储后生效。")
                .foregroundStyle(.secondary)
            TextField("搜索快捷键", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(["菜单", "画布与图层", "文字编辑"], id: \.self) { group in
                        Text(group).font(.headline).padding(.top, 8)
                        ForEach(ShortcutDefinition.all.filter { $0.group == group && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }) { definition in
                            HStack {
                                Text(definition.title)
                                Spacer()
                                ShortcutRecorder(chord: draft[definition.id] ?? definition.original,
                                    recording: recording == definition.id,
                                    start: { recording = definition.id },
                                    finish: { chord in
                                        if let chord { draft[definition.id] = chord }
                                        recording = nil
                                    })
                                    .frame(width: 150, height: 26)
                            }
                        }
                    }
                    Divider().padding(.vertical, 8)
                    Text("上下文按键与鼠标手势").font(.headline)
                    Text("文本框保留标准 macOS 编辑按键。对话框共用上面的“应用/取消”快捷键。数字输入框使用上/下方向键，按住 Shift 步进更大。标准 macOS 快捷键包括 ⌘Q 退出、⌃⌘F 全屏。快捷键编辑器本身在未录制时始终使用 Return 存储、Esc 取消。")
                    Text("在绘画工具中按住 Option 可临时切换为吸管。Shift 约束形状/移动方向或添加到选区；Option 从选区减去或从中心绘制。Command 拖动移动所选像素；Command-Option 拖动拷贝所选像素。Option 拖动复制图层/组/效果；Option 点击图层边界切换剪贴蒙版。Command 点击缩略图载入选区。Control 暂时忽略对齐。右键拖动调整画笔大小。修饰键加鼠标的手势不可修改。")
                }.padding(.trailing, 8)
            }.frame(height: 465)
            // Only a conflict takes room here; an empty line left a wide gap above the buttons.
            if let problem = ShortcutSettings.problem(in: draft) {
                Text(problem)
                    .foregroundStyle(.orange).font(.callout).lineLimit(2)
                    .frame(height: 22, alignment: .topLeading)
            }
            Divider()
            HStack {
                Button("恢复默认") { recording = nil; draft = [:] }
                Spacer()
                Button("取消") { settings.close() }.keyboardShortcut(.cancelAction)
                Button("存储") { settings.save(draft) }.keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(recording != nil || ShortcutSettings.problem(in: draft) != nil)
            }
        }.padding(24).frame(width: 660).fixedSize()
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let chord: ShortcutChord
    let recording: Bool
    let start: () -> Void
    let finish: (ShortcutChord?) -> Void
    func makeNSView(context: Context) -> RecorderButton { RecorderButton() }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.start = start; button.finish = finish; button.recording = recording
        button.title = recording ? "请按键…" : chord.label
        button.setAccessibilityLabel(recording ? "请按下快捷键" : chord.label)
        if recording, button.window?.firstResponder !== button { button.window?.makeFirstResponder(button) }
    }
    final class RecorderButton: NSButton {
        var start: (() -> Void)?
        var finish: ((ShortcutChord?) -> Void)?
        var recording = false
        override var acceptsFirstResponder: Bool { true }
        init() {
            super.init(frame: .zero)
            bezelStyle = .rounded; target = self; action = #selector(beginRecording)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        @objc private func beginRecording() { window?.makeFirstResponder(self); recording = true; start?() }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event); return true
        }
        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            let chord = ShortcutChord(event)
            guard chord.key.count == 1 else { NSSound.beep(); return }
            recording = false
            finish?(chord)
            window?.makeFirstResponder(nil)
        }
    }
}
