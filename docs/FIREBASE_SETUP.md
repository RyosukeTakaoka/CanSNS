# Firebase のセットアップ手順

CanSNS を友達と本当に使えるようにするための、Firebase 側の設定です。
所要時間は 20〜30 分くらいです。上から順番に進めてください。

> アプリのコードはもう Firebase に対応しています。
> 下の手順 3 の `GoogleService-Info.plist` をアプリに入れると、自動で「Firebase モード」になります。
> 入れていないあいだは、今までどおり「オフライン（デモ）モード」で動きます。

---

## 0. 先に確認：Bundle Identifier（アプリのID）

Firebase とアプリを結びつけるための「アプリのID」です。
このプロジェクトでは **`com.ryosuketakaoka.CanSNS`** にしてあります。

- Xcode で `CanSNS.xcodeproj` を開き、左の一覧の一番上の **CanSNS** → **TARGETS の CanSNS** → **Signing & Capabilities** タブ
  - **Team**: 自分の Apple ID を選ぶ（なければ「Add an Account…」で追加）
  - **Bundle Identifier**: `com.ryosuketakaoka.CanSNS` になっていることを確認
  - もし「すでに使われています」と出たら、`com.ryosuketakaoka.cansns2` のように少し変えて、**以下の手順3でも同じIDを使ってください**

---

## 1. Firebase プロジェクトを作る

1. https://console.firebase.google.com を開いて、Google アカウントでログイン
2. **「プロジェクトを作成」**
3. プロジェクト名: `CanSNS`（なんでもOK）
4. Google アナリティクス: **オフでOK**（あとからでも入れられます）
5. 「プロジェクトを作成」→ 完了まで待つ

## 2. 料金プランを「Blaze（従量課金）」にする ⚠️

写真・動画・音声を保存する **Cloud Storage は、2024年10月から Blaze プランでないと使えなくなりました。**

- 左下の **「アップグレード」** → **Blaze** を選び、支払い方法（クレジットカード）を登録します
- **無料枠があるので、友達数人で使う程度ならほぼ 0 円** です
- 念のため **予算アラート** を設定しておきましょう（例: 100円）。使いすぎるとメールで知らせてくれます
  - アップグレードの途中で「予算を設定」と出てくるので、そこで金額を入れればOK

> クレジットカードを登録できない場合は教えてください。
> 「写真と音声だけ Firestore に保存する（動画はなし）」形に作り変えることもできます。

## 3. iOS アプリを登録して、設定ファイルをダウンロードする

1. プロジェクトのトップ画面で **iOS のアイコン（「iOS+」）** を押す
2. **Apple バンドル ID**: `com.ryosuketakaoka.CanSNS`（Xcode と**完全に同じ**にする）
3. アプリのニックネーム: `CanSNS`（なんでもOK）／ App Store ID: 空欄でOK
4. 「アプリを登録」
5. **`GoogleService-Info.plist` をダウンロード**
6. Finder で、ダウンロードしたファイルを **このリポジトリの `CanSNS/` フォルダ（`CanSNSApp.swift` がある場所）** に入れる
   - Xcode 16 以降は、フォルダに入れるだけで自動でプロジェクトに追加されます
   - ファイル名が `GoogleService-Info (1).plist` のようになっていたら、`GoogleService-Info.plist` に直してください
7. 画面の「Firebase SDK の追加」「初期化コードの追加」は **もうアプリ側でやってあるので「次へ」で飛ばしてOK**

> `GoogleService-Info.plist` は `.gitignore` に入れてあるので、GitHub には上がりません。

## 4. ログイン（Authentication）をオンにする

1. 左メニュー **「構築」→「Authentication」→「始める」**
2. **「Sign-in method」** タブ → **「匿名」** → **有効にする** → 保存

> 今は「匿名ログイン」にしています。ログイン画面なしで使えますが、
> **アプリを削除するとアカウントも消えます**。あとで Apple / Google ログインに変えることもできます。

## 5. データベース（Cloud Firestore）を作る

1. 左メニュー **「構築」→「Firestore Database」→「データベースを作成」**
2. ロケーション: **`asia-northeast1`（東京）**（あとから変えられないので注意）
3. **「本番環境モードで開始」** を選ぶ → 作成
4. できたら上の **「ルール」** タブを開く
5. 中身を全部消して、このリポジトリの **`firebase/firestore.rules` の内容を全部コピーして貼り付け** → **「公開」**

## 6. ファイル置き場（Cloud Storage）を作る

1. 左メニュー **「構築」→「Storage」→「始める」**
2. ロケーション: **`US-CENTRAL1` などアメリカのリージョン**がおすすめ
   - 「Always Free（無料枠）」が使えるのは `US-CENTRAL1` / `US-EAST1` / `US-WEST1` だけです
3. **「本番環境モードで開始」** → 作成
4. 上の **「ルール」** タブを開き、**`firebase/storage.rules` の内容を全部貼り付け** → **「公開」**
5. 「Cloud Storage が Firestore にアクセスするための権限を付与しますか？」のような確認が出たら **許可** してください
   （Storage のルールの中で「この人はメンバーか？」を Firestore で確かめているためです）

## 7. アプリを動かして確認する

1. Xcode で `CanSNS.xcodeproj` を開く
   - 初回は Firebase のライブラリのダウンロードに数分かかります（左下の「Resolving Package…」が消えるまで待つ）
   - うまくいかないときは、メニューの **File → Packages → Reset Package Caches**
2. シミュレーターで ▶︎ 実行
3. 「自販機に電気を入れています…」のあと、名前の登録画面が出れば接続成功です
4. **設定タブ → 開発者メニュー** の「モード」が **「Firebase（友達と共有）」** になっていることを確認

### 1人で「友達とのやりとり」を試す方法

シミュレーターを2台使うと、それぞれ別のアカウントになります。

1. Xcode 上部の実行先で **iPhone 16** を選んで ▶︎ → 名前を登録 → 「新しく自販機を置く」
2. 設定タブ → 招待コードをメモ
3. 実行先を **iPhone 16 Pro** など別の機種に変えて ▶︎ → 名前を登録 → 招待コードで参加
4. 2台で納品してみる（2人そろったので開店条件OK）
5. 21:00 をすぎると、おたがいの缶を開けられます
   - Firebase モードでは時刻は**サーバーの時計**で判定されるので、時刻をずらすテストはできません
   - 時刻を動かして試したいときは、開発者メニューから **オフライン（デモ）モード** に切り替えてください

## 8. うまくいかないとき

| 症状 | 見るところ |
| --- | --- |
| 「サーバーにつながりませんでした」と出る | 手順 4 の「匿名」ログインが有効になっているか |
| 名前を登録しても先に進まない／「〜に失敗しました」と出る | 手順 5 のルールを「公開」したか。Xcode 下のログに `Missing or insufficient permissions` と出ていたらルールの問題です |
| 写真・動画・音声の缶だけ納品に失敗する | 手順 2（Blaze）と手順 6（Storage とそのルール、権限の許可） |
| 開店後なのに中身が「受け取れませんでした」になる | 端末の時刻が合っているか。自動設定になっているか |
| ずっとオフラインモードのまま | `GoogleService-Info.plist` の名前と置き場所（`CanSNS/` フォルダの中） |

Xcode 下のログ（コンソール）に出ている英語のエラー文を、そのまま貼って聞いてもらえればすぐ調べます。

---

## 参考：データの置き場所

```
users/{uid}                                   プロフィール（参加中の自販機のID一覧）
users/{uid}/notifications/{id}                お知らせ（本人だけ読める）
users/{uid}/fridge/{canId}                    冷蔵庫に入れた友達の缶（本人だけ読める）
inviteCodes/{code}                            招待コード → 自販機ID
machines/{machineId}                          自販機
machines/{machineId}/members/{uid}            メンバー
machines/{machineId}/cans/{canId}             缶のラベル（メンバーならいつでも読める）
machines/{machineId}/cans/{canId}/private/content  缶の中身（21:00〜翌6:00 だけ友達が読める）
machines/{machineId}/activities/{id}          開封・リアクション
machines/{machineId}/letters/{id}             返却口の手紙（送った人と投稿者だけ）
machines/{machineId}/straws/{id}              ストロー（2人だけ）
Storage: machines/{machineId}/cans/{canId}/…  写真・動画・音声（中身と同じ人だけ読める）
```

コマンドに慣れてきたら、Firebase CLI（`firebase deploy --only firestore:rules,storage`）でルールを反映することもできます（`firebase.json` を用意してあります）。
