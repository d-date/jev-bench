import Foundation
import Jev

/// The label set the three arms are scored against.
enum Department: String, CaseIterable, JevChoiceOptions {
    case billing
    case technical
    case sales
    case account

    static var optionDescriptions: [Department: String] {
        [
            .billing: "Invoices, charges, refunds, pricing on an existing contract, trial billing",
            .technical: "Bugs, outages, errors, SDK and integration problems",
            .sales: "Quotes for new or expanded contracts, plan upgrades, discount negotiation",
            .account: "Login, credentials, two-factor, seats, permissions, deactivating members",
        ]
    }
}

struct Sample: Sendable {
    var id: String
    /// The raw Japanese inquiry, exactly as a user would type it.
    var text: String
    var department: Department
    var isUrgent: Bool
    /// What makes this sample hard. Used to group the results.
    var stressor: String
}

enum Dataset {
    static let samples: [Sample] = [
        .init(
            id: "s01",
            text: "3日前から売上の入金が全部失敗してます。今日中に給料を払わないといけないのに、サポートに連絡しても返事がありません。至急なんとかしてください。",
            department: .billing, isUrgent: true, stressor: "平易"
        ),
        .init(
            id: "s02",
            text: "iOSアプリのSDKをv4.2に上げたらビルドが通らなくなりました。Xcode 27でarm64のシミュレータ向けにリンクエラーが出ます。",
            department: .technical, isUrgent: false, stressor: "平易"
        ),
        .init(
            id: "s03",
            text: "来期から利用人数を80名に増やす予定です。エンタープライズプランだと1人あたりいくらになりますか。見積もりが欲しいです。",
            department: .sales, isUrgent: false, stressor: "平易"
        ),
        .init(
            id: "s04",
            text: "二段階認証に使っていた端末を機種変更で紛失してしまい、ログインできません。バックアップコードも控えていませんでした。",
            department: .account, isUrgent: true, stressor: "平易"
        ),
        .init(
            id: "s05",
            text: "請求書の件ではないのですが、管理画面にログインしようとすると延々とリダイレクトが続きます。Chromeでも Safari でも同じでした。",
            department: .technical, isUrgent: false, stressor: "否定・スコープ語"
        ),
        .init(
            id: "s06",
            text: "障害のお知らせは拝見しました。そちらは急ぎではありません。それとは別に、先月分の請求額が契約より 12,000 円多いように見えるので確認をお願いします。",
            department: .billing, isUrgent: false, stressor: "否定・スコープ語"
        ),
        .init(
            id: "s07",
            text: "先週の火曜に申し込んだのですが、4/3 締めの請求に2月利用分が載っていて、2026-03-15 の値上げ前の単価で計算されているように見えます。差額はいくらになりますか。",
            department: .billing, isUrgent: false, stressor: "日付・数値"
        ),
        .init(
            id: "s08",
            text: "昨日の夜、娘の誕生日の準備でバタバタしていて、ケーキを取りに行った帰りに気づいたんですが、アプリのプッシュ通知が iPhone だけ届いていません。Android の方は普通に届いています。あ、ちなみに来月引っ越します。",
            department: .technical, isUrgent: false, stressor: "無関係な詳細"
        ),
        .init(
            id: "s09",
            text: "解約したいわけではありません。ただ、このまま値上げが続くなら他社への乗り換えも検討せざるを得ません。continue する場合の割引条件を教えてください。",
            department: .sales, isUrgent: false, stressor: "否定・スコープ語"
        ),
        .init(
            id: "s10",
            text: "本番のAPIが全リージョンで502を返しています。5分前から復旧していません。数千人のユーザーが決済できない状態です。",
            department: .technical, isUrgent: true, stressor: "平易"
        ),
        .init(
            id: "s11",
            text: "退職した元メンバーのアカウントがまだ有効になっていました。権限を剥奪して、ついでに請求対象からも外してほしいです。",
            department: .account, isUrgent: true, stressor: "境界があいまい"
        ),
        .init(
            id: "s12",
            text: "無料トライアルが 14 日で切れると書いてありましたが、私の画面では残り 21 日と表示されています。どちらが正しいのでしょうか。課金はまだ発生していません。",
            department: .billing, isUrgent: false, stressor: "日付・数値"
        ),
    ]
}

/// The routing questions, shared by the Jev arms so A and C differ only in the state.
enum Questions {
    static let department = ChoiceQuestion<Department>(
        "department", "Which team should handle this customer inquiry?"
    )

    static let urgency = NoulQuestion(
        "urgency", "Does this inquiry need to be handled today?",
        whenTrue: "The customer states a deadline within a day, or describes an active outage or a lockout blocking their work.",
        whenFalse: "The inquiry can wait for the normal support queue, even if the customer sounds annoyed."
    )

    static let frustration = ScoreQuestion(
        "frustration", "How frustrated is the customer?",
        levels: ["Calm and factual", "Visibly annoyed", "Angry, threatening to leave"]
    )

    static let all = try! JevQuestionSet([department, urgency, frustration])
}
