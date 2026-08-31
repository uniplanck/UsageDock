import Combine
import Foundation

enum DockEdge: String, CaseIterable, Codable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var label: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        }
    }
}

final class PlacementStore: ObservableObject {
    private static let edgeKey = "UsageDock.edge"

    @Published var edge: DockEdge {
        didSet {
            defaults.set(edge.rawValue, forKey: Self.edgeKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.edgeKey),
           let persisted = DockEdge(rawValue: raw) {
            edge = persisted
        } else {
            edge = .right
        }
    }
}
