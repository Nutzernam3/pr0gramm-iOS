
import Foundation
import UIKit

enum ConnectorUpdateType {
    case login(success: Bool)
    case captcha(image: UIImage)
    case logout
}

protocol Pr0grammConnectorObserver: class {
    func connectorDidUpdate(type: ConnectorUpdateType)
}

enum Flags: Int {
    case sfw = 1
    case nsfw = 2
    case nsfl = 4
    case nsfp = 8
}

@objc
enum Sorting: Int {
    case top = 1
    case neu = 0
    
    var description: String {
        switch self {
        case .top:
            return "Beliebt"
        case .neu:
            return "Neu"
        }
    }
}

enum FetchType {
    case reload
    case more
    case search
}

enum PostType {
    case login
    case voteComment
    case voteItem
    case voteTag
    
    var path: String {
        switch self {
        case .login:
           return ""
        case .voteComment:
           return "comments"
        case .voteItem:
           return "items"
        case .voteTag:
           return "tags"
        }
    }
}

enum MediaType {
    case image, gif, video
}

enum Vote: Int {
    case neutral = 0
    case up = 1
    case down = -1
    case favorite = 2
}

class Pr0grammConnector {

    var observers: [Pr0grammConnectorObserver] = []

    let http = "https://"
    let thumb = "thumb."
    let img = "img."
    let vid = "vid."
    let baseURL = "pr0gramm.com/"
    let top = "api/items/get?flags=3&promoted=0"
    let itemInfo = "api/items/info?itemId="
    var captchaResponse: LoginCaptcha?
    var nonce: String?
    var userName: String?
        
    var isLoggedIn: Bool {
        guard let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://pr0gramm.com/")!) else { return false }
            
        for cookie in cookies {
            if cookie.name == "me" {
                print("Cookie found. User is logged in.")
                
                let value = cookie.value.removingPercentEncoding?.data(using: .utf8)!
                
                if let json = try? JSONSerialization.jsonObject(with: value!, options: .mutableContainers) as? [String: Any] {
                    if let id = json["id"] as? String {
                        nonce = String(id.prefix(16))
                    }
                    if let userName = json["n"] as? String {
                        self.userName = userName
                    }
                }

                return true
            }
        }
        return false
    }
    
    init() {
        URLSession.shared.configuration.httpCookieAcceptPolicy = .always
        AppSettings.isLoggedIn = isLoggedIn
    }
    
    func addObserver(_ observer: Pr0grammConnectorObserver) {
        observers.append(observer)
    }
    
    func removeObserver(_ observer: Pr0grammConnectorObserver) {
        for i in observers.indices {
            if observers[i] === observer {
                observers.remove(at: i)
                break
            }
        }
    }
    
    func getCaptcha() {
        let url = URL(string:"https://pr0gramm.com/api/user/captcha")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
            guard let data = data else { return }
            let jsonDecoder = JSONDecoder()
            do {
                self.captchaResponse = try jsonDecoder.decode(LoginCaptcha.self, from: data)
                if let image = self.captchaResponse?.captcha?.base64ToImage() {
                    DispatchQueue.main.async {
                        self.observers.forEach { $0.connectorDidUpdate(type: .captcha(image: image))}
                    }
                }
            } catch let error {
                print(error)
            }
        }
        task.resume()
    }
    
    func login(userName: String,
               password: String,
               solvedCaptcha: String) {
        
        let url = URL(string: http + baseURL + "api/user/login")!
        guard let token = captchaResponse?.token else { return }
        let data: [String: String] = ["name": userName,
                                      "password": password,
                                      "token": token,
                                      "captcha": solvedCaptcha]
        post(data: data, to: url, postType: .login) { [unowned self] success in
            print("Login: \(success)")
            AppSettings.isLoggedIn = success && self.isLoggedIn
            DispatchQueue.main.async {
                self.observers.forEach { $0.connectorDidUpdate(type: .login(success: success)) }
            }
        }
    }
    
    func logout() {
        let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://pr0gramm.com/")!)
        cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        AppSettings.isLoggedIn = false
        userName = nil
        observers.forEach { $0.connectorDidUpdate(type: .logout) }
    }
        
    func vote(id: Int, value: Vote, type: PostType) {
        guard isLoggedIn else { return }
        guard let nonce = nonce else { return }
        let data: [String: String] = ["id": "\(id)",
                                      "vote": "\(value.rawValue)",
                                      "_nonce": nonce]
        
        let url = URL(string: http + baseURL + "api/\(type.path)/vote")!
        post(data: data, to: url, postType: .voteItem) { success in
            print("Voted \(type.path): \(success)")
        }
    }
    
    func postComment(to itemId: Int, parentId: Int = 0, comment: String) {
        guard isLoggedIn else { return }
        guard let nonce = nonce else { return }
        let data: [String: String] = ["parentId": "\(parentId)",
                                      "itemId": "\(itemId)",
                                      "comment": "\(comment)",
                                      "_nonce": nonce]
        
        var components = URLComponents()
        components.scheme = "https"
        components.host = "pr0gramm.com"
        components.path = "/api/comments/post"
        guard let url = components.url else { return }

        post(data: data, to: url, postType: .voteItem) { success in
            print("Posted comment: \(success)")
        }
    }
    
    private func post(data: [String: String], to url: URL, postType: PostType, completion: @escaping (Bool) -> Void) {
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded;", forHTTPHeaderField: "Content-Type")
        let body = HTTPUtils.formUrlencode(data)
        request.httpBody = body.data(using: .utf8)

        let task = URLSession.shared.dataTask(with: request as URLRequest, completionHandler: { data, response, error in
            guard let data = data else { completion(false); return }
            print(String(data: data, encoding: .utf8) ?? "Nope")
            do {
                let jsonDecoder = JSONDecoder()
                switch postType {
                case .login:
                    let responseModel = try jsonDecoder.decode(Login.self, from: data)
                    completion(responseModel.success ?? false)
                case .voteTag, .voteItem, .voteComment:
                    completion(true)
                }
            } catch {
                print(error)
                completion(false)
            }
        })
        task.resume()
    }
    
    func fetchUserInfo(for name: String, completion: @escaping (UserInfo?) -> Void) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "pr0gramm.com"
        components.path = "/api/profile/info"
        components.queryItems = [
            URLQueryItem(name: "name", value: "\(name)")
        ]
        
        guard let url = components.url else { completion(nil); return }
        let request = getRequest(with: url)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data else { completion(nil); return }
            let jsonDecoder = JSONDecoder()
            do {
                let responseModel = try jsonDecoder.decode(UserInfo.self, from: data)
                completion(responseModel)
            } catch {
                print(error)
                completion(nil)
            }
        }
        task.resume()
    }
    
    func fetchUserCollection(sorting: Sorting,
                             flags: [Flags],
                             userName: String,
                             collectionName: String,
                             afterId: Int? = nil,
                             completion: @escaping (AllItems?) -> Void) {
        guard isLoggedIn else { return }
            
        let userQueryItem = URLQueryItem(name: "user", value: userName)
        let collectionQueryItem = URLQueryItem(name: "collection", value: collectionName)

        fetchItems(sorting: sorting,
                   flags: flags,
                   additionalQueryItems: [userQueryItem, collectionQueryItem],
                   afterId: afterId,
                   completion: completion)
    }
    
    func fetchUserItems(sorting: Sorting,
                        flags: [Flags],
                        userName: String,
                        afterId: Int? = nil,
                        completion: @escaping (AllItems?) -> Void) {
        guard isLoggedIn else { return }
        let queryItem = URLQueryItem(name: "user", value: userName)
        
        fetchItems(sorting: sorting,
                   flags: flags,
                   additionalQueryItems: [queryItem],
                   afterId: afterId,
                   completion: completion)
    }
    
    func search(sorting: Sorting,
                flags: [Flags],
                for tags: [String],
                afterId: Int? = nil,
                completion: @escaping (AllItems?) -> Void) {
        
        let queryItem = URLQueryItem(name: "tags", value: "\(tags.first ?? "")")
        
        fetchItems(sorting: sorting,
                   flags: flags,
                   additionalQueryItems: [queryItem],
                   afterId: afterId,
                   completion: completion)
    }
    
    
    func fetchItems(sorting: Sorting,
                    flags: [Flags],
                    additionalQueryItems: [URLQueryItem] = [],
                    afterId: Int? = nil,
                    completion: @escaping (AllItems?) -> Void) {
        
        let flagsCombined = flags.reduce(0, { $0 + $1.rawValue })
        
        var components = URLComponents()
        components.scheme = "https"
        components.host = "pr0gramm.com"
        components.path = "/api/items/get"
        components.queryItems = [
            URLQueryItem(name: "flags", value: "\(flagsCombined)"),
            URLQueryItem(name: "promoted", value: "\(sorting.rawValue)")
            ] + additionalQueryItems

        if let afterId = afterId {
            components.queryItems?.append(URLQueryItem(name: "older", value: "\(afterId)"))
        }
        
        guard let url = components.url else { completion(nil); return }
        let request = getRequest(with: url)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data else { completion(nil); return }
            let jsonDecoder = JSONDecoder()
            do {
                let responseModel = try jsonDecoder.decode(AllItems.self, from: data)
                completion(responseModel)
            } catch {
                print(error)
                completion(nil)
            }
        }
        task.resume()
    }
            
    func thumbLink(for item: Item) -> String {
        let link = http + thumb + baseURL + item.thumb
        return link
    }
    
    func link(for item: Item) -> (link: String, mediaType: MediaType) {
        if item.image.hasSuffix(".mp4") {
            return (http + vid + baseURL + item.image, .video)
        } else if item.image.hasSuffix(".gif") {
            return (http + img + baseURL + item.image, .gif)
        } else {
            return (http + img + baseURL + item.image, .image)
        }
    }

    func loadItemInfo(for id: Int, completion: @escaping (ItemInfo?) -> Void) {
        let url = URL(string: http + baseURL + itemInfo + "\(id)")
        let task = URLSession.shared.dataTask(with: url!) { (data, response, error) in
            guard let data = data else { return }
            let jsonDecoder = JSONDecoder()
            do {
                let itemInfo = try jsonDecoder.decode(ItemInfo.self, from: data)
                completion(itemInfo)
            } catch let error {
                print(error)
                completion(nil)
            }
        }
        task.resume()
    }
    
    private func getRequest(with url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "GET"
        return request
    }
}


extension String {
    static let formUrlencodedAllowedCharacters =
        CharacterSet(charactersIn: "0123456789" +
            "abcdefghijklmnopqrstuvwxyz" +
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ" +
            "-._* ")

    public func formUrlencoded() -> String {
        let encoded = addingPercentEncoding(withAllowedCharacters: String.formUrlencodedAllowedCharacters)
        return encoded?.replacingOccurrences(of: " ", with: "+") ?? ""
    }
}

extension String {
    func base64ToImage() -> UIImage? {
        if let url = URL(string: self),
            let data = try? Data(contentsOf: url),
            let image = UIImage(data: data) {
            return image
        }
        return nil
    }
}

class HTTPUtils {
    public class func formUrlencode(_ values: [String: String]) -> String {
        return values.map { key, value in
            return "\(key.formUrlencoded())=\(value.formUrlencoded())"
        }.joined(separator: "&")
    }
}
