import Cocoa
import ApplicationServices

struct PipWindowInfo {
    let bounds: CGRect
    let axWindow: AXUIElement
}

/// Returns rects of all windows above normal level (floating/PiP).
private func floatingWindowRects() -> [CGRect] {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    var rects: [CGRect] = []
    for info in list {
        guard let layer = info[kCGWindowLayer as String] as? Int, layer > 0,
              let bd = info[kCGWindowBounds as String] as? [String: Any] else { continue }
        let x = (bd["X"] as? NSNumber)?.doubleValue ?? 0
        let y = (bd["Y"] as? NSNumber)?.doubleValue ?? 0
        let w = (bd["Width"] as? NSNumber)?.doubleValue ?? 0
        let h = (bd["Height"] as? NSNumber)?.doubleValue ?? 0
        rects.append(CGRect(x: x, y: y, width: w, height: h))
    }
    return rects
}

func debugPipDiscovery() -> String {
    var out = ""
    let chromeApps = NSWorkspace.shared.runningApplications.filter {
        ($0.localizedName ?? "").contains("Chrome")
            || ($0.bundleIdentifier ?? "").contains("chrome")
    }
    out += "AXTrusted: \(AXIsProcessTrusted())\n"
    out += "chromeApps: \(chromeApps.map { "\($0.localizedName ?? "?") pid=\($0.processIdentifier)" })\n"
    let floating = floatingWindowRects()
    out += "floatingRects: \(floating.count)\n"
    for (i, r) in floating.enumerated() { out += "  float[\(i)] \(r)\n" }
    for app in chromeApps {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        guard let windows = windowsRef as? [AXUIElement] else {
            out += "  \(app.localizedName ?? "?"): AX error \(err.rawValue)\n"
            continue
        }
        out += "\(app.localizedName ?? "?"): \(windows.count) windows\n"
        for (i, w) in windows.enumerated() {
            var tRef: CFTypeRef?; _ = AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &tRef)
            var pRef: CFTypeRef?; _ = AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &pRef)
            var sRef: CFTypeRef?; _ = AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &sRef)
            var rRef: CFTypeRef?; _ = AXUIElementCopyAttributeValue(w, kAXRoleAttribute as CFString, &rRef)
            var srRef: CFTypeRef?; _ = AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &srRef)
            var minRef: CFTypeRef?
            let hasMin = AXUIElementCopyAttributeValue(w, kAXMinimizeButtonAttribute as CFString, &minRef) == .success && minRef != nil
            var clRef: CFTypeRef?
            let hasCl = AXUIElementCopyAttributeValue(w, kAXCloseButtonAttribute as CFString, &clRef) == .success && clRef != nil
            var pos = CGPoint.zero; var size = CGSize.zero
            if let pv = pRef { AXValueGetValue(pv as! AXValue, .cgPoint, &pos) }
            if let sv = sRef { AXValueGetValue(sv as! AXValue, .cgSize, &size) }
            let ratio = size.height > 0 ? size.width / size.height : 0
            let title = (tRef as? String) ?? ""
            let matchFloat = floating.contains { r in
                abs(r.origin.x - pos.x) < 3 && abs(r.origin.y - pos.y) < 3
                    && abs(r.width - size.width) < 3 && abs(r.height - size.height) < 3
            }
            out += "  [\(i)] \"\(title.prefix(40))\" \(Int(size.width))x\(Int(size.height)) ratio=\(String(format:"%.2f", ratio)) role=\(rRef as? String ?? "-") sub=\(srRef as? String ?? "-") min=\(hasMin) close=\(hasCl) float=\(matchFloat)\n"
        }
    }
    let pip = findPipWindow()
    out += "findPipWindow: \(pip != nil)\n"
    if let p = pip { out += "  bounds: \(p.bounds)\n" }
    return out
}

func findPipWindow() -> PipWindowInfo? {
    let chromeApps = NSWorkspace.shared.runningApplications.filter {
        ($0.localizedName ?? "").contains("Chrome")
            || ($0.bundleIdentifier ?? "").contains("chrome")
    }

    if chromeApps.isEmpty { return nil }

    let floating = floatingWindowRects()

    for app in chromeApps {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            continue
        }

        for window in windows {
            if let info = extractPipInfo(from: window, floating: floating) {
                return info
            }
        }
    }

    return nil
}

private func extractPipInfo(from window: AXUIElement, floating: [CGRect]) -> PipWindowInfo? {
    var titleRef: CFTypeRef?
    _ = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
    let title = (titleRef as? String) ?? ""

    var posRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
          AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success else {
        return nil
    }

    var pos = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
    AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)

    let isPip = title.localizedCaseInsensitiveContains("picture in picture")
        || title.localizedCaseInsensitiveContains("picture-in-picture")

    // Document PiP: untitled, landscape, AND confirmed floating (above normal window level).
    // The floating check prevents matching Chrome popups like the omnibox dropdown.
    let matchesFloat = floating.contains { r in
        abs(r.origin.x - pos.x) < 3 && abs(r.origin.y - pos.y) < 3
            && abs(r.width - size.width) < 3 && abs(r.height - size.height) < 3
    }

    // Additional AX role/subrole filtering for Document PiP to reject popups,
    // autofill dropdowns, dialogs, etc.
    var roleRef: CFTypeRef?
    _ = AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleRef)
    let role = (roleRef as? String) ?? ""

    var subroleRef: CFTypeRef?
    _ = AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef)
    let subrole = (subroleRef as? String) ?? ""

    let popupSubroles: Set<String> = ["AXDialog", "AXSystemDialog", "AXFloatingWindow"]
    let invalidRoles: Set<String> = ["AXPopover", "AXSheet"]

    let hasValidAXAttributes = (role == "" || role == "AXWindow")
        && !popupSubroles.contains(subrole)
        && !invalidRoles.contains(role)

    // Reject windows with a minimize or close button — real PiP windows have neither.
    // This filters out extension popups, devtools panels, and other Chrome UI.
    var minimizeRef: CFTypeRef?
    let hasMinimize = AXUIElementCopyAttributeValue(window, kAXMinimizeButtonAttribute as CFString, &minimizeRef) == .success
        && minimizeRef != nil

    var closeRef: CFTypeRef?
    let hasClose = AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &closeRef) == .success
        && closeRef != nil

    let isDocPip = (title == "" || title == "about:blank")
        && matchesFloat
        && hasValidAXAttributes
        && !hasMinimize
        && !hasClose
        && size.width >= 200 && size.width <= 800
        && size.height >= 100 && size.height <= 600
        && (size.width / size.height) > 1.4

    // Title-matched PiP: the window title contains "Picture in Picture" or
    // "Picture-in-Picture". Distinguish from the main YouTube tab (whose title
    // also contains this string) by requiring it to be in the floating layer.
    // Chrome PiP windows are always above normal window level (layer > 0).
    let isTitledPip = isPip && matchesFloat

    guard isTitledPip || isDocPip else { return nil }

    let bounds = CGRect(origin: pos, size: size)
    return PipWindowInfo(bounds: bounds, axWindow: window)
}
