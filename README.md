# QueensDomain Minimap（試作）

UE4SS用の、現在位置・向き・移動軌跡を画面右上に表示するLua MODです。

**実ゲームでの動作は未確認です。地形・壁・敵・アイテムは表示しません。**
添付されたゲーム本体の静的解析ではUE4.27系の識別子とHUD描画関数名を確認しましたが、
それだけでUE4SS対応やHUDフックの発火を保証することはできません。

## 0.2診断版への更新

UE4SS 4.0.0の実機ログで、MOD読み込みとエンジン側HUDイベントのフック登録まで成功していることを確認しました。描画完了ログはなく、描画イベント未発火か早期returnかは元のログでは区別できません。

ゲーム終了後、`QueensDomainMinimap/Scripts/main.lua`だけを最新版で上書きしてください。`geometry.lua`と`mods.txt`の変更は不要です。

0.2では開始時とClientRestart後に、ゲームスレッド上で存在するHUDを確認し、Blueprint側のReceiveDrawHUD実装が見つかれば追加フックします。HUDを新規生成したり、既存HUDの表示設定を変更したりはしません。実ゲームでの修正効果は未確認です。

セーブを読み込み、10秒ほど移動してからゲームを終了し、再度UE4SS.logを確認してください。

- `Build 0.2 loaded`: 最新版の読み込み
- `HUD inspection` / `HUD instance`: HUDの存在と種類
- `HUD event received`: 描画イベントの受信
- `Skipped:`: 描画を抜けた理由（同じ理由は1回だけ記録）
- `First HUD frame drawn`: 描画関数の呼び出しまで到達

追加したHUD探索・Blueprintフック登録・ゲームスレッドへの移譲は模擬APIで確認しています。実際のHUDがこのイベントを使わない場合には別の描画方式が必要です。

## 導入

1. ゲームを終了します。
2. [UE4SS公式リリース](https://github.com/UE4SS-RE/RE-UE4SS/releases)からWindows x64の安定版を取得し、公式の説明に従って`QueensDomain/Binaries/Win64`へ導入します。最上位のランチャーの場所ではありません。
3. UE4SS単体でゲームが起動することを確認します。
4. このリポジトリを **Code → Download ZIP** で取得して展開します。
5. `QueensDomainMinimap`フォルダーを、UE4SSが使用する`Mods`フォルダーにコピーします。
6. 同じ`Mods`内の既存`mods.txt`に、次の行を追記します。ファイル全体を置き換えないでください。

```text
QueensDomainMinimap : 1
```

標準的な構成例（UE4SSの配布形式により`Mods`の場所は異なります）：

```text
QueensDomain/Binaries/Win64/
└── ue4ss/
    └── Mods/
        ├── mods.txt
        └── QueensDomainMinimap/
            └── Scripts/
                ├── main.lua
                └── geometry.lua
```

ゲームを起動してセーブを読み込み、移動して確認してください。

## 表示と設定

- 画面右上に240pxの枠、向きを示す矢印、移動軌跡を表示します。
- +Xが右、+Yが上です。ゲーム内の北方向との一致は未確認です。
- 表示半径は6000 Unreal units（標準の縮尺なら60m）です。
- 高低差350 units以内の軌跡を表示します。階層を判定しているわけではありません。
- 最大1500点を保持します。古い点は消えます。
- 軌跡は保存しません。レベル変更、大きな移動、ゲーム終了で消えます。

`Scripts/main.lua`先頭の`config`でサイズ・半径・記録間隔・保持点数・高低差許容値を変更できます。編集後はゲームを再起動してください。

## 表示されない場合

`UE4SS.log`で`[QueensDomainMinimap]`を検索してください。

| ログ | 意味 |
| --- | --- |
| `HUD hook registered` | フック登録まで完了 |
| `First HUD frame drawn` | 有効なHUDで描画関数の呼び出しまで到達 |
| `HUD hook failed` / `Draw error` | 登録・描画時のエラー。後続の内容を確認 |

登録ログだけで描画ログが出なければ、このゲームが`ReceiveDrawHUD`を呼んでいない可能性があります。その場合はゲーム側HUDに合わせた別の方式が必要です。

描画エラーが3回発生するとMODの描画を停止します。ネイティブクラッシュをLuaのエラー処理で防ぐことはできません。

問題を報告する際は、UE4SSのバージョン、起動・セーブ読込・移動の結果、ログの本MOD関連行とその前後を添えてください。

## 検証状況

Luaのロード、座標変換、線の切り取り、初回描画、移動、テレポート・レベル変更時のリセットを模擬UE4SS APIで確認しました。
Windows上でのゲーム起動、UE4SSとの互換性、実際のHUD描画は未検証です。

## 削除

ゲーム終了後、`mods.txt`の該当行を削除するか値を`0`にし、`QueensDomainMinimap`フォルダーを削除します。
このMODのコードはゲームEXE、pak、セーブデータを書き換えません。

## 今後の開発

地形付きミニマップには、pak内のマップ構造やHUDアセットの調査が別途必要です。
ゲーム本体やアセット、UE4SS自体はこのリポジトリに含めていません。

参考：[UE4SS RegisterHook API](https://docs.ue4ss.com/lua-api/global-functions/registerhook.html)
