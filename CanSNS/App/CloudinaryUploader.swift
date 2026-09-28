import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Cloudinary に写真・動画・音声をアップロード／ダウンロードする。
///
/// サーバーを用意しなくていいように「署名なし（Unsigned）アップロード」を使う。
/// 返ってきた URL は Firestore の「缶の中身」に保存するので、
/// URL を知ることができるのは、中身を読める人（開店時間の友達・投稿者・冷蔵庫に入れた人）だけ。
enum CloudinaryUploader {
    /// アプリに入れた Cloudinary-Info.plist の設定（なければ nil）
    static var config: CloudinaryConfig? {
        guard let url = Bundle.main.url(forResource: "Cloudinary-Info", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any] else { return nil }
        return CloudinaryConfig(dictionary: dictionary)
    }

    static var isConfigured: Bool { config != nil }

    /// ファイルをアップロードして、保存先の URL（https://res.cloudinary.com/...）を返す
    static func upload(fileURL: URL, kind: ContentKind) async throws -> String {
        guard let config else { throw CloudinaryError.notConfigured }
        let fileData = try Data(contentsOf: fileURL)

        var form = MultipartFormData()
        form.addField(name: "upload_preset", value: config.uploadPreset)
        form.addFile(name: "file", fileName: fileURL.lastPathComponent,
                     mimeType: MultipartFormData.mimeType(forExtension: fileURL.pathExtension), data: fileData)

        var request = URLRequest(url: config.uploadURL(for: kind))
        request.httpMethod = "POST"
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.upload(for: request, from: form.finalized())
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try CloudinaryUploadResponse.secureURL(from: data, statusCode: statusCode)
    }

    /// URL のファイルをダウンロードして、端末の destination に保存する
    static func download(from url: URL, to destination: URL) async throws {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CloudinaryError.downloadFailed
        }
        try data.write(to: destination, options: .atomic)
    }
}
