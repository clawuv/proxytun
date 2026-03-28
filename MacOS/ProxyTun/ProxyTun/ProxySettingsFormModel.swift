import Foundation
import Combine

@MainActor
final class ProxySettingsFormModel: ObservableObject {
    static let proxyTypes = ["http", "socks5"]

    @Published var proxyType = ""
    @Published var proxyHost = ""
    @Published var proxyPort = ""
    @Published var username = ""
    @Published var password = ""
    @Published var validationError = ""

    var isSaveDisabled: Bool {
        proxyType.isEmpty || proxyHost.isEmpty || proxyPort.isEmpty || !validationError.isEmpty
    }

    func load(from config: ProxyTunViewModel.ProxyConfig?) {
        if let config {
            proxyType = config.type
            proxyHost = config.host
            proxyPort = String(config.port)
            username = config.username ?? ""
            password = config.password ?? ""
        } else {
            proxyType = ""
            proxyHost = ""
            proxyPort = ""
            username = ""
            password = ""
        }

        validate()
    }

    func validate() {
        if !proxyHost.isEmpty && !Self.isValidHost(proxyHost) {
            validationError = "Invalid proxy IP or domain."
            return
        }

        if !proxyPort.isEmpty {
            guard let port = Int(proxyPort) else {
                validationError = "Port must be a valid number."
                return
            }

            guard (1...65535).contains(port) else {
                validationError = "Port must be between 1 and 65535."
                return
            }
        }

        validationError = ""
    }

    func buildConfig() -> ProxyTunViewModel.ProxyConfig? {
        validate()
        guard validationError.isEmpty, let port = Int(proxyPort) else {
            return nil
        }

        return ProxyTunViewModel.ProxyConfig(
            type: proxyType,
            host: proxyHost,
            port: port,
            username: username.isEmpty ? nil : username,
            password: password.isEmpty ? nil : password
        )
    }

    func save(to viewModel: ProxyTunViewModel) -> ProxySettingsSaveResult {
        guard let config = buildConfig() else {
            return .validationFailed(validationError)
        }

        viewModel.setProxyConfig(config)

        if viewModel.tunnelSession == nil {
            return .savedLocally
        }

        return .savedAndSynced
    }

    private static func isValidHost(_ host: String) -> Bool {
        isValidIPv4(host) || isValidIPv6(host) || isValidDomain(host)
    }

    private static func isValidIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return false }

        for part in parts {
            guard let num = Int(part), num >= 0 && num <= 255 else {
                return false
            }
        }

        return true
    }

    private static func isValidIPv6(_ ip: String) -> Bool {
        let validChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF:")
        return ip.rangeOfCharacter(from: validChars.inverted) == nil && ip.contains(":")
    }

    private static func isValidDomain(_ domain: String) -> Bool {
        let domainPattern = "^([a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?\\.)*[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", domainPattern)
        return predicate.evaluate(with: domain) || domain == "localhost"
    }
}

enum ProxySettingsSaveResult {
    case savedLocally
    case savedAndSynced
    case validationFailed(String)

    var message: String {
        switch self {
        case .savedLocally:
            return "Settings saved locally. Start the tunnel to push the endpoint into the extension."
        case .savedAndSynced:
            return "Settings saved and sent to the active tunnel."
        case .validationFailed(let message):
            return message
        }
    }

    var isError: Bool {
        if case .validationFailed = self {
            return true
        }
        return false
    }
}
