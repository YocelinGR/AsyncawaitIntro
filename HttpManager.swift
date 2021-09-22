//
//  HttpManager.swift
//  HttpManager
//
//  Created by Yocelin Garcia Romero on 21/09/21.
//

import Foundation
// Http Client

struct HttpClient {
    let session: URLSession
    let baseUrl: String

    typealias ResultResponse = (Result<Data?, Error>) -> Void

    func get(path: String, complete: @escaping ResultResponse) {
        request(method: "get", path: path, body: nil, complete: complete)
    }

    private func request(method: String, path: String, body: Data?, complete: @escaping ResultResponse) {
        guard let req = RequestBuilder.build(method: method, baseUrl: baseUrl, path: path, body: body) else {
            complete(.failure(RequestError.invalidRequest))
            return
        }

        session.dataTask(with: req) { data, response, error in
            if let error = error {
                complete(.failure(error))
                return
            }
            let response = HttpResponse(response: response)
            let result = response.result(for: data)
            complete(result)
        }.resume()
    }
}

 // Rest Client
typealias Restable = Codable & Identifiable

struct RestClient<T: Restable> {
    let client: HttpClient
    let path: String

    public var decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public var encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    func list(complete: @escaping (Result<[T], Error>) -> Void) {
        client.get(path: path) { result in
            let newResult = result.flatMap { parseList(data: $0) }
            complete(newResult)
        }
    }

    func show(complete: @escaping (Result<T?, Error>) -> Void) {
        show("", complete: complete)
    }

    func show(_ identifier: String, complete: @escaping (Result<T?, Error>) -> Void) {
        client.get(path: "\(path)/\(identifier)") { result in
            let newResult = result.flatMap { parse(data: $0) }
            complete(newResult)
        }
    }

    private func parseList(data: Data?) -> Result<[T], Error> {
        if let data = data {
            return Result { try self.decoder.decode([T].self, from: data) }
        } else {
            return .success([])
        }
    }

    private func parse(data: Data?) -> Result<T?, Error> {
        if let data = data {
            return Result { try self.decoder.decode(T.self, from: data) }
        } else {
            return .success(nil)
        }
    }
}

// Http Response
struct HttpResponse {
let httpUrlResponse: HTTPURLResponse

init(response: URLResponse?) {
    httpUrlResponse = (response as? HTTPURLResponse) ?? HTTPURLResponse()
}

var status: StatusCode {
    return StatusCode(rawValue: httpUrlResponse.statusCode)
}

func result(for data: Data?) -> Result<Data?, Error> {
        if let udata = data, !udata.isEmpty {
            return status.result().map { _ in data }
        } else {
            return status.result().map { _ in nil }
        }
    }
}

// Response error

protocol Titleable {
    var title: String { get }
}

enum ResponseError: Error, Titleable {
    case invalidResponse
    case clientError
    case serverError

    var title: String {
        switch self {
        case .invalidResponse:
            return "Invalid Response"
        case .clientError:
            return "Client error"
        case .serverError:
            return "Internal Server error"
        }
    }
}

// Request builder

struct RequestBuilder: CustomDebugStringConvertible {
    enum ContentMode {
        case jsonApp

        func accept() -> String {
            switch self {
            case .jsonApp:
                return "application/json"
            }
        }

        func contentType() -> String {
            switch self {
            case .jsonApp:
                return "application/json"
            }
        }
    }

    private let urlComponents: URLComponents
    public var scheme: String = "https"
    public var method: String = "get"
    public var path: String = "/"
    public var body: Data?
    public var headers: [String: String]?
    public var contentMode: ContentMode = .jsonApp

    var debugDescription: String {
        let currentUrl = url()?.debugDescription ?? "Not valid URL"
        let currentHeaders = headers?.debugDescription ?? ""
        if let ubody = body, let currentBody = String(data: ubody, encoding: .utf8) {
            return "Request to: \(method.uppercased()) - \(currentUrl) -H \(currentHeaders) -d \(currentBody)"
        } else {
            return "Request to: \(method.uppercased()) - \(currentUrl) -H \(currentHeaders)"
        }
    }

    static func build(method: String, baseUrl: String, path: String, body: Data?) -> URLRequest? {
        var builder = RequestBuilder(baseUrl: baseUrl)
        builder.method = method
        builder.path = path
        builder.body = body
        return builder.request()
    }

    init(baseUrl: String) {
        urlComponents = URLComponents(string: baseUrl)!
    }

    func url() -> URL? {
        var comps = urlComponents
        comps.scheme = scheme
        comps.path = path
        return comps.url
    }

    func request() -> URLRequest? {
        guard let url = url() else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.addValue(contentMode.accept(), forHTTPHeaderField: "Accept")
        req.addValue(contentMode.contentType(), forHTTPHeaderField: "Content-Type")
        if let headers = self.headers {
            for (key, value) in headers {
                req.addValue(value, forHTTPHeaderField: key)
            }
        }
        return req
    }
}

// Request error
enum RequestError: Error, Titleable {
    case invalidRequest

    var title: String {
        switch self {
        case .invalidRequest:
            return "Invalid Request"
        }
    }
}

// Status code
enum StatusCode: Int {
    case unkown = 0
    case info
    case success
    case redirection
    case clientError
    case serverError

    public init(rawValue: Int) {
        switch rawValue {
        case 100, 101, 102:
            self = .info
        case 200, 201, 202, 203, 204, 205, 206, 207, 208, 226:
            self = .success
        case 300, 301, 302, 303, 304, 305, 306, 307, 308:
            self = .redirection
        case 400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412,
             413, 414, 415, 416, 417, 418, 421, 422, 423, 424, 426, 428, 429, 431, 451:
            self = .clientError
        case 500, 501, 502, 503, 504, 505, 506, 507, 510, 511:
            self = .serverError
        default:
            self = .unkown
        }
    }

    func result() -> Result<Int?, Error> {
        switch self {
        case .success:
            return .success(rawValue)
        case .clientError:
            return .failure(ResponseError.clientError)
        case .serverError:
            return .failure(ResponseError.serverError)
        default:
            return .failure(ResponseError.invalidResponse)
        }
    }
}

