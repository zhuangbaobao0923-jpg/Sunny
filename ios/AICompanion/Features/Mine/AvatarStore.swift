import SwiftUI
import Observation
import PhotosUI

/// 头像：存一张图到 Documents，Mine 页和账号资料页共用同一个来源
@MainActor
@Observable
final class AvatarStore {
    static let shared = AvatarStore()

    var image: UIImage?

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("avatar.jpg")
    }

    private init() { load() }

    func load() {
        image = UIImage(contentsOfFile: fileURL.path)
    }

    func save(_ image: UIImage) {
        // 压到 512 以内，别把几 MB 的原图塞进沙盒
        let side: CGFloat = 512
        let scale = min(1, side / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: fileURL, options: .atomic)
        self.image = resized
    }
}

/// 相机（模拟器没有摄像头时会自动走相册）
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        init(onImage: @escaping (UIImage) -> Void) { self.onImage = onImage }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage) {
                onImage(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

/// 城市选择：省份分组 + 搜索，点一下即选
struct CityPickerView: View {
    let current: String
    var onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""

    private let regions: [(province: String, cities: [String])] = [
        ("直辖市", ["北京", "上海", "天津", "重庆"]),
        ("广东", ["广州", "深圳", "珠海", "佛山", "东莞", "中山"]),
        ("浙江", ["杭州", "宁波", "温州", "嘉兴", "绍兴"]),
        ("江苏", ["南京", "苏州", "无锡", "常州", "南通"]),
        ("四川", ["成都", "绵阳", "乐山"]),
        ("湖北", ["武汉", "宜昌", "襄阳"]),
        ("湖南", ["长沙", "株洲", "湘潭"]),
        ("陕西", ["西安", "咸阳", "宝鸡"]),
        ("山东", ["济南", "青岛", "烟台", "潍坊"]),
        ("河南", ["郑州", "洛阳", "开封"]),
        ("福建", ["福州", "厦门", "泉州"]),
        ("辽宁", ["沈阳", "大连", "鞍山"]),
        ("黑龙江", ["哈尔滨", "大庆"]),
        ("吉林", ["长春", "吉林"]),
        ("河北", ["石家庄", "唐山", "保定"]),
        ("山西", ["太原", "大同"]),
        ("内蒙古", ["呼和浩特", "包头"]),
        ("安徽", ["合肥", "芜湖", "蚌埠"]),
        ("江西", ["南昌", "赣州", "九江"]),
        ("广西", ["南宁", "桂林", "柳州"]),
        ("海南", ["海口", "三亚"]),
        ("贵州", ["贵阳", "遵义"]),
        ("云南", ["昆明", "大理", "丽江"]),
        ("西藏", ["拉萨"]),
        ("甘肃", ["兰州", "天水"]),
        ("青海", ["西宁"]),
        ("宁夏", ["银川"]),
        ("新疆", ["乌鲁木齐", "喀什"]),
        ("港澳台", ["香港", "澳门", "台北", "高雄"])
    ]

    private var filtered: [(province: String, cities: [String])] {
        let key = keyword.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return regions }
        return regions.compactMap { region in
            let cities = region.cities.filter { $0.contains(key) }
            return cities.isEmpty ? nil : (region.province, cities)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered, id: \.province) { region in
                    Section(region.province) {
                        ForEach(region.cities, id: \.self) { city in
                            Button {
                                onPick(city)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(city)
                                        .foregroundStyle(Palette.ink)
                                    Spacer()
                                    if city == current {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Palette.gold)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $keyword, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索城市")
            .navigationTitle("选择城市")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Palette.ink2)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
        }
        .preferredColorScheme(.dark)
    }
}
