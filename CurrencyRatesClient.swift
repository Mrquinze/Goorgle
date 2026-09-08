import Foundation

/// Live exchange rates for the `100 usd to ils` form of the calculator.
///
/// Uses open.er-api.com, which needs no API key and returns every rate against
/// one base in a single response — so cross-rates are computed locally and the
/// text someone typed never leaves the machine; the only thing sent is the
/// fixed base-currency URL. Rates are cached for six hours, which is far
/// finer-grained than the endpoint's own daily refresh.
actor CurrencyRatesClient {
    static let shared = CurrencyRatesClient()

    private static let endpoint = URL(string: "https://open.er-api.com/v6/latest/USD")!
    private static let maxAge: TimeInterval = 6 * 60 * 60

    private var rates: [String: Double] = [:]
    private var updatedLabel: String?
    private var fetchedAt: Date?

    /// Nil when the rates can't be fetched (offline) or either currency isn't
    /// quoted — the caller then simply shows no answer row.
    func convert(_ request: CurrencyRequest) async -> CalcResult? {
        await refreshIfNeeded()
        guard let from = rates[request.from], let to = rates[request.to], from > 0 else { return nil }
        // Both legs are quoted against the same base, so the cross-rate is
        // just their ratio — no second request for a different base.
        let rate = to / from
        let asOf = updatedLabel
        // Formatting hops to the main actor because that's where Calculator
        // (and its NumberFormatters, which aren't thread-safe) live.
        return await MainActor.run { Calculator.result(for: request, rate: rate, asOf: asOf) }
    }

    private func refreshIfNeeded() async {
        if let fetchedAt, Date().timeIntervalSince(fetchedAt) < Self.maxAge, !rates.isEmpty { return }

        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 8

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let payload = try JSONDecoder().decode(RatesPayload.self, from: data)
            guard payload.result == "success" else { return }
            rates = payload.rates
            updatedLabel = payload.time_last_update_utc.map(Self.shortDate)
            fetchedAt = Date()
        } catch {
            // Keep whatever's cached; a failed refresh shouldn't wipe usable
            // (if slightly stale) rates.
            NSLog("Goorgle: exchange rate fetch failed — \(error.localizedDescription)")
        }
    }

    /// "Sat, 15 Aug 2026 00:02:31 +0000" → "15 Aug 2026".
    private static func shortDate(_ raw: String) -> String {
        let parts = raw.split(separator: " ")
        guard parts.count >= 4 else { return raw }
        return parts[1...3].joined(separator: " ")
    }

    private struct RatesPayload: Decodable {
        let result: String
        let rates: [String: Double]
        let time_last_update_utc: String?
    }
}
