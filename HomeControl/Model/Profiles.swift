import Foundation

/// Whose dashboard is showing. Everyone in the home's iCloud share has their own, keyed by their iCloud user;
/// "Me" comes first.
@Observable
final class Profiles {
    struct Profile: Identifiable, Hashable {
        var id: String
        var name: String
    }

    let homeID: String
    let all: [Profile]
    var selected: String {
        didSet { UserDefaults.standard.set(selected, forKey: "profile.\(homeID)") }
    }

    init(homeID: String, people: [Profile] = []) {
        self.homeID = homeID
        all = people.isEmpty ? [Profile(id: "", name: String(localized: "Me"))] : people
        let saved = UserDefaults.standard.string(forKey: "profile.\(homeID)")
        selected = all.first { $0.id == saved }?.id ?? all[0].id
    }

    func name(of id: String) -> String {
        all.first { $0.id == id }?.name ?? String(localized: "Me")
    }
}
