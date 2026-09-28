# CanSNS 🥫

**友達の今日を、1本ずつ受け取る。** 自動販売機がモチーフの、少人数向けSNS（iPhoneアプリ / SwiftUI）。

- 朝6:00〜20:59 … **納品**（投稿）の時間。友達の缶のラベルは見えるけど、まだ開けられない
- 21:00 … **開店**。ボタンを押して「ガコン！」→ 取り出し口をスワイプ → タップで「プシュッ！」→ 中身
- 翌朝6:00 … **廃棄**。自分の缶は自分の「冷蔵庫」（アーカイブ）へ

## 動かし方（Mac が必要です）

1. Mac に **Xcode 16 以上** を入れる（App Store から無料）
2. このフォルダの **`CanSNS.xcodeproj` をダブルクリック** して開く
3. 画面上部の実行先で **iPhone のシミュレーター**（例: iPhone 16）を選ぶ
4. **▶︎（Run）ボタン** を押す

> 実機（自分のiPhone）で動かすときは、左の一覧で `CanSNS` → `Signing & Capabilities` → `Team` に自分の Apple ID を選んでください。
> 初回は Firebase のライブラリのダウンロードに数分かかります。

## 2つのモード

| モード | いつ | できること |
| --- | --- | --- |
| **Firebase モード** | `CanSNS/GoogleService-Info.plist` があるとき（自動） | 友達と本当にやりとりできる。開店・廃棄はサーバーの時計で判定。写真・動画・音声は `CanSNS/Cloudinary-Info.plist` も必要 |
| **オフライン（デモ）モード** | 設定ファイルがないとき／開発者メニューで切り替えたとき | 端末の中だけ。友達ボット・時刻ずらし・なりきりで1人で全部試せる |

Firebase と Cloudinary（写真・動画・音声の置き場所）の設定は **[docs/SETUP.md](docs/SETUP.md)** を見てください。

## 1人で全部の流れを試す方法（オフラインモード）

1. 名前とアイコンを決めて「はじめる」
2. 「**デモの自販機を置く**」を押す（友達ボット3人入り）
3. ホームの「今日の缶を納品する」から投稿してみる（何本でもOK）→ 全員そろって「満タン！」の演出
4. **設定タブ → 開発者メニュー** で時刻を「夜 21:30」にする → 友達の缶を開けられるようになる
5. 「翌朝 6:05 に進める」→ 缶が廃棄されて **冷蔵庫** に入るのを確認
6. 「なりきるユーザー」で友達に切り替えると、友達側の操作（開封・リアクション・手紙）も試せる

## フォルダ構成

```
CanSNS/
├── CanSNSApp.swift         アプリの入り口・タブ
├── Core/                   ルール（SwiftUI を使わない部分。テストあり）
│   ├── BusinessClock.swift   営業日・納品/開店/廃棄の時刻計算
│   ├── Models.swift          ユーザー・自販機・缶・リアクションなどのデータの形
│   ├── AppDatabase.swift     納品する・開ける・冷蔵庫に入れる などの操作とルール
│   ├── MachineEffects.swift  満タン・全員購入済み・限定ネオン・新商品入荷、レベル
│   ├── SkyPalette.swift      時刻ごとの空の色
│   ├── SoundSynth.swift      「ガコン」「プシュッ」を計算で作る効果音
│   ├── DatabaseChanges.swift 操作の前後の差分（Firebase に書き込む内容）
│   ├── Cloudinary.swift      Cloudinary の設定・送信データの組み立て
│   └── DemoSeeder.swift      デモ用の友達ボット
├── App/
│   ├── AppStore.swift        アプリの状態。オフライン保存と Firebase モードの切り替え
│   ├── CloudSync.swift       Firebase（ログイン・Firestore）とのやりとり
│   ├── CloudinaryUploader.swift 写真・動画・音声を Cloudinary に送る・受け取る
│   └── Services.swift        写真・動画・音声の保存、効果音、振動、通知、カメラ
└── Views/                  画面
    ├── Home/                 自販機・空の背景
    ├── Open/                 開封演出・缶の中身・リアクション・ストロー・手紙
    ├── Deliver/              納品（投稿）画面
    ├── Fridge/               冷蔵庫・お知らせ
    ├── Settings/             設定・開発者メニュー
    └── Onboarding/           最初の登録・自販機えらび
Tests/CanSNSCoreTests/      ルール部分の自動テスト
firebase/                   Firestore のセキュリティルール
docs/SPEC.md                仕様と「検討事項」をどう決めたかのメモ
docs/SETUP.md               Firebase と Cloudinary の設定手順
```

## テストの実行

ルール部分（`CanSNS/Core`）には自動テストがあります。Mac のターミナルでこのフォルダに移動して:

```sh
swift test
```

## 今の制限（次にやること）

- ログインは「匿名ログイン」です。アプリを削除するとアカウントが消えます（Apple / Google ログインは今後）
- プッシュ通知（アプリを閉じていても届く通知）はまだです。今は毎日決まった時刻のローカル通知と、アプリ内のお知らせだけです
