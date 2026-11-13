import StoreKit

/// The App Store's signed word on the app's subscriptions, as StoreKit 2 has it on this device, for chatbots with the RevenueCat tool.
/// ChatFrom checks each against Apple's own certificate, and reads only what Apple signed. It is about whoever is signed in to the
/// App Store on the device, which is not always whoever is signed in to the app.
enum AppStoreSubscriptions {
    /// As many as ChatFrom reads on a turn, APP_STORE_MAX in the app's libs/app-subscriber.ts: a person holds one or two.
    static let max = 5

    /// Each subscription the customer has had in this app, ended ones too, so the chat can say why one ended. Nothing it reads asks the person anything.
    static func read() async -> [AppStoreProof] {
        // A product's statuses cover its whole subscription group, so one product from each group the customer has had here.
        var productOfGroup: [String: String] = [:]
        for await result in Transaction.all {
            guard case .verified(let transaction) = result, transaction.productType == .autoRenewable, let group = transaction.subscriptionGroupID else { continue }
            if productOfGroup[group] == nil { productOfGroup[group] = transaction.productID }
        }
        guard !productOfGroup.isEmpty else { return [] }
        let products: [Product]
        do {
            products = try await Product.products(for: Set(productOfGroup.values))
        } catch {
            chatLog.notice("The App Store's subscriptions could not be read: \(error.localizedDescription, privacy: .public)")
            return []
        }
        var proofs: [AppStoreProof] = []
        for product in products {
            guard let statuses = try? await product.subscription?.status else { continue }
            proofs += statuses.map { AppStoreProof(transaction: $0.transaction.jwsRepresentation, renewal: $0.renewalInfo.jwsRepresentation) }
        }
        return Array(proofs.prefix(max))
    }
}
