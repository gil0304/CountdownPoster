# Countdown Poster

Googleカレンダーの予定を、予定日までの残り日数に応じて変化する9:16ポスターとして楽しむSwiftUIアプリです。

## 実装済み

- 直近予定のホーム一覧
- 予定タイプ判定
  - 旅行
  - ご飯・カフェ
  - 仕事・学校
  - イベント
  - 判定不能
- location優先、予定名から地域推定、東京デフォルトのおすすめ分岐
- 仕事・学校予定の予定後空き時間判定
- 7日前 / 5日前 / 3日前 / 2日前 / 明日 / 当日の6テンプレート
- 9:16ポスターのSwiftUI描画
- ポスター保存、共有、背景再生成、コピー再生成、予定の非表示
- おすすめ場所の表示、Google Mapsリンク、ポスター採用切り替え
- 設定画面

## 現在の外部連携

このリポジトリ単体で起動できるよう、APIキー未設定時はデモ実装にフォールバックします。
`CountdownPoster/Secrets.plist`を置くと、設定されたAPIから順に実データへ切り替わります。

実データに切り替える場合は、以下の差し替え口から実装します。

- `CalendarEventProviding`
  - 現在: `DemoGoogleCalendarService`
  - 実運用: `GoogleOAuthClient` + `GoogleCalendarAPIService`
- `RuleBasedEventAnalyzer` / `OpenAIEventAnalyzer`
  - APIキーなし: ローカルルール判定
  - APIキーあり: OpenAI Structured Outputsで予定タイプ、地域、背景プロンプトを生成
- `LocalPlaceRecommendationService`
  - APIキーなし: ローカル候補
  - APIキーあり: Google Places Text SearchとPlace Photosで候補と写真を取得
- `PosterFactory`
  - 通常: SwiftUIテンプレート背景 + Places写真
  - 背景再生成: OpenAI Images APIで背景画像を生成し、SwiftUI文字合成と組み合わせる

## 実APIセットアップ

1. `CountdownPoster/Secrets.example.plist`をコピーして`CountdownPoster/Secrets.plist`を作成します。

```sh
cp CountdownPoster/Secrets.example.plist CountdownPoster/Secrets.plist
```

2. `Secrets.plist`に値を入れます。

- `GoogleOAuthClientID`: Google Cloudで作ったiOS OAuthクライアントID
- `GoogleOAuthRedirectScheme`: 逆順クライアントID。例: `com.googleusercontent.apps.xxxxxxxxx`
- `GooglePlacesAPIKey`: Places APIが有効なAPIキー
- `OpenAIAPIKey`: OpenAI APIキー
- `OpenAITextModel`: 予定判定モデル
- `OpenAIImageModel`: 背景生成モデル

3. XcodeのBuild Settingsで`GOOGLE_OAUTH_REDIRECT_SCHEME`を`GoogleOAuthRedirectScheme`と同じ値にします。

この値は生成Info.plistのURL Scheme登録に使われます。ここが一致していないとGoogle OAuthのコールバックがアプリに戻りません。

4. Google Cloudで以下を有効化します。

- Google Calendar API
- Places API (New)

5. OpenAIの背景生成は詳細画面のメニューから「背景再生成」を押したときだけ実行されます。同期のたびに全ポスター画像を生成しないようにして、APIコストを抑えています。

## 注意

MVPとしてiPhoneアプリから直接APIを呼んでいます。本番公開する場合、OpenAI APIキーやGoogle Places APIキーはSupabase Edge Functionsなどのバックエンド経由に移し、アプリ内に直接入れない構成にしてください。

Google Placesの写真には帰属表示が必要です。アプリ内ではおすすめカードとポスター下部にPhoto attributionを表示します。

## ビルド確認

```sh
xcodebuild -scheme CountdownPoster -project CountdownPoster.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0.1' build
```

## 参照した公式ドキュメント

- [Google Calendar API Events](https://developers.google.com/workspace/calendar/api/v3/reference/events)
- [Google OAuth 2.0 for Mobile & Desktop Apps](https://developers.google.com/identity/protocols/oauth2/native-app)
- [Google Places Text Search](https://developers.google.com/maps/documentation/places/web-service/text-search)
- [Google Place Photos](https://developers.google.com/maps/documentation/places/web-service/place-photos)
- [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
- [OpenAI Image generation](https://developers.openai.com/api/docs/guides/image-generation)
