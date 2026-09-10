import Foundation

struct Scenario: Identifiable {
    let id: String
    let title: String
    let characterName: String
    let summary: String
    // Example first line shown before the practice starts.
    let opener: String

    // `id` and `characterName` must match backend/src/scenarios.ts; the persona itself stays on the server.
    static let lateReport = Scenario(
        id: "late-report",
        title: "提出が遅れている部下",
        characterName: "田中",
        summary: "昨日が期限だった資料が、まだ届いていません。真面目だけれど報告が遅れがちな田中さんに、上司として声をかけてみましょう。",
        opener: "資料の進み具合を教えてもらえる？"
    )

    static let mistakeReport = Scenario(
        id: "mistake-report",
        title: "ミスを報告してきた部下",
        characterName: "佐藤",
        summary: "納品した資料の金額に誤りがあり、取引先から指摘が入りました。ミスを自覚して動揺している佐藤さんと、これからの対応を決めましょう。",
        opener: "まず状況を詳しく聞かせてもらえる？"
    )

    static let lowMotivation = Scenario(
        id: "low-motivation",
        title: "やる気が下がっている部下",
        characterName: "鈴木",
        summary: "希望していた案件から外れ、この数か月は元気がありません。「大丈夫です」と話を切り上げがちな鈴木さんから、本音を聞いてみましょう。",
        opener: "最近どう？ 気になっていることはある？"
    )

    static let attitudeIssue = Scenario(
        id: "attitude-issue",
        title: "態度に問題がある部下",
        characterName: "山本",
        summary: "打ち合わせで同僚のやり方を全員の前で否定し、チームに気まずさが残りました。成果は高く自信のある山本さんに、上司として向き合いましょう。",
        opener: "先日の打ち合わせのことで、少し話せる？"
    )

    static let all: [Scenario] = [lateReport, mistakeReport, lowMotivation, attitudeIssue]

    // Returns nil for a conversation saved by a newer build; callers keep the details stored on the conversation.
    static func named(_ id: String) -> Scenario? {
        all.first { $0.id == id }
    }
}
