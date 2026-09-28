import Foundation

/// Cloudinary（写真・動画・音声の置き場所）の設定。
/// アプリに入れた `Cloudinary-Info.plist` から読み込む。
struct CloudinaryConfig: Equatable {
    static let cloudNameKey = "CLOUD_NAME"
    static let uploadPresetKey = "UPLOAD_PRESET"

    var cloudName: String
    /// 「署名なし（Unsigned）」のアップロードプリセット名
    var uploadPreset: String

    /// plist の中身から作る。空欄やサンプルのままなら nil
    init?(dictionary: [String: Any]) {
        let cloudName = (dictionary[Self.cloudNameKey] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = (dictionary[Self.uploadPresetKey] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cloudName.isEmpty, !preset.isEmpty,
              !cloudName.hasPrefix("YOUR_"), !preset.hasPrefix("YOUR_") else { return nil }
        self.cloudName = cloudName
        self.uploadPreset = preset
    }

    /// Cloudinary では、写真は image、動画と音声は video としてアップロードする
    static func resourceType(for kind: ContentKind) -> String {
        kind == .photo ? "image" : "video"
    }

    func uploadURL(for kind: ContentKind) -> URL {
        URL(string: "https://api.cloudinary.com/v1_1/\(cloudName)/\(Self.resourceType(for: kind))/upload")!
    }
}

enum CloudinaryError: LocalizedError, Equatable {
    case notConfigured
    case uploadFailed(String)
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "写真・動画・音声を送るには Cloudinary の設定が必要です（ひとことの缶は送れます）"
        case .uploadFailed(let reason):
            "写真などのアップロードに失敗しました：\(reason)"
        case .downloadFailed:
            "写真などのダウンロードに失敗しました"
        }
    }
}

/// Cloudinary からの返事（必要なところだけ）
struct CloudinaryUploadResponse: Decodable {
    var secureURL: String
    var publicID: String

    enum CodingKeys: String, CodingKey {
        case secureURL = "secure_url"
        case publicID = "public_id"
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable { var message: String }
        var error: Detail
    }

    /// 返事から、保存された画像などの URL を取り出す。失敗ならエラーの理由を投げる
    static func secureURL(from data: Data, statusCode: Int) throws -> String {
        if (200..<300).contains(statusCode),
           let response = try? JSONDecoder().decode(CloudinaryUploadResponse.self, from: data) {
            return response.secureURL
        }
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) {
            throw CloudinaryError.uploadFailed(body.error.message)
        }
        throw CloudinaryError.uploadFailed("サーバーからの返事が読めませんでした（\(statusCode)）")
    }
}

/// ファイルを HTTP で送るときの「multipart/form-data」形式のデータを作る
struct MultipartFormData {
    let boundary: String
    private var body = Data()

    init(boundary: String = "CanSNS-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func addFile(name: String, fileName: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    /// 最後の区切りをつけた完成データ
    func finalized() -> Data {
        var result = body
        result.append(Data("--\(boundary)--\r\n".utf8))
        return result
    }

    static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        case "heic": "image/heic"
        case "mov": "video/quicktime"
        case "mp4": "video/mp4"
        case "m4a": "audio/mp4"
        default: "application/octet-stream"
        }
    }

    private mutating func append(_ string: String) {
        body.append(Data(string.utf8))
    }
}
