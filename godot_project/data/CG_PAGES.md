# CGページ編集

本文とページ順は `cg_pages.json` だけを編集します。各CGのキーは回想カタログのIDと一致させてください。

```json
"fatigue_end_stray": {
  "pages": [
    {
      "image": "res://art/cg/fatigue_end_stray_01.png",
      "name": "",
      "text": "ナレーション本文"
    },
    {
      "image": "res://art/cg/fatigue_end_stray_02.png",
      "name": "粘体",
      "text": "話者名付きの本文"
    }
  ]
}
```

- `pages` の順番が再生順です。要素を追加・削除してページ数を調整できます。
- `image` は各ページで別の `res://art/cg/` 内の画像へ設定できます。未配置なら画面に「CG画像未設定」と出ます。
- `name` は空文字ならナレーションになり、名前欄を表示しません。
- `text` はページ単位で自由な長さにできます。読みやすさの目安は2〜4文です。
