//
//  LocationManager.swift
//  Kai
//
//  Manages device location services for location-based features.
//

import Foundation
import CoreLocation

/// Manages location services for the app.
/// Provides current location for weather and other location-based features.
@MainActor
class LocationManager: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = LocationManager()

    // MARK: - Published Properties

    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isAuthorized: Bool = false

    // MARK: - Private Properties

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    // MARK: - Initialization

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer // City-level is enough for weather
        authorizationStatus = locationManager.authorizationStatus
        updateAuthorizationState()
    }

    // MARK: - Public Methods

    /// Request location permissions from the user.
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Get the current location coordinates.
    /// Returns nil if location services are not available or not authorized.
    var coordinates: (latitude: Double, longitude: Double)? {
        guard let location = currentLocation else { return nil }
        return (latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    /// Request a single location update.
    func requestLocation() {
        guard isAuthorized else {
            requestPermission()
            return
        }
        locationManager.requestLocation()
    }

    /// Async method to get current location, requesting if needed.
    func getCurrentLocation() async -> CLLocation? {
        // If we have a recent location (within 5 minutes), use it
        if let location = currentLocation,
           Date().timeIntervalSince(location.timestamp) < 300 {
            return location
        }

        guard isAuthorized else {
            return nil
        }

        // Request a fresh location
        return await withCheckedContinuation { continuation in
            self.locationContinuation = continuation
            self.locationManager.requestLocation()

            // Timeout after 10 seconds
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if self.locationContinuation != nil {
                    self.locationContinuation?.resume(returning: self.currentLocation)
                    self.locationContinuation = nil
                }
            }
        }
    }

    // MARK: - Private Methods

    private func updateAuthorizationState() {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            isAuthorized = true
        default:
            isAuthorized = false
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            self.currentLocation = location

            // Resume any waiting continuation
            if let continuation = self.locationContinuation {
                continuation.resume(returning: location)
                self.locationContinuation = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("[LocationManager] Error: \(error.localizedDescription)")
        #endif

        Task { @MainActor in
            // Resume continuation with current location (may be nil)
            if let continuation = self.locationContinuation {
                continuation.resume(returning: self.currentLocation)
                self.locationContinuation = nil
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            self.updateAuthorizationState()

            // If just authorized, request location
            if self.isAuthorized && self.currentLocation == nil {
                self.locationManager.requestLocation()
            }
        }
    }
}
