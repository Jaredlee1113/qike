import Foundation
import SwiftUI
import Combine

@MainActor
class CoinTemplateStorageManager: ObservableObject {
    static let shared = CoinTemplateStorageManager()

    @Published var templates: [CoinTemplate] = []
    @Published var selectedTemplateId: UUID?

    private let templatesKey = "coin_templates"
    private let selectedTemplateKey = "selected_coin_template"

    private init() {
        loadTemplates()
        loadSelectedTemplate()
    }

    // MARK: - 文件路径管理

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var templatesDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("CoinTemplates")
        // 创建目录（如果不存在）
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func imagePath(for imageName: String) -> URL {
        templatesDirectory.appendingPathComponent(imageName)
    }

    // MARK: - 数据加载

    private func loadTemplates() {
        if let data = UserDefaults.standard.data(forKey: templatesKey),
           let decoded = try? JSONDecoder().decode([CoinTemplate].self, from: data) {
            templates = decoded
        }
    }

    private func loadSelectedTemplate() {
        if let uuidString = UserDefaults.standard.string(forKey: selectedTemplateKey),
           let uuid = UUID(uuidString: uuidString) {
            selectedTemplateId = uuid
        }
    }

    private func saveTemplates() {
        if let encoded = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(encoded, forKey: templatesKey)
        }
    }

    private func saveSelectedTemplate() {
        if let uuid = selectedTemplateId {
            UserDefaults.standard.set(uuid.uuidString, forKey: selectedTemplateKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedTemplateKey)
        }
    }

    // MARK: - 模板管理

    /// 获取当前选中的模板
    var selectedTemplate: CoinTemplate? {
        templates.first { $0.id == selectedTemplateId }
    }

    /// 选择模板
    func selectTemplate(_ template: CoinTemplate) {
        selectedTemplateId = template.id
        saveSelectedTemplate()
    }

    /// 创建新模板
    func createTemplate(name: String, frontImage: UIImage, backImage: UIImage) -> CoinTemplate? {
        let id = UUID()
        let frontImageName = "\(id.uuidString)_front.jpg"
        let backImageName = "\(id.uuidString)_back.jpg"

        // 保存图片
        guard saveImage(frontImage, to: frontImageName),
              saveImage(backImage, to: backImageName) else {
            return nil
        }

        let template = CoinTemplate(
            id: id,
            name: name,
            createdDate: Date(),
            frontImageName: frontImageName,
            backImageName: backImageName
        )

        templates.append(template)
        saveTemplates()

        // 如果是第一个模板，自动选中
        if templates.count == 1 {
            selectTemplate(template)
        }

        return template
    }

    /// 更新模板
    func updateTemplate(_ template: CoinTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
            saveTemplates()
        }
    }

    /// 删除模板
    func deleteTemplate(_ template: CoinTemplate) {
        // 删除图片文件
        deleteImage(named: template.frontImageName)
        deleteImage(named: template.backImageName)

        // 删除模板数据
        templates.removeAll { $0.id == template.id }
        saveTemplates()

        // 如果删除的是当前选中的模板，清除选中状态或选择另一个
        if selectedTemplateId == template.id {
            selectedTemplateId = templates.first?.id
            saveSelectedTemplate()
        }
    }

    // MARK: - 图片操作

    /// 保存图片到文件
    private func saveImage(_ image: UIImage, to imageName: String) -> Bool {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else { return false }
        let path = imagePath(for: imageName)
        do {
            try imageData.write(to: path)
            return true
        } catch {
            print("保存图片失败: \(error)")
            return false
        }
    }

    /// 加载图片
    func loadImage(named imageName: String) -> UIImage? {
        let path = imagePath(for: imageName)
        return UIImage(contentsOfFile: path.path)
    }

    /// 删除图片
    private func deleteImage(named imageName: String) {
        let path = imagePath(for: imageName)
        try? FileManager.default.removeItem(at: path)
    }

    // MARK: - 便捷方法

    /// 获取指定面的图片
    func image(for template: CoinTemplate, face: CoinFace) -> UIImage? {
        let imageName = face == .front ? template.frontImageName : template.backImageName
        return loadImage(named: imageName)
    }

    /// 检查是否有可用模板
    var hasTemplates: Bool {
        !templates.isEmpty
    }
}
