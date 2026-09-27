import SwiftUI

@main
struct USBDriveDoctorApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("USB Drive Doctor", systemImage: model.overallStatus.symbolName) {
            MenuBarContentView(model: model)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("USB Drive Doctor", id: "details") {
            ContentView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
