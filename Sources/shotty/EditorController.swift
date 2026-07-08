import AppKit

// MARK: - Editor window (one per capture)

/// Top-left origin so scroll-view content aligns to the top, not the bottom.
final class FlippedView: NSView { override var isFlipped: Bool { true } }

final class EditorController: NSObject, NSWindowDelegate {
    let canvas: CanvasView
    let window: NSWindow
    var onClose: ((EditorController) -> Void)?
    private var toolButtons: [NSButton] = []
    private var colorButtons: [(button: NSButton, color: NSColor)] = []
    private var bgChoices: [(button: NSButton, bg: Background)] = []
    private var widthSlider: NSSlider!
    private var undoBtn: NSButton!
    private var redoBtn: NSButton!
    private var intensitySlider: NSSlider!
    private var intensityContainer: NSStackView!
    private weak var intensityTarget: Annotation?
    private var paddingSlider: NSSlider!
    private var cornerSlider: NSSlider!
    private var shadowSlider: NSSlider!
    private var ratioPopup: NSPopUpButton!
    private let ratios: [(String, CGFloat?)] = [
        ("Auto", nil), ("16:9", 16.0 / 9), ("4:3", 4.0 / 3), ("1:1", 1), ("3:2", 3.0 / 2),
    ]

    init(image: NSImage) {
        canvas = CanvasView(image: image)

        let w = max(960.0, min(image.size.width + 260, 1500))
        let h = max(640.0, min(image.size.height + 120, 950))
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: w, height: h),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        super.init()

        let toolbar = makeToolbar()
        let sidebar = makeSidebar()
        canvas.onToolChanged = { [weak self] t in
            for b in self?.toolButtons ?? [] { b.state = (b.identifier?.rawValue == t.rawValue) ? .on : .off }
        }
        canvas.onHistoryChanged = { [weak self] in
            self?.undoBtn.isEnabled = self?.canvas.canUndo ?? false
            self?.redoBtn.isEnabled = self?.canvas.canRedo ?? false
        }
        canvas.onStateRestored = { [weak self] in self?.syncControls() }
        canvas.onSelectionChanged = { [weak self] a in
            guard let self else { return }
            self.intensityTarget = nil
            self.intensityContainer.isHidden = true
            self.widthSlider.isHidden = false
            // The size slider retargets to the selection (or sets the default when nothing is selected).
            switch a?.tool {
            case .blur, .pixelate:
                self.intensityTarget = a
                self.intensitySlider.doubleValue = Double(a!.intensity)
                self.intensityContainer.isHidden = false
                self.widthSlider.isHidden = true
            case .text:
                self.widthSlider.minValue = 12; self.widthSlider.maxValue = 200
                self.widthSlider.doubleValue = Double(a!.fontSize)
                self.highlightColor(a!.color)
            case .arrow, .rect:
                self.widthSlider.minValue = 1; self.widthSlider.maxValue = 40
                self.widthSlider.doubleValue = Double(a!.lineWidth)
                self.highlightColor(a!.color)
            default:
                self.widthSlider.minValue = 1; self.widthSlider.maxValue = 40
                self.widthSlider.doubleValue = Double(self.canvas.lineWidth)
                self.highlightColor(self.canvas.color)
            }
        }
        let root = NSView()
        for v in [toolbar, sidebar, canvas] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 46),
            sidebar.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 240),
            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        // Hairline separators so the panels read as distinct.
        let hDiv = hairline(), vDiv = hairline()
        for v in [hDiv, vDiv] { root.addSubview(v) }
        NSLayoutConstraint.activate([
            hDiv.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            hDiv.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            hDiv.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            hDiv.heightAnchor.constraint(equalToConstant: 1),
            vDiv.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            vDiv.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            vDiv.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            vDiv.widthAnchor.constraint(equalToConstant: 1),
        ])

        window.appearance = NSAppearance(named: .darkAqua)
        window.title = "Shotty"
        window.isReleasedWhenClosed = false // ARC/this controller owns it; avoid a double-free on close
        window.contentView = root
        window.contentMinSize = NSSize(width: 760, height: 560)
        window.delegate = self
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless() // surface above other apps even though we're an accessory app
    }

    func windowWillClose(_ note: Notification) {
        // Defer teardown so we don't deallocate self while AppKit is still inside the close.
        DispatchQueue.main.async { [self] in onClose?(self) }
    }

    private func hairline() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(white: 1, alpha: 0.12).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    private func makeToolbar() -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1).cgColor

        let tools = NSStackView()
        tools.spacing = 6
        for t in Tool.allCases {
            let b = NSButton(title: t.rawValue.capitalized, target: self, action: #selector(pickTool(_:)))
            b.setButtonType(.pushOnPushOff)
            b.bezelStyle = .rounded
            b.identifier = NSUserInterfaceItemIdentifier(t.rawValue)
            b.state = (t == canvas.tool) ? .on : .off
            toolButtons.append(b)
            tools.addArrangedSubview(b)
        }

        // Inline colour palette (avoids the shared NSColorPanel, which floats onto other screens).
        let colorRow = NSStackView()
        colorRow.spacing = 4
        let annotationColors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen,
                                           .systemBlue, .systemPurple, .white, .black]
        for c in annotationColors {
            let b = NSButton(title: "", target: self, action: #selector(pickAnnotationColor(_:)))
            b.isBordered = false
            b.focusRingType = .none
            b.image = Backgrounds.solidThumbnail(c, size: NSSize(width: 18, height: 18))
            b.wantsLayer = true
            b.layer?.cornerRadius = 4
            b.layer?.borderColor = NSColor.white.cgColor
            b.layer?.borderWidth = (c == canvas.color) ? 2 : 0
            b.widthAnchor.constraint(equalToConstant: 18).isActive = true
            b.heightAnchor.constraint(equalToConstant: 18).isActive = true
            colorButtons.append((b, c))
            colorRow.addArrangedSubview(b)
        }

        widthSlider = NSSlider(value: Double(canvas.lineWidth), minValue: 1, maxValue: 40,
                               target: self, action: #selector(pickWidth(_:)))
        widthSlider.widthAnchor.constraint(equalToConstant: 90).isActive = true

        // Intensity control — shown only when a blur/pixelate annotation is selected.
        let intensityLabel = NSTextField(labelWithString: "Intensity")
        intensityLabel.font = .systemFont(ofSize: 11)
        intensityLabel.textColor = .secondaryLabelColor
        intensitySlider = NSSlider(value: 1, minValue: 0.3, maxValue: 3,
                                   target: self, action: #selector(changeIntensity(_:)))
        intensitySlider.widthAnchor.constraint(equalToConstant: 90).isActive = true
        intensityContainer = NSStackView(views: [intensityLabel, intensitySlider])
        intensityContainer.spacing = 6
        intensityContainer.isHidden = true

        undoBtn = NSButton(image: NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Undo")!,
                           target: self, action: #selector(undoAction))
        undoBtn.bezelStyle = .rounded; undoBtn.isEnabled = false
        redoBtn = NSButton(image: NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: "Redo")!,
                           target: self, action: #selector(redoAction))
        redoBtn.bezelStyle = .rounded; redoBtn.isEnabled = false

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [
            tools, undoBtn, redoBtn, colorRow, widthSlider, intensityContainer, spacer,
            NSButton(title: "Duplicate", target: self, action: #selector(duplicateItem)),
            NSButton(title: "Copy", target: self, action: #selector(copyImage)),
            NSButton(title: "Save…", target: self, action: #selector(saveImage)),
        ])
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    private func sectionLabel(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func separator() -> NSBox {
        let b = NSBox()
        b.boxType = .separator
        b.widthAnchor.constraint(equalToConstant: 208).isActive = true
        return b
    }

    private func grid(_ views: [NSView], columns: Int, spacing: CGFloat) -> NSGridView {
        var rows: [[NSView]] = []
        var i = 0
        while i < views.count {
            rows.append(Array(views[i..<min(i + columns, views.count)]))
            i += columns
        }
        let g = NSGridView(views: rows)
        g.rowSpacing = spacing; g.columnSpacing = spacing
        return g
    }

    private func swatch(image: NSImage, bg: Background, size: NSSize) -> NSButton {
        let b = NSButton(title: "", target: self, action: #selector(selectBg(_:)))
        b.isBordered = false
        b.focusRingType = .none // we draw our own selection border; the ring skews grid spacing
        b.image = image
        b.imageScaling = .scaleAxesIndependently
        b.wantsLayer = true
        b.layer?.cornerRadius = 6
        b.layer?.borderColor = NSColor.controlAccentColor.cgColor
        b.layer?.borderWidth = canvas.background.sameAs(bg) ? 3 : 0
        b.widthAnchor.constraint(equalToConstant: size.width).isActive = true
        b.heightAnchor.constraint(equalToConstant: size.height).isActive = true
        bgChoices.append((b, bg))
        return b
    }

    private func slider(_ value: CGFloat, _ lo: Double, _ hi: Double, _ action: Selector) -> NSSlider {
        let s = NSSlider(value: Double(value), minValue: lo, maxValue: hi, target: self, action: action)
        s.widthAnchor.constraint(equalToConstant: 208).isActive = true
        return s
    }

    private func makeSidebar() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Background: None
        let none = NSButton(title: "No Background", target: self, action: #selector(selectBg(_:)))
        none.toolTip = "Transparent background — exports as a PNG with alpha"
        none.bezelStyle = .rounded
        none.focusRingType = .none
        none.wantsLayer = true
        none.layer?.cornerRadius = 6
        none.layer?.borderColor = NSColor.controlAccentColor.cgColor
        none.layer?.borderWidth = canvas.background.sameAs(.none) ? 3 : 0
        none.widthAnchor.constraint(equalToConstant: 208).isActive = true
        bgChoices.append((none, .none))
        stack.addArrangedSubview(none)

        let panelW: CGFloat = 208, sp: CGFloat = 6 // swatch grids fill the panel width

        // Background: Gradients (5-column grid, full width)
        stack.addArrangedSubview(sectionLabel("Gradients"))
        let gW = (panelW - sp * 4) / 5
        let gSize = NSSize(width: gW, height: gW * 0.72)
        stack.addArrangedSubview(grid(Backgrounds.pairs.indices.map { i in
            swatch(image: Backgrounds.gradientThumbnail(i, size: gSize), bg: .gradient(i), size: gSize)
        }, columns: 5, spacing: sp))

        // Background: Plain colours (6-column grid, full width)
        stack.addArrangedSubview(sectionLabel("Plain colour"))
        let pW = (panelW - sp * 5) / 6
        let pSize = NSSize(width: pW, height: pW * 0.78)
        stack.addArrangedSubview(grid(Backgrounds.plainColors.map { c in
            swatch(image: Backgrounds.solidThumbnail(c, size: pSize), bg: .solid(c), size: pSize)
        }, columns: 6, spacing: sp))

        stack.addArrangedSubview(separator())

        // Padding / Corners / Shadow
        paddingSlider = slider(canvas.paddingFraction, 0, 0.2, #selector(changePadding(_:)))
        cornerSlider = slider(canvas.cornerFraction, 0, 0.12, #selector(changeCorners(_:)))
        shadowSlider = slider(canvas.shadowStrength, 0, 1, #selector(changeShadow(_:)))
        stack.addArrangedSubview(sectionLabel("Padding")); stack.addArrangedSubview(paddingSlider)
        stack.addArrangedSubview(sectionLabel("Corners")); stack.addArrangedSubview(cornerSlider)
        stack.addArrangedSubview(sectionLabel("Shadow")); stack.addArrangedSubview(shadowSlider)

        stack.addArrangedSubview(separator())

        // Ratio
        stack.addArrangedSubview(sectionLabel("Ratio"))
        ratioPopup = NSPopUpButton()
        ratioPopup.addItems(withTitles: ratios.map { $0.0 })
        ratioPopup.target = self; ratioPopup.action = #selector(pickRatio(_:))
        stack.addArrangedSubview(ratioPopup)

        // Wrap in a scroll view so the tall panel never clips on a short window.
        // FlippedView so short content top-aligns instead of sinking to the bottom.
        let content = FlippedView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
        ])

        let scroll = NSScrollView()
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)
        scroll.hasVerticalScroller = true
        scroll.documentView = content
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        ])
        return scroll
    }

    @objc private func pickTool(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let t = Tool(rawValue: id) else { return }
        canvas.tool = t
        for b in toolButtons { b.state = (b === sender) ? .on : .off }
    }
    @objc private func pickAnnotationColor(_ sender: NSButton) {
        guard let match = colorButtons.first(where: { $0.button === sender }) else { return }
        canvas.color = match.color
        highlightColor(match.color)
        if let sel = canvas.selectedAnnotation, [.arrow, .rect, .text].contains(sel.tool) {
            canvas.recordChange { sel.color = match.color }
            canvas.needsDisplay = true
        }
    }
    private func highlightColor(_ c: NSColor) {
        for (b, col) in colorButtons { b.layer?.borderWidth = (col == c) ? 2 : 0 }
    }
    private func syncControls() {
        paddingSlider.doubleValue = Double(canvas.paddingFraction)
        cornerSlider.doubleValue = Double(canvas.cornerFraction)
        shadowSlider.doubleValue = Double(canvas.shadowStrength)
        if let idx = ratios.firstIndex(where: { $0.1 == canvas.ratio }) { ratioPopup.selectItem(at: idx) }
        for (b, bg) in bgChoices { b.layer?.borderWidth = canvas.background.sameAs(bg) ? 3 : 0 }
    }
    @objc private func pickWidth(_ s: NSSlider) {
        if let sel = canvas.selectedAnnotation {
            canvas.beginChange()
            switch sel.tool {
            case .text: sel.fontSize = CGFloat(s.doubleValue)
            case .arrow, .rect: sel.lineWidth = CGFloat(s.doubleValue)
            default: break
            }
            canvas.needsDisplay = true
            if NSApp.currentEvent?.type == .leftMouseUp { canvas.commitChange() }
        } else {
            canvas.lineWidth = CGFloat(s.doubleValue) // default for new annotations; not undoable
        }
    }
    @objc private func changeIntensity(_ s: NSSlider) {
        canvas.beginChange()
        intensityTarget?.intensity = CGFloat(s.doubleValue)
        canvas.needsDisplay = true
        if NSApp.currentEvent?.type == .leftMouseUp { canvas.commitChange() }
    }
    @objc private func undoAction() { canvas.undo() }
    @objc private func redoAction() { canvas.redo() }
    @objc private func selectBg(_ sender: NSButton) {
        guard let match = bgChoices.first(where: { $0.button === sender }) else { return }
        canvas.recordChange { self.canvas.background = match.bg }
        for (b, _) in bgChoices { b.layer?.borderWidth = (b === sender) ? 3 : 0 }
        canvas.needsDisplay = true
    }
    @objc private func changePadding(_ s: NSSlider) {
        canvas.beginChange(); canvas.paddingFraction = CGFloat(s.doubleValue); canvas.needsDisplay = true
        if NSApp.currentEvent?.type == .leftMouseUp { canvas.commitChange() }
    }
    @objc private func changeCorners(_ s: NSSlider) {
        canvas.beginChange(); canvas.cornerFraction = CGFloat(s.doubleValue); canvas.needsDisplay = true
        if NSApp.currentEvent?.type == .leftMouseUp { canvas.commitChange() }
    }
    @objc private func changeShadow(_ s: NSSlider) {
        canvas.beginChange(); canvas.shadowStrength = CGFloat(s.doubleValue); canvas.needsDisplay = true
        if NSApp.currentEvent?.type == .leftMouseUp { canvas.commitChange() }
    }
    @objc private func pickRatio(_ p: NSPopUpButton) {
        let r = ratios[p.indexOfSelectedItem].1
        canvas.recordChange { self.canvas.ratio = r }
        canvas.needsDisplay = true
    }

    @objc private func duplicateItem() { canvas.duplicateSelected() }

    @objc private func copyImage() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([canvas.renderedImage()])
    }

    @objc private func saveImage() {
        guard let png = canvas.renderedPNG() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        panel.nameFieldStringValue = "Shotty \(df.string(from: Date())).png"
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            try? png.write(to: url)
        }
    }
}
