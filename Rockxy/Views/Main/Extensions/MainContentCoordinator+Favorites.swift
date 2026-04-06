import Foundation
import os

// Extends `MainContentCoordinator` with favorites behavior for the main workspace.

// MARK: - MainContentCoordinator + Favorites

/// Coordinator extension for managing user-pinned sidebar favorites.
/// Favorites are persisted to UserDefaults so they survive app restarts.
extension MainContentCoordinator {
    // MARK: - Constants

    private static let favoritesKey = RockxyIdentity.current.defaultsKey("favorites")

    // MARK: - Favorite Management

    func addFavorite(_ item: SidebarItem) {
        guard !favorites.contains(item) else {
            return
        }
        favorites.append(item)
        saveFavorites()
        Self.logger.info("Added favorite: \(String(describing: item))")
    }

    func removeFavorite(_ item: SidebarItem) {
        favorites.removeAll { $0 == item }
        saveFavorites()
        Self.logger.info("Removed favorite: \(String(describing: item))")
    }

    func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: Self.favoritesKey) else {
            return
        }
        do {
            let decoded = try JSONDecoder().decode([SidebarItem].self, from: data)
            favorites = decoded
            Self.logger.info("Loaded \(decoded.count) favorites from UserDefaults")
        } catch {
            Self.logger.error("Failed to load favorites: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func saveFavorites() {
        do {
            let data = try JSONEncoder().encode(favorites)
            UserDefaults.standard.set(data, forKey: Self.favoritesKey)
        } catch {
            Self.logger.error("Failed to save favorites: \(error.localizedDescription)")
        }
    }
}
