//
//  BiometricPromptView.swift
//  Kai
//
//  Biometric authentication prompt using AuthenticationManager.
//

import SwiftUI

struct BiometricPromptView: View {
    // MARK: - State

    @State private var isAnimating: Bool = false

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var authManager = AuthenticationManager.shared

    // MARK: - Callbacks

    var onBiometricSuccess: (() -> Void)?
    var onUsePassword: (() -> Void)?

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer()

                // Main Content
                VStack(spacing: 32) {
                    // Biometric Icon
                    biometricIcon
                        .frame(height: geometry.size.height * 0.25)

                    // Title and Subtitle
                    titleSection

                    // Error Message
                    if let error = authManager.error {
                        errorSection(error.localizedDescription)
                    }
                }

                Spacer()

                // Buttons
                buttonSection
                    .padding(.bottom, 48)
            }
            .padding(.horizontal, 24)
        }
        .background(backgroundGradient)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                isAnimating = true
            }
            // Auto-trigger biometric authentication on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                authenticate()
            }
        }
    }

    // MARK: - Biometric Icon

    private var biometricIcon: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .frame(width: 160, height: 160)
                .scaleEffect(isAnimating ? 1 : 0.8)
                .opacity(isAnimating ? 1 : 0)

            // Inner glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.blue.opacity(0.15), Color.clear],
                        center: .center,
                        startRadius: 40,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)
                .scaleEffect(isAnimating ? 1 : 0.9)

            // Icon background
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 100, height: 100)
                .shadow(color: Color.blue.opacity(0.4), radius: 20, x: 0, y: 10)
                .scaleEffect(isAnimating ? 1 : 0.5)

            // Biometric Icon
            Image(systemName: biometricIconName)
                .font(.system(size: 44, weight: .medium))
                .foregroundColor(.white)
                .opacity(isAnimating ? 1 : 0)
                .symbolEffect(.pulse, options: .repeating, isActive: authManager.isLoading)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: isAnimating)
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(spacing: 12) {
            Text("Unlock Kai")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .opacity(isAnimating ? 1 : 0)
                .offset(y: isAnimating ? 0 : 20)

            Text(biometricSubtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .opacity(isAnimating ? 1 : 0)
                .offset(y: isAnimating ? 0 : 10)
        }
        .animation(.easeOut(duration: 0.5).delay(0.2), value: isAnimating)
    }

    // MARK: - Error Section

    private func errorSection(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.orange)

            Text(error)
                .font(.subheadline)
                .foregroundColor(.orange)
                .lineLimit(2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .transition(.opacity.combined(with: .scale))
    }

    // MARK: - Button Section

    private var buttonSection: some View {
        VStack(spacing: 16) {
            // Primary Biometric Button
            Button {
                authenticate()
            } label: {
                HStack(spacing: 12) {
                    if authManager.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: biometricIconName)
                            .font(.system(size: 18, weight: .medium))
                    }

                    Text(biometricButtonTitle)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.blue.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(14)
                .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
            }
            .disabled(authManager.isLoading)
            .opacity(isAnimating ? 1 : 0)
            .offset(y: isAnimating ? 0 : 20)
            .animation(.easeOut(duration: 0.5).delay(0.4), value: isAnimating)

            // Secondary Password Button
            Button {
                onUsePassword?()
            } label: {
                Text("Sign in with password")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }
            .disabled(authManager.isLoading)
            .opacity(isAnimating ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.5), value: isAnimating)
        }
    }

    // MARK: - Computed Properties

    private var biometricIconName: String {
        switch authManager.biometricType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        case .none:
            return "lock.fill"
        }
    }

    private var biometricSubtitle: String {
        switch authManager.biometricType {
        case .faceID:
            return "Use Face ID to quickly access your personal assistant"
        case .touchID:
            return "Use Touch ID to quickly access your personal assistant"
        case .opticID:
            return "Use Optic ID to quickly access your personal assistant"
        case .none:
            return "Authenticate to access your personal assistant"
        }
    }

    private var biometricButtonTitle: String {
        switch authManager.biometricType {
        case .faceID:
            return "Use Face ID"
        case .touchID:
            return "Use Touch ID"
        case .opticID:
            return "Use Optic ID"
        case .none:
            return "Authenticate"
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                colorScheme == .dark ? Color(.systemBackground) : Color(.systemGray6).opacity(0.5),
                colorScheme == .dark ? Color(.systemGray6).opacity(0.3) : Color(.systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Methods

    private func authenticate() {
        guard !authManager.isLoading else { return }

        Task {
            do {
                try await authManager.authenticateWithBiometric()
                onBiometricSuccess?()
            } catch let error as AuthenticationError {
                // Handle specific biometric errors
                switch error {
                case .biometricCancelled:
                    // User cancelled - don't show error
                    break
                case .biometricFallback:
                    // User wants to use password
                    onUsePassword?()
                case .noStoredCredentials:
                    // No credentials - go to login
                    onUsePassword?()
                default:
                    // Error is displayed by authManager
                    break
                }
            } catch {
                // Generic error - already handled by authManager
            }
        }
    }
}

// MARK: - Preview

#Preview("Biometric Prompt") {
    BiometricPromptView(
        onBiometricSuccess: {
            print("Biometric success")
        },
        onUsePassword: {
            print("Use password")
        }
    )
}
