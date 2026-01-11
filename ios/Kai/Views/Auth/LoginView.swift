//
//  LoginView.swift
//  Kai
//
//  Authentication login view using AuthenticationManager.
//

import SwiftUI

struct LoginView: View {
    // MARK: - State

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var showPassword: Bool = false
    @State private var isAnimating: Bool = false

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var authManager = AuthenticationManager.shared

    // MARK: - Callbacks

    var onLoginSuccess: (() -> Void)?
    var onShowRegister: (() -> Void)?

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: geometry.size.height * 0.08)

                    // Logo and Title
                    headerSection

                    Spacer()
                        .frame(height: 40)

                    // Login Form
                    formSection

                    Spacer()
                        .frame(height: 20)

                    // Error Message
                    if let error = authManager.error {
                        errorSection(error.localizedDescription)
                    }

                    Spacer()
                        .frame(height: 28)

                    // Sign In Button
                    signInButton

                    Spacer()
                        .frame(minHeight: 40)

                    // Footer
                    footerSection
                }
                .padding(.horizontal, 24)
                .frame(minHeight: geometry.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(backgroundGradient)
        .ignoresSafeArea(.keyboard)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                isAnimating = true
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            // App Icon
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.blue.opacity(0.2), Color.clear],
                            center: .center,
                            startRadius: 30,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                    .scaleEffect(isAnimating ? 1 : 0.8)
                    .opacity(isAnimating ? 1 : 0)

                // Main icon
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.purple.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: Color.blue.opacity(0.4), radius: 20, x: 0, y: 10)
                    .scaleEffect(isAnimating ? 1 : 0.5)

                Text("K")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(isAnimating ? 1 : 0)
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: isAnimating)

            VStack(spacing: 8) {
                Text("Welcome to Kai")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .opacity(isAnimating ? 1 : 0)
                    .offset(y: isAnimating ? 0 : 20)

                Text("Your personal AI assistant")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .opacity(isAnimating ? 1 : 0)
                    .offset(y: isAnimating ? 0 : 10)
            }
            .animation(.easeOut(duration: 0.5).delay(0.2), value: isAnimating)
        }
    }

    // MARK: - Form Section

    private var formSection: some View {
        VStack(spacing: 16) {
            // Email Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .foregroundColor(.secondary)
                        .frame(width: 20)

                    TextField("Enter your email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(fieldBackground)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
            .opacity(isAnimating ? 1 : 0)
            .offset(y: isAnimating ? 0 : 20)
            .animation(.easeOut(duration: 0.5).delay(0.3), value: isAnimating)

            // Password Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.secondary)
                        .frame(width: 20)

                    if showPassword {
                        TextField("Enter your password", text: $password)
                            .textContentType(.password)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("Enter your password", text: $password)
                            .textContentType(.password)
                    }

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(fieldBackground)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
            .opacity(isAnimating ? 1 : 0)
            .offset(y: isAnimating ? 0 : 20)
            .animation(.easeOut(duration: 0.5).delay(0.4), value: isAnimating)
        }
    }

    // MARK: - Error Section

    private func errorSection(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)

            Text(error)
                .font(.subheadline)
                .foregroundColor(.red)
                .lineLimit(2)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Sign In Button

    private var signInButton: some View {
        Button {
            Task {
                await signIn()
            }
        } label: {
            HStack(spacing: 8) {
                if authManager.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.9)
                } else {
                    Text("Sign In")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: isFormValid ? [Color.blue, Color.blue.opacity(0.85)] : [Color.gray.opacity(0.4)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(14)
            .shadow(
                color: isFormValid ? Color.blue.opacity(0.3) : Color.clear,
                radius: 10,
                x: 0,
                y: 5
            )
        }
        .disabled(!isFormValid || authManager.isLoading)
        .opacity(isAnimating ? 1 : 0)
        .offset(y: isAnimating ? 0 : 20)
        .animation(.easeOut(duration: 0.5).delay(0.5), value: isAnimating)
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        VStack(spacing: 16) {
            HStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 1)

                Text("or")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 1)
            }

            Button {
                onShowRegister?()
            } label: {
                Text("Don't have an account? ")
                    .foregroundColor(.secondary) +
                Text("Sign Up")
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
        }
        .padding(.bottom, 32)
        .opacity(isAnimating ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(0.6), value: isAnimating)
    }

    // MARK: - Computed Properties

    private var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty && email.contains("@")
    }

    private var fieldBackground: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground)
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

    // MARK: - Actions

    private func signIn() async {
        guard isFormValid else { return }

        do {
            try await authManager.login(email: email, password: password)
            onLoginSuccess?()
        } catch {
            // Error is already handled by AuthenticationManager
        }
    }
}

// MARK: - Preview

#Preview {
    LoginView(
        onLoginSuccess: {
            print("Login success")
        },
        onShowRegister: {
            print("Show register")
        }
    )
}
