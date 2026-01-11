//
//  IntentHandler.swift
//  KaiIntents
//
//  Intent handler for Siri integration.
//

import Intents

/// Main intent handler for the KaiIntents extension.
/// This class serves as the entry point for Siri intent handling.
/// With App Intents (iOS 16+), most handling is done by the intent classes themselves.
class IntentHandler: INExtension {

    override func handler(for intent: INIntent) -> Any {
        // Return self as the default handler
        // App Intents handle themselves, so this is primarily for compatibility
        return self
    }
}
