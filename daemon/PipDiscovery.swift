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

func findPipWindow() -> PipWindowInfo? {
    let chromeApps = NSWorkspace.shared.runningApplications.filter {
        ($0.localizedName ?? "").contains("Chrome")
            || ($0.bundleIdentifier ?? "").contains("chrome")
    }

    let floating = floatingWindowRects()

    for app in chromeApps {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { continue }

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

    let titleLower = title.lowercased()
    let isPip = titleLower.contains("picture in picture")
        || titleLower.contains("picture-in-picture")

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

    let isDocPip = (title == "" || title == "about:blank")
        && matchesFloat
        && hasValidAXAttributes
        && size.width >= 200 && size.width <= 800
        && size.height >= 100 && size.height <= 600
        && (size.width / size.height) > 1.4

    guard isPip || isDocPip else { return nil }

    let bounds = CGRect(origin: pos, size: size)
    return PipWindowInfo(bounds: bounds, axWindow: window)
}
