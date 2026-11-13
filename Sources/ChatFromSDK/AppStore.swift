import StoreKit

/// The App Store's signed word on the app's subscriptions, as StoreKit 2 has it on this device, for chatbots with the RevenueCat tool.
/// ChatFrom checks each against Apple's own certificate, and reads only what Apple signed. It is about whoever is signed in to the
/// App Store on the device, which is not always whoever is signed in to the app.
enum AppStoreSubscriptions {
    /// As many as ChatFrom reads on a turn, APP_STORE_MAX in the app's libs/app-subscriber.ts: a person holds one or two.
    static let most = 5

    /// Each subscription the customer has had in this app, ended ones too, so the chat can say why one ended: those that give access first,
    /// then the latest to end. Nil when the App Store could not be read, which is not the same as none. Nothing here asks the person anything.
    static func read() async -> [AppStoreProof]? {
        // Statuses are kept per subscription group, and any transaction names its group, even one for a product no longer on sale.
        var groups = Set<String>()
        for await result in Transaction.all {
            guard case .verified(let transaction) = result, transaction.productType == .autoRenewable, let group = transaction.subscriptionGroupID else { continue }
            groups.insert(group)
        }
        var statuses: [Product.SubscriptionInfo.Status] = []
        do {
            for group in groups.sorted() {
                statuses += try await Product.SubscriptionInfo.status(for: group)
            }
        } catch {
            chatLog.notice("The App Store's subscriptions could not be read: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return statuses.sorted(by: comesFirst).prefix(most).map { AppStoreProof(transaction: $0.transaction.jwsRepresentation, renewal: $0.renewalInfo.jwsRepresentation) }
    }

    private static func comesFirst(_ a: Product.SubscriptionInfo.Status, _ b: Product.SubscriptionInfo.Status) -> Bool {
        let (first, second) = (rank(a.state), rank(b.state))
        if first != second { return first < second }
        return (a.transaction.unsafePayloadValue.expirationDate ?? .distantPast) > (b.transaction.unsafePayloadValue.expirationDate ?? .distantPast)
    }

    /// Those that give access, then a payment being tried again, then those that are over.
    private static func rank(_ state: Product.SubscriptionInfo.RenewalState) -> Int {
        switch state {
        case .subscribed: return 0
        case .inGracePeriod: return 1
        case .inBillingRetryPeriod: return 2
        case .expired: return 3
        case .revoked: return 4
        default: return 5
        }
    }
}
