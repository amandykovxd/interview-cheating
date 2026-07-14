import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var container: DIContainer?
    private var coordinator: AppCoordinator?

    // init без изоляции — вызывается из top-level main.swift до старта раннлупа
    nonisolated override init() { super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let di = DIContainer()
        let coordinator = AppCoordinator(di: di)
        self.container = di
        self.coordinator = coordinator
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        container?.audioPipeline.stop()
    }
}
