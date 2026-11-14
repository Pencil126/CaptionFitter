import AppKit
import SwiftUI

/// Keys that move the playhead.
enum PlaybackKey {
    /// ⇧← / ⇧→: jump by the number of seconds chosen in Settings.
    case skipBack, skipForward
    /// ← / →: one frame.
    case frameBack, frameForward
}

/// Listens for playback keys in the window it is placed in.
///
/// These are plain arrow keys, which text fields need for moving the cursor and selecting,
/// so they are handled here rather than as menu shortcuts: while text is being edited the
/// keys are left alone.
struct PlaybackKeys: NSViewRepresentable {
    /// Returns whether the key was used.
    let handler: (PlaybackKey) -> Bool

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.handler = handler
        return view
    }

    func updateNSView(_ view: KeyView, context: Context) {
        view.handler = handler
    }

    final class KeyView: NSView {
        var handler: ((PlaybackKey) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let key = self.key(for: event), self.handler?(key) == true else { return event }
                return nil
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        private func key(for event: NSEvent) -> PlaybackKey? {
            // Only this window, and not while a sheet covers it or text is being edited.
            guard let window, event.window === window, window.attachedSheet == nil,
                  !(window.firstResponder is NSText) else { return nil }
            let modifiers = event.modifierFlags.intersection([.shift, .command, .option, .control])
            switch (event.keyCode, modifiers) {
            case (123, .shift): return .skipBack
            case (124, .shift): return .skipForward
            case (123, []): return .frameBack
            case (124, []): return .frameForward
            default: return nil
            }
        }
    }
}
