# DevinUsageBar

Devin CLI のクォータ使用量を macOS メニューバーに表示する小さなアプリ。

`⚡ D:100% W:50%` のように、Daily / Weekly クォータの残り%を 60 秒ごとに更新します。
メニューを開くと、リセット時刻・Overage 残高・プラン終了日などを表示します。

## データ取得の仕組み

- `devin` CLI が内部的に使っている `SeatManagementService/GetUserStatus` RPC
  (`https://server.codeium.com/...`) を直接叩く。`devin auth status` と同じ API。
- 認証は `~/.local/share/devin/credentials.toml` の `windsurf_api_key` を
  実行時に読み込むだけ。キーはコード・リポジトリに一切含めない。

## ビルド・実行

```sh
./build.sh          # swiftc でコンパイル → DevinUsageBar.app
open DevinUsageBar.app
```

再ビルドしても Info.plist は残るのでビルドは1行です。

## ログイン時に自動起動

```sh
osascript -e 'tell application "System Events" to make login item at end with properties {path:"<abs path>/DevinUsageBar.app", hidden:false}'
```

## 要件

- macOS 13+ (Swift 6 でビルド確認)
- `devin` CLI でログイン済みであること (`devin auth status` が通ること)
