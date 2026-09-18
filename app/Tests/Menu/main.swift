import AppKit

let application = NSApplication.shared
let suite = "PGNClipboard.MenuTests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
var checks = 0
func expect(_ value: @autoclosure () -> Bool, _ label: String) {
    checks += 1
    guard value() else { fatalError(label) }
    print("PASS: \(label)")
}
var delegate = AppDelegate(defaults: defaults)
let menu = NSMenu()
menu.autoenablesItems = false
func items() -> (NSMenuItem, NSMenuItem) {
    delegate.menuWillOpen(menu)
    menu.update()
    return (menu.item(withTitle: "Strip headers")!, menu.item(withTitle: "Auto headers")!)
}
func click(_ item: NSMenuItem) { _ = (item.target as? NSObject)?.perform(item.action) }
var (strip, auto) = items()
expect(strip.state == .off && auto.state == .off, "Menu defaults both options off")
expect(strip.isEnabled && !auto.isEnabled, "Menu disables dependent option")
click(auto)
expect(!defaults.bool(forKey: "autoHeaders"), "Disabled action guarded even if invoked directly")
click(strip)
(strip, auto) = items()
expect(strip.state == .on && auto.isEnabled, "Strip menu action enables Auto headers")
click(auto)
(strip, auto) = items()
expect(auto.state == .on && defaults.bool(forKey: "autoHeaders"), "Auto menu action persists preference")
click(strip)
(strip, auto) = items()
expect(strip.state == .off && !auto.isEnabled && auto.state == .on, "Disabling strip retains inactive auto preference")
delegate = AppDelegate(defaults: defaults)
(strip, auto) = items()
expect(strip.state == .off && auto.state == .on && !auto.isEnabled, "Relaunch restores gated preferences")
click(strip)
(strip, auto) = items()
expect(strip.state == .on && auto.state == .on && auto.isEnabled, "Re-enabling strip restores auto setting")
click(auto)
(strip, auto) = items()
expect(auto.state == .off && auto.isEnabled, "Auto can be turned off independently")
expect(defaults.bool(forKey: "stripHeaders") && !defaults.bool(forKey: "autoHeaders"), "Both preferences stored independently")
print("\(checks) menu checks passed in an isolated preferences suite.")
