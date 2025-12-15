import AppKit

@MainActor
final class ProgressPanel {
    private let panel: NSPanel

    init(title: String, message: String) {
        let contentRect = NSRect(x: 0, y: 0, width: 360, height: 120)
        self.panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        self.panel.isFloatingPanel = true
        self.panel.level = .floating
        self.panel.hidesOnDeactivate = false
        self.panel.title = title

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 10
        container.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)

        let label = NSTextField(labelWithString: message)
        label.font = NSFont.systemFont(ofSize: 13)
        label.lineBreakMode = .byWordWrapping

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.startAnimation(nil)

        container.addArrangedSubview(label)
        container.addArrangedSubview(spinner)

        let contentView = NSView(frame: contentRect)
        contentView.addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            container.topAnchor.constraint(equalTo: contentView.topAnchor),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        self.panel.contentView = contentView
        self.panel.center()
    }

    func show() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel.orderOut(nil)
    }
}
