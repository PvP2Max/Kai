//
//  LoadingView.swift
//  Kai
//
//  Created for Kai iOS App
//

import SwiftUI

struct LoadingView: View {
    // MARK: - Properties

    var message: String?
    var showBackground: Bool = true

    // MARK: - State

    @State private var isAnimating: Bool = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background
            if showBackground {
                Color(.systemBackground)
                    .opacity(0.9)
                    .ignoresSafeArea()
            }

            // Content
            VStack(spacing: 20) {
                // Animated spinner
                spinnerView

                // Message
                if let message = message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
            )
        }
        .onAppear {
            isAnimating = true
        }
    }

    // MARK: - Spinner View

    private var spinnerView: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                .frame(width: 48, height: 48)

            // Animated arc
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 48, height: 48)
                .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                .animation(
                    .linear(duration: 1)
                        .repeatForever(autoreverses: false),
                    value: isAnimating
                )
        }
    }
}

// MARK: - Simple Loading Spinner

struct SimpleLoadingSpinner: View {
    // MARK: - Properties

    var size: CGFloat = 24
    var lineWidth: CGFloat = 3
    var color: Color = .blue

    // MARK: - State

    @State private var isAnimating: Bool = false

    // MARK: - Body

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
            .animation(
                .linear(duration: 0.8)
                    .repeatForever(autoreverses: false),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Loading Overlay Modifier

struct LoadingOverlay: ViewModifier {
    let isLoading: Bool
    let message: String?

    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(isLoading)
                .blur(radius: isLoading ? 2 : 0)

            if isLoading {
                LoadingView(message: message)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}

extension View {
    func loadingOverlay(isLoading: Bool, message: String? = nil) -> some View {
        modifier(LoadingOverlay(isLoading: isLoading, message: message))
    }
}

// MARK: - Pulse Loading Dots

struct PulseLoadingDots: View {
    // MARK: - Properties

    var dotSize: CGFloat = 8
    var color: Color = .blue
    var spacing: CGFloat = 4

    // MARK: - State

    @State private var isAnimating: Bool = false

    // MARK: - Body

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(isAnimating ? 1 : 0.5)
                    .opacity(isAnimating ? 1 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Previews

#Preview("Loading View") {
    LoadingView(message: "Loading your data...")
}

#Preview("Simple Spinner") {
    VStack(spacing: 32) {
        SimpleLoadingSpinner()

        SimpleLoadingSpinner(size: 32, lineWidth: 4, color: .purple)

        SimpleLoadingSpinner(size: 48, lineWidth: 5, color: .green)
    }
}

#Preview("Pulse Dots") {
    VStack(spacing: 32) {
        PulseLoadingDots()

        PulseLoadingDots(dotSize: 10, color: .purple, spacing: 6)

        PulseLoadingDots(dotSize: 12, color: .green, spacing: 8)
    }
}

#Preview("Loading Overlay") {
    VStack {
        Text("Content behind loading overlay")
            .font(.title)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .loadingOverlay(isLoading: true, message: "Processing...")
}
