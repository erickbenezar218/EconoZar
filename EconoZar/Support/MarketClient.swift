import Foundation
import Observation

enum MarketSettings {
    static let urlKey = "market.serverURL"
    static let keyKey = "market.apiKey"

    static var serverURL: String {
        let raw = UserDefaults.standard.string(forKey: urlKey) ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static var apiKey: String {
        UserDefaults.standard.string(forKey: keyKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static var isConfigured: Bool {
        !serverURL.isEmpty && !apiKey.isEmpty
    }
}

struct LeituraPayload: Encodable {
    var aporte: Double
    var registrado: Bool
    var negocio: String
    var cofre: String
    var tipoCofre: String
    var faltaMeta: Double
    var notificar: Bool
}

struct MarketQuote: Decodable, Identifiable {
    var ticker: String
    var preco: Double?
    var variacaoDiaPercent: Double?
    var dividendYieldAnual: Double?
    var descontoMaxima52s: Double?
    var erro: String?

    var id: String { ticker }

    var rotulo: String {
        ticker.replacingOccurrences(of: ".SA", with: "")
    }
}

struct MarketReading: Decodable {
    var selicMetaAnual: Double?
    var selicData: String?
    var aporte: Double?
    var registrado: Bool
    var cofre: String
    var sugestaoTicker: String?
    var sugestaoValor: Double?
    var motivo: String
    var aviso: String
    var telegramEnviado: Bool
    var cotacoes: [MarketQuote]
    var geradoEm: String?
}

enum MarketAPIError: LocalizedError {
    case missingConfig
    case badURL
    case unauthorized
    case server(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .missingConfig:
            "Informe o endereço e a chave do servidor em Ajustes."
        case .badURL:
            "O endereço do servidor não é uma URL válida."
        case .unauthorized:
            "O servidor recusou a chave da API."
        case .server(let message):
            message
        case .empty:
            "O servidor respondeu sem dados."
        }
    }
}

enum MarketAPI {
    static func market(baseURL: String, apiKey: String) async throws -> MarketReading {
        try await send(path: "/v1/market", method: "GET", body: Optional<LeituraPayload>.none, baseURL: baseURL, apiKey: apiKey)
    }

    static func leitura(baseURL: String, apiKey: String, payload: LeituraPayload) async throws -> MarketReading {
        try await send(path: "/v1/leitura", method: "POST", body: payload, baseURL: baseURL, apiKey: apiKey)
    }

    static func health(baseURL: String) async throws {
        let trimmed = baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + "/health") else { throw MarketAPIError.badURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    private static func send<Body: Encodable>(
        path: String,
        method: String,
        body: Body?,
        baseURL: String,
        apiKey: String
    ) async throws -> MarketReading {
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedKey.isEmpty else { throw MarketAPIError.missingConfig }
        guard let url = URL(string: trimmedURL + path) else { throw MarketAPIError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 50
        request.setValue(trimmedKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(MarketReading.self, from: data)
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw MarketAPIError.empty }
        if http.statusCode == 401 { throw MarketAPIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "Erro \(http.statusCode)"
            throw MarketAPIError.server(detail)
        }
    }
}

@MainActor
@Observable
final class MarketStore {
    var reading: MarketReading?
    var errorMessage: String?
    var isLoading = false

    func refresh(payload: LeituraPayload?) async {
        guard MarketSettings.isConfigured else {
            errorMessage = MarketAPIError.missingConfig.localizedDescription
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            if let payload {
                reading = try await MarketAPI.leitura(
                    baseURL: MarketSettings.serverURL,
                    apiKey: MarketSettings.apiKey,
                    payload: payload
                )
            } else {
                reading = try await MarketAPI.market(
                    baseURL: MarketSettings.serverURL,
                    apiKey: MarketSettings.apiKey
                )
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
