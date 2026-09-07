import AppKit
@main enum W { static func main() {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                          kCGNullWindowID) as? [[String: Any]] ?? []
    for info in list {
        guard (info[kCGWindowOwnerName as String] as? String) == "Ampel" else { continue }
        let id = info[kCGWindowNumber as String] as? Int ?? 0
        let name = info[kCGWindowName as String] as? String ?? ""
        let b = info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
        let layer = info[kCGWindowLayer as String] as? Int ?? 0
        print("\(id)\t\(Int(b["X"] ?? 0)),\(Int(b["Y"] ?? 0)) \(Int(b["Width"] ?? 0))x\(Int(b["Height"] ?? 0))\tlayer=\(layer)\t\(name)")
    }
}}
