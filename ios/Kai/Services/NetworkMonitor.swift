//
//  NetworkMonitor.swift
//  Kai
//
//  Network connectivity monitoring using NWPathMonitor.
//

import Foundation
import Network
import Combine

/// Monitors network connectivity status using NWPathMonitor.
/// Provides real-time connectivity updates through Combine publishers.
final class NetworkMonitor: ObservableObject {

    // MARK: - Singleton

    static let shared = NetworkMonitor()

    // MARK: - Published Properties

    /// Whether the device currently has network connectivity.
    @Published private(set) var isConnected: Bool = true

    /// Whether the current connection is expensive (cellular, hotspot).
    @Published private(set) var isExpensive: Bool = false

    /// Whether the current connection is constrained (Low Data Mode).
    @Published private(set) var isConstrained: Bool = false

    /// The current network interface type.
    @Published private(set) var connectionType: ConnectionType = .unknown

    // MARK: - Types

    /// Represents the type of network connection.
    enum ConnectionType: String {
        case wifi = "WiFi"
        case cellular = "Cellular"
        case wiredEthernet = "Ethernet"
        case loopback = "Loopback"
        case other = "Other"
        case unknown = "Unknown"
    }

    // MARK: - Private Properties

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        monitor = NWPathMonitor()
        queue = DispatchQueue(label: "com.kai.networkmonitor", qos: .utility)
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Public Methods

    /// Starts monitoring network connectivity.
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.updateConnectionStatus(path: path)
            }
        }
        monitor.start(queue: queue)
    }

    /// Stops monitoring network connectivity.
    func stopMonitoring() {
        monitor.cancel()
    }

    /// Checks if the network is available and throws if not.
    /// - Throws: `NetworkError.noConnection` if not connected.
    func requireConnection() throws {
        guard isConnected else {
            throw NetworkError.noConnection
        }
    }

    // MARK: - Private Methods

    private func updateConnectionStatus(path: NWPath) {
        isConnected = path.status == .satisfied
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained
        connectionType = determineConnectionType(path: path)

        #if DEBUG
        print("[NetworkMonitor] Status: \(isConnected ? "Connected" : "Disconnected"), Type: \(connectionType.rawValue)")
        #endif
    }

    private func determineConnectionType(path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .wiredEthernet
        } else if path.usesInterfaceType(.loopback) {
            return .loopback
        } else if path.usesInterfaceType(.other) {
            return .other
        } else {
            return .unknown
        }
    }
}

// MARK: - Network Error

/// Errors related to network connectivity.
enum NetworkError: LocalizedError {
    case noConnection
    case timeout
    case serverUnreachable

    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "No internet connection. Please check your network settings."
        case .timeout:
            return "The request timed out. Please try again."
        case .serverUnreachable:
            return "Unable to reach the server. Please try again later."
        }
    }
}
