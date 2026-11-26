import Foundation

/// The people who share this device, each with their own dashboard. HomeKit doesn't list a home's
/// members to apps, so others are added by name; "Me" (the empty id) is this device's own member.
@Observable
final class Profiles {
    struct Profile: Codable, Identifiable, Hashable {
        var id: String
        var name: String
    }

    let homeID: String
    private(set) var others: [Profile]
    var selected: String {
        didSet { UserDefaults.standard.set(selected, forKey: "profile.\(homeID)") }
    }

    init(homeID: String) {
        self.homeID = homeID
        let data = UserDefaults.standard.data(forKey: "profiles.\(homeID)")
        others = data.flatMap { try? JSONDecoder().decode([Profile].self, from: $0) } ?? []
        selected = UserDefaults.standard.string(forKey: "profile.\(homeID)") ?? ""
        if !selected.isEmpty, !others.contains(where: { $0.id == selected }) { selected = "" }
    }

    var all: [Profile] {
        [Profile(id: "", name: String(localized: "Me"))] + others
    }

    func name(of id: String) -> String {
        all.first { $0.id == id }?.name ?? String(localized: "Me")
    }

    func add(_ name: String) {
        let profile = Profile(id: UUID().uuidString, name: name)
        others.append(profile)
        save()
        selected = profile.id
    }

    func remove(_ id: String) {
        others.removeAll { $0.id == id }
        save()
        selected = ""
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(others), forKey: "profiles.\(homeID)")
    }
}
