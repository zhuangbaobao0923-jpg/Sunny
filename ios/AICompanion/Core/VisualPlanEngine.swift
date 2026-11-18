import Foundation

// MARK: - 形象生成方案（动态三方案）

/// 一个候选形象方案：结构化提示词 + 本地渲染参数
/// 提示词遵循「主体 + 外貌细节 + 道具 + 环境 + 光影 + 视角 + 风格词」的标准结构。
struct VisualPlan: Identifiable, Equatable {
    let id: UUID
    let title: String       // 方案名（风格 · 场景）
    let prompt: String      // 可直接喂给绘图模型的结构化提示词
    let imageName: String   // 本地立绘底图（接真文生图后替换为生成图路径）
    let hue: Double         // 本地渲染：色相偏移（区分三方案的视觉效果）
    let saturation: Double  // 本地渲染：饱和度
    /// AI 真图落盘路径（非 nil 时优先渲染文件图，忽略底图 + 滤镜）
    var localPath: String? = nil
}

/// 按用户描述动态生成三个截然不同的方案：风格差异 × 场景差异 × 人物差异。
/// 接真文生图 API 后，把 prompt 直接发给模型、用返回图替换 imageName 即可。
enum VisualPlanEngine {

    // MARK: 三条风格方向（方案间风格差异的骨架）

    private struct Direction {
        let styleLabel: String       // 风格名（展示用）
        let styleWords: String       // 英文风格词（提示词用）
        let lightings: [String]      // 光影池
        let angles: [String]         // 视角池
        let palettes: [String]       // 色板
        let render: (hue: Double, sat: Double)
    }

    private static let directions: [Direction] = [
        Direction(
            styleLabel: "写实电影感",
            styleWords: "photorealistic, cinematic lighting, shallow depth of field, 8k, ultra detailed",
            lightings: ["冷月光勾勒发丝轮廓，背景灯市虚化成光斑", "逆光剪影，边缘泛着暖金描边", "顶光切割面部，一半沉在阴影里"],
            angles: ["电影感低角度仰拍", "浅景深特写", "侧面跟拍视角"],
            palettes: ["冷蓝银灰", "暗金琥珀", "墨黑绯红"],
            render: (hue: 0, sat: 1)
        ),
        Direction(
            styleLabel: "3D 古风 CG",
            styleWords: "3D render, ancient chinese style CG, octane render, soft global illumination, 4k wallpaper",
            lightings: ["柔和天光从云隙洒落，衣袂通透发亮", "霓虹灯笼暖光打在侧脸", "晨雾中丁达尔光柱斜穿画面"],
            angles: ["半身环绕镜头", "微俯视构图", "广角纵深机位"],
            palettes: ["青白黛蓝", "绯樱粉金", "苍翠鎏金"],
            render: (hue: 150, sat: 0.9)
        ),
        Direction(
            styleLabel: "国风水墨",
            styleWords: "chinese ink painting style, ethereal, flowing brush strokes, minimalist, rice paper texture",
            lightings: ["留白大面积，主体一抹淡墨晕染", "朱砂一点提亮眼尾", "淡彩薄雾笼住背景"],
            angles: ["立轴竖构图", "散点透视远景", "留白居中构图"],
            palettes: ["墨色黛青", "绛红鎏金", "月白青灰"],
            render: (hue: -110, sat: 0.75)
        )
    ]

    // MARK: 场景池（按描述关键词选主题，保证场景与输入相关）

    private static func scenes(for description: String) -> [String] {
        let d = description.lowercased()
        if ["剑", "侠", "古风", "皇子", "郡主", "君", "江湖", "殿", "宫", "当铺"].contains(where: d.contains) {
            return ["月夜屋檐之上", "竹林深处", "雪原孤驿前", "上元灯市的人潮中", "断桥烟雨里", "宫墙檐角月下", "荒漠孤城残垣"]
        }
        if ["学", "校园", "同学", "课", "社团", "转学生", "学长", "少女", "校服"].contains(where: d.contains) {
            return ["黄昏的教室窗边", "图书馆落地窗前", "雨后操场的跑道上", "天台围栏旁", "樱花飘落的坡道", "便利店暖灯下", "放学后的琴房"]
        }
        if ["星", "观", "夜", "占", "命", "道"].contains(where: d.contains) {
            return ["漏雨的观星台上", "山顶天文台穹顶下", "深宫檐角星河下", "渔火零星的渡口", "荒原篝火旁", "城郊栈道尽头"]
        }
        return ["黄昏的天台", "雨夜街头", "深秋林间小径", "海边栈桥", "旧书店门口", "霓虹巷口", "清晨的站台"]
    }

    // MARK: 道具池（按主题匹配）

    private static func props(for description: String) -> [String] {
        let d = description.lowercased()
        if ["剑", "侠", "皇子", "郡主", "君", "江湖", "殿", "宫"].contains(where: d.contains) {
            return ["手持一柄未出鞘的长剑", "执一盏晃动的绢灯", "腰间悬着旧玉佩", "指尖捻着半张当票", "肩头落着细雪", "背负褪色刀鞘"]
        }
        if ["学", "校园", "同学", "课", "转学生", "学长", "少女", "校服"].contains(where: d.contains) {
            return ["怀抱一摞课本", "书包侧袋插着草莓牛奶", "指尖转着中性笔", "举着一台旧相机", "拎着装满零食的纸袋", "耳机挂在颈间"]
        }
        return ["指间夹着一封未寄出的信", "拎着一盏旧风灯", "肩上搭着深色围巾", "手心摊着一枚旧硬币", "袖口沾着淡淡颜料"]
    }

    // MARK: 人物气质（方案间人物差异）

    private static func moods(for description: String) -> [String] {
        let d = description.lowercased()
        if ["少女", "女", "她", "学姐", "姑娘", "郡主", "小师妹"].contains(where: d.contains) {
            return ["眉眼弯弯，笑意明亮，透着不设防的元气", "神情安静，眼睫低垂，藏着一点心事", "下巴微扬，眼神倔强又狡黠"]
        }
        return ["眼神冷冽，眉骨锋利，沧桑克制", "少年感英气，下颌线干净，眼神干净赤诚", "神情神秘，眼尾上挑，笑意不达眼底"]
    }

    // MARK: 确定性随机（同一描述 + 同一批次可复现，换一批才换 seed）

    private struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }

    // MARK: 入口：生成三个差异化方案

    static func plans(for description: String, artStyle: String, seed: Int) -> [VisualPlan] {
        let subject = description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "气质出众的神秘人物"
            : description.trimmingCharacters(in: .whitespacesAndNewlines)

        let scenePool = scenes(for: subject)
        let propPool = props(for: subject)
        let moodPool = moods(for: subject)
        // 本地方案的底图池：用满 7 张自带立绘，断网时「换一批」也看得出变化
        // （AI 生图失败时以前只在 3 张之间打转，用户当然觉得换了个寂寞）
        let images = ["char_shenjinghan", "char_nalanzheng", "char_shaonu",
                      "char_xiaoxuance", "char_xiewujiu", "char_peijingnian", "char_lingyunshang"]

        // 注意：String.hashValue 可能为负数，必须走 bitPattern 转 UInt64，否则强制转换直接崩溃
        var rng = SeededRNG(
            seed: UInt64(bitPattern: Int64(subject.hashValue))
                &+ UInt64(bitPattern: Int64(seed))
                &+ UInt64(bitPattern: Int64(artStyle.hashValue))
        )
        let sceneShuffle = scenePool.shuffled(using: &rng)
        let propShuffle = propPool.shuffled(using: &rng)
        let moodShuffle = moodPool.shuffled(using: &rng)
        let imageShuffle = images.shuffled(using: &rng)
        let styleHint = artStyle == "经典" ? "" : "，\(artStyle)画风"

        return zip(zip(directions, sceneShuffle), zip(propShuffle, moodShuffle)).enumerated().map { index, pair in
            let (direction, scene) = pair.0
            let prop = pair.1.0
            let mood = pair.1.1
            let lighting = direction.lightings[index % direction.lightings.count]
            let angle = direction.angles[index % direction.angles.count]
            let palette = direction.palettes[index % direction.palettes.count]

            // 标准结构：主体 + 外貌细节（含气质）+ 道具 + 环境 + 光影 + 视角 + 风格词 + 色板
            let prompt = [
                subject + styleHint,
                mood,
                prop,
                "置身\(scene)",
                lighting,
                angle,
                direction.styleWords,
                "color palette: \(palette)"
            ].joined(separator: "，")

            return VisualPlan(
                id: UUID(),
                title: "\(direction.styleLabel) · \(Self.shortScene(scene))",
                prompt: prompt,
                imageName: imageShuffle[index % imageShuffle.count],
                hue: direction.render.hue,
                saturation: direction.render.sat
            )
        }
    }

    /// 场景短语截短用于标题：「雨后操场的跑道上」→「雨后操场」
    private static func shortScene(_ scene: String) -> String {
        var s = String(scene.prefix(4))
        while s.hasSuffix("的") || s.hasSuffix("里") || s.hasSuffix("上") || s.hasSuffix("前") {
            s.removeLast()
        }
        return s
    }
}
