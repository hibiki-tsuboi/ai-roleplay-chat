import Foundation

struct Scenario: Identifiable {
    let id: String
    let title: String
    let characterName: String
    let summary: String

    static let lateReport = Scenario(
        id: "late-report",
        title: "提出が遅れている部下",
        characterName: "田中",
        summary: "昨日が期限だった資料が、まだ届いていません。真面目だけれど報告が遅れがちな田中さんに、上司として声をかけてみましょう。"
    )
}
