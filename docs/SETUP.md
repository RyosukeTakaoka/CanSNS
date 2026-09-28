# Firebase と Cloudinary のセットアップ手順

CanSNS を友達と本当に使えるようにするための設定です。所要時間は 30 分くらいです。

| サービス | 役割 | 料金 |
| --- | --- | --- |
| **Firebase**（Authentication・Cloud Firestore） | ログイン、缶のラベル・本文・リアクション・手紙などのデータ | 無料の **Spark プラン** のままでOK（クレジットカード不要） |
| **Cloudinary** | 写真・動画・音声のファイル置き場 | 無料プランでOK（クレジットカード不要） |

> アプリのコードはもう両方に対応しています。
> - `GoogleService-Info.plist` を入れると → **Firebase モード**（友達と共有）
> - さらに `Cloudinary-Info.plist` を入れると → **写真・動画・音声の缶も送れる**
> - どちらも入れていないあいだは、今までどおり **オフライン（デモ）モード**
>
> 2つの設定ファイルは `.gitignore` に入れてあるので、GitHub には上がりません。

---

## 0. 先に確認：Bundle Identifier（アプリのID）

Firebase とアプリを結びつけるための「アプリのID」です。
このプロジェクトでは **`com.ryosuketakaoka.CanSNS`** にしてあります。

- Xcode で `CanSNS.xcodeproj` を開き、左の一覧の一番上の **CanSNS** → **TARGETS の CanSNS** → **Signing & Capabilities** タブ
  - **Team**: 自分の Apple ID を選ぶ（なければ「Add an Account…」で追加）
  - **Bundle Identifier**: `com.ryosuketakaoka.CanSNS` になっていることを確認
  - もし「すでに使われています」と出たら、`com.ryosuketakaoka.cansns2` のように少し変えて、**以下の手順 A-2 でも同じIDを使ってください**

---

# A. Firebase の設定

## A-1. Firebase プロジェクトを作る

1. https://console.firebase.google.com を開いて、Google アカウントでログイン
2. **「プロジェクトを作成」**（「Firebase プロジェクトを作成」と出ることもあります）
3. プロジェクト名: `CanSNS`（なんでもOK）
4. Google アナリティクス: **オフでOK**
5. 「プロジェクトを作成」→ 完了まで待つ

> 料金プランは **Spark（無料）のまま** で大丈夫です。アップグレードは不要です。

## A-2. iOS アプリを登録して、設定ファイルをダウンロードする

1. プロジェクトのトップ画面で **「iOS+」**（アップルのマーク）を押す
2. **Apple バンドル ID**: `com.ryosuketakaoka.CanSNS`（Xcode と**完全に同じ**にする）
3. アプリのニックネーム: `CanSNS`（なんでもOK）／ App Store ID: 空欄でOK
4. 「アプリを登録」
5. **`GoogleService-Info.plist` をダウンロード**
6. Finder で、ダウンロードしたファイルを **このリポジトリの `CanSNS/` フォルダ（`CanSNSApp.swift` がある場所）** に入れる
   - Xcode 16 以降は、フォルダに入れるだけで自動でプロジェクトに追加されます
   - ファイル名が `GoogleService-Info (1).plist` のようになっていたら、`GoogleService-Info.plist` に直す
7. 「Firebase SDK の追加」「初期化コードの追加」は **アプリ側でもうやってあるので「次へ」で飛ばしてOK**

## A-3. ログイン（Authentication）をオンにする

1. 左メニュー **「構築」→「Authentication」→「始める」**
2. **「Sign-in method」** タブ → **「匿名」** → **有効にする** → 保存

> 今は「匿名ログイン」です。ログイン画面なしで使えますが、**アプリを削除するとアカウントも消えます**。
> あとで Apple / Google ログインに変えることもできます。

## A-4. データベース（Cloud Firestore）を作る

1. 左メニュー **「構築」→「Firestore Database」→「データベースを作成」**
2. ロケーション: **`asia-northeast1`（東京）**（あとから変えられないので注意）
3. **「本番環境モードで開始」** を選ぶ → 作成
4. できたら上の **「ルール」** タブを開く
5. 中身を全部消して、このリポジトリの **`firebase/firestore.rules` の内容を全部コピーして貼り付け** → **「公開」**
   - ルールの中に Cloudinary の cloud name（`dw71feikq`）が書いてあります。別の cloud name を使うときは、そこも書きかえてください
   - アプリを更新したときにルールも変わっていることがあります。`firebase/firestore.rules` が変わったら、もう一度貼り付けて「公開」してください

> Firebase の「Storage」は使いません（写真などは Cloudinary に置きます）。

---

# B. Cloudinary の設定

## B-1. アカウントを作る

1. https://cloudinary.com を開いて **「Sign up for free」**
2. Google アカウントなどで登録（無料プラン。クレジットカードは不要）
3. 最初にいくつか質問（役割・用途など）が出たら、適当に答えてOK

## B-2. 「Cloud name」を確認する

- ログイン後のトップ画面（Dashboard / Home）に **Cloud name** が表示されています（例: `dxxxxxxxx`）
- 見つからないときは、左下の **歯車（Settings）→「API Keys」** のページの上のほうにあります

> 同じページにある **API Key / API Secret はアプリに入れないでください**（とくに Secret は絶対に秘密）。
> CanSNS は Secret を使わない「署名なしアップロード」なので、必要なのは Cloud name と、次に作るプリセット名だけです。

## B-3. アップロードプリセット（Upload preset）を作る

「アプリからのアップロードをどんな設定で受け付けるか」を決めるものです。

1. 左下の **歯車（Settings）→「Upload」**（または「Upload Presets」）を開く
2. **「Add upload preset」**（「Add Upload Preset」）を押す
3. 次のように設定する
   | 項目 | 設定 |
   | --- | --- |
   | Upload preset name | `cansns_unsigned` |
   | **Signing mode** | **Unsigned**（ここが一番大事） |
   | Asset folder（Folder） | `cansns` |
   | Use filename / Use the filename as public ID | **オフ** |
   | Unique filename | **オン** |
4. 見つかれば、ついでに **「Upload Control」（または「Upload Manipulations」）の「Allowed formats」** に
   `jpg,jpeg,png,heic,mov,mp4,m4a` と入れておくと、ほかの種類のファイルを送られにくくなります（なくてもOK）
5. **Save**

## B-4. アプリに Cloudinary の設定ファイルを入れる

1. このリポジトリの **`docs/Cloudinary-Info.sample.plist`** をコピーして、
   **`CanSNS/` フォルダ（`GoogleService-Info.plist` と同じ場所）に `Cloudinary-Info.plist` という名前で置く**
   - ターミナルなら、リポジトリのフォルダで:
     ```sh
     cp docs/Cloudinary-Info.sample.plist CanSNS/Cloudinary-Info.plist
     ```
2. Xcode で `CanSNS/Cloudinary-Info.plist` を開き、2つの値を書きかえる
   | Key | Value |
   | --- | --- |
   | `CLOUD_NAME` | B-2 で確認した Cloud name |
   | `UPLOAD_PRESET` | `cansns_unsigned` |

---

# C. 動かして確認する

1. Xcode で `CanSNS.xcodeproj` を開く
   - 初回は Firebase のライブラリのダウンロードに数分かかります（左下の「Resolving Package…」が消えるまで待つ）
   - うまくいかないときは、メニューの **File → Packages → Reset Package Caches**
2. シミュレーターで ▶︎ 実行
3. 「自販機に電気を入れています…」のあと、名前の登録画面が出れば Firebase の接続は成功
4. **設定タブ → 開発者メニュー** の「モード」が **「Firebase（友達と共有）」** になっていることを確認
5. 写真の缶を1本納品してみる → Cloudinary の **Media Library（Assets）の `cansns` フォルダ** に画像が増えていれば成功

### 1人で「友達とのやりとり」を試す方法

シミュレーターを2台使うと、それぞれ別のアカウントになります。

1. Xcode 上部の実行先で **iPhone 16** を選んで ▶︎ → 名前を登録 → 「新しく自販機を置く」
2. 設定タブ → 招待コードをメモ
3. 実行先を **iPhone 16 Pro** など別の機種に変えて ▶︎ → 名前を登録 → 招待コードで参加
4. 2台で納品してみる（2人そろったので開店の条件OK）
5. **21:00 をすぎると**、おたがいの缶を開けられます
   - Firebase モードでは時刻は**サーバーの時計**で判定されるので、時刻をずらすテストはできません
   - 時刻を動かして試したいときは、開発者メニューから **オフライン（デモ）モード** に切り替えてください

---

# D. うまくいかないとき

| 症状 | 見るところ |
| --- | --- |
| 「サーバーにつながりませんでした」と出る | A-3 の「匿名」ログインが有効になっているか |
| 名前を登録しても先に進まない／「〜に失敗しました」と出る | A-4 のルールを「公開」したか。Xcode 下のログに `Missing or insufficient permissions` と出ていたらルールの問題 |
| 納品画面に「Cloudinary の設定が必要です」と出る | B-4 のファイル名（`Cloudinary-Info.plist`）と置き場所、値が `YOUR_...` のままになっていないか |
| 「アップロードに失敗しました：Upload preset not found」 | B-3 のプリセット名と B-4 の `UPLOAD_PRESET` が同じか |
| 「アップロードに失敗しました：Upload preset must be whitelisted for unsigned uploads」 | B-3 の Signing mode が **Unsigned** になっているか |
| 「アップロードに失敗しました：Invalid cloud_name」 | B-4 の `CLOUD_NAME` |
| 開店後なのに中身が「受け取れませんでした」になる | 端末の時刻が自動設定になっているか |
| ずっとオフラインモードのまま | `GoogleService-Info.plist` の名前と置き場所（`CanSNS/` フォルダの中） |

Xcode 下のログ（コンソール）に出ている英語のエラー文を、そのまま貼って聞いてもらえればすぐ調べます。

---

# 知っておいてほしいこと（安全のために）

- **Cloudinary の写真などの URL は「知っている人なら見られる」** しくみです。
  - CanSNS では URL を Firestore の「缶の中身」に入れていて、サーバーのルールで **開店時間の友達・投稿者・冷蔵庫に入れた人しか読めない** ようにしています
  - ファイル名もランダムなので、推測されることはまずありません
  - ただし、見られる人が URL をコピーして他の人に渡すことはできてしまいます（スクリーンショットと同じです）
- **「署名なしアップロード」は、Cloud name とプリセット名を知っている人なら誰でもアップロードできます。**
  - `Cloudinary-Info.plist` を GitHub などに公開しないでください（`.gitignore` 済み）
  - 使用量は Cloudinary の Dashboard で確認できます。無料プランは毎月 25 クレジット（ストレージ・転送量あわせて約 25GB 分）までです
- **Cloudinary に上げたファイルは、アプリからは消えません**（翌朝の廃棄はアプリの中の見え方の話です）。
  消したいときは Cloudinary の Media Library から手で削除できます。

---

## 参考：データの置き場所

```
Firestore
  users/{uid}                                   プロフィール（参加中の自販機のID一覧）
  users/{uid}/notifications/{id}                お知らせ（本人だけ読める）
  users/{uid}/fridge/{canId}                    冷蔵庫に入れた友達の缶（本人だけ読める）
  inviteCodes/{code}                            招待コード → 自販機ID
  machines/{machineId}                          自販機
  machines/{machineId}/members/{uid}            メンバー
  machines/{machineId}/cans/{canId}             缶のラベル（メンバーならいつでも読める）
  machines/{machineId}/cans/{canId}/private/content
                                                缶の中身（本文と Cloudinary の URL。21:00〜翌6:00 だけ友達が読める）
  machines/{machineId}/activities/{id}          開封・リアクション
  machines/{machineId}/letters/{id}             返却口の手紙（送った人と投稿者だけ）
  machines/{machineId}/straws/{id}              ストロー（2人だけ）

Cloudinary
  cansns/…                                      写真（image）・動画と音声（video）
```

コマンドに慣れてきたら、Firebase CLI（`firebase deploy --only firestore:rules`）でルールを反映することもできます（`firebase.json` を用意してあります）。
