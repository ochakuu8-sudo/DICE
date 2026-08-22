# スプライト必要箇所 一覧

`tools/art_manifest.py` が `Main.gd` のデータ表から生成します。
敵やイベントを増やしたら再実行してください。手で編集しても次の
実行で消えます。チェック欄は実ファイルの有無を見ています。

```
python3 tools/art_manifest.py
```

**進捗: 15 / 88**

## 優先度の意味

| | 意味 |
| --- | --- |
| **P0** | 無いとプレイヤーにマゼンタのプレースホルダが見える。ここが商品の下限 |
| **P1** | 無くても既存の描画で成立するが、商品としては要る |
| **P2** | あると良い。無ければ静かに他のスロットへ落ちる |

## 規格

| 種別 | フォルダ | 形式 | 推奨サイズ |
| --- | --- | --- | --- |
| 立ち絵 | `art/stage/` | 縦長 / 透過PNG | 800 x 1200（2:3） |
| 全画面CG | `art/cg/` | 16:9 / 不透過 | 1920 x 1080 |
| 背景 | `art/bg/` | 16:9 / 不透過 | 1920 x 1080 |
| マップ顔 | `art/face/` | 透過PNG / 中央帯のみ表示 | 256 x 256（主題は中央 256x200 に） |
| UI部品 | `art/ui/` | 透過PNG | 個別（PIPELINE.md 参照） |

連番（`_0`, `_1`, …）はアニメーションになります。番号は0から連続
している必要があり、抜けたところでクリップが終わります。

## P0 — これが無いと画面が壊れて見える　（8 / 8）

| | パス | 内容 |
| --- | --- | --- |
| [x] | `art/stage/shizuku_idle.png` | 自機「シズク」の立ち絵・通常 |
| [x] | `art/stage/stray_idle.png` | 「粘体」の立ち絵・通常 |
| [x] | `art/stage/scout_idle.png` | 「絡み蔦」の立ち絵・通常 |
| [x] | `art/stage/archer_idle.png` | 「灼眼」の立ち絵・通常 |
| [x] | `art/stage/heavy_idle.png` | 「擬態箱」の立ち絵・通常 |
| [x] | `art/stage/plague_idle.png` | 「胞子塊」の立ち絵・通常 |
| [x] | `art/stage/captain_idle.png` | 「贄喰い」の立ち絵・通常 |
| [x] | `art/stage/boss_idle.png` | 「深淵の主」の立ち絵・通常 |

## P1 — 商品として要る　（7 / 16）

| | パス | 内容 |
| --- | --- | --- |
| [ ] | `art/ui/logo_default.png` | タイトルロゴ。**ストアページの第一印象そのもの**。横長・透過PNG / 目安 900 x 260 |
| [ ] | `art/bg/scene_default.png` | 全画面の下地。**これ1枚で全画面をカバーする**ので最初に描く |
| [ ] | `art/bg/scene_title.png` | タイトルのキービジュアル。ストアと配信で最初に映る画面 |
| [ ] | `art/bg/scene_map.png` | ノードマップの背景 |
| [ ] | `art/bg/scene_battle.png` | 通常戦闘の背景 |
| [ ] | `art/stage/shizuku_hit_0.png` | 自機「シズク」被弾アニメ |
| [ ] | `art/stage/shizuku_hit_1.png` | 自機「シズク」被弾アニメ |
| [ ] | `art/stage/shizuku_hit_2.png` | 自機「シズク」被弾アニメ |
| [ ] | `art/stage/shizuku_hit_3.png` | 自機「シズク」被弾アニメ |
| [x] | `art/face/stray_node.png` | 「粘体」のマップ顔 |
| [x] | `art/face/scout_node.png` | 「絡み蔦」のマップ顔 |
| [x] | `art/face/archer_node.png` | 「灼眼」のマップ顔 |
| [x] | `art/face/heavy_node.png` | 「擬態箱」のマップ顔 |
| [x] | `art/face/plague_node.png` | 「胞子塊」のマップ顔 |
| [x] | `art/face/captain_node.png` | 「贄喰い」のマップ顔 |
| [x] | `art/face/boss_node.png` | 「深淵の主」のマップ顔 |

## P2 — あると良い　（0 / 64）

| | パス | 内容 |
| --- | --- | --- |
| [ ] | `art/bg/scene_rest.png` | 休憩ノードの背景 |
| [ ] | `art/bg/scene_shop.png` | 店ノードの背景 |
| [ ] | `art/bg/scene_event.png` | イベントノードの背景 |
| [ ] | `art/bg/scene_elite.png` | 強敵戦の背景（無ければ戦闘背景） |
| [ ] | `art/bg/scene_boss.png` | ボス戦の背景（無ければ戦闘背景） |
| [ ] | `art/bg/scene_gallery.png` | 回想画面の背景（無ければマップ背景） |
| [ ] | `art/stage/shizuku_down.png` | 自機「シズク」瀕死（HP35%以下） |
| [ ] | `art/cg/stray_win.png` | 「粘体」に勝利したときのCG |
| [ ] | `art/cg/stray_lose.png` | 「粘体」に敗北したときのCG |
| [ ] | `art/cg/scout_win.png` | 「絡み蔦」に勝利したときのCG |
| [ ] | `art/cg/scout_lose.png` | 「絡み蔦」に敗北したときのCG |
| [ ] | `art/cg/archer_win.png` | 「灼眼」に勝利したときのCG |
| [ ] | `art/cg/archer_lose.png` | 「灼眼」に敗北したときのCG |
| [ ] | `art/cg/heavy_win.png` | 「擬態箱」に勝利したときのCG |
| [ ] | `art/cg/heavy_lose.png` | 「擬態箱」に敗北したときのCG |
| [ ] | `art/cg/plague_win.png` | 「胞子塊」に勝利したときのCG |
| [ ] | `art/cg/plague_lose.png` | 「胞子塊」に敗北したときのCG |
| [ ] | `art/cg/captain_win.png` | 「贄喰い」に勝利したときのCG |
| [ ] | `art/cg/captain_lose.png` | 「贄喰い」に敗北したときのCG |
| [ ] | `art/cg/boss_win.png` | 「深淵の主」に勝利したときのCG |
| [ ] | `art/cg/boss_lose.png` | 「深淵の主」に敗北したときのCG |
| [ ] | `art/stage/stray_hit_0.png` | 「粘体」被弾アニメ |
| [ ] | `art/stage/stray_hit_1.png` | 「粘体」被弾アニメ |
| [ ] | `art/stage/stray_hit_2.png` | 「粘体」被弾アニメ |
| [ ] | `art/stage/stray_hit_3.png` | 「粘体」被弾アニメ |
| [ ] | `art/stage/stray_down.png` | 「粘体」瀕死（HP35%以下） |
| [ ] | `art/stage/scout_hit_0.png` | 「絡み蔦」被弾アニメ |
| [ ] | `art/stage/scout_hit_1.png` | 「絡み蔦」被弾アニメ |
| [ ] | `art/stage/scout_hit_2.png` | 「絡み蔦」被弾アニメ |
| [ ] | `art/stage/scout_hit_3.png` | 「絡み蔦」被弾アニメ |
| [ ] | `art/stage/scout_down.png` | 「絡み蔦」瀕死（HP35%以下） |
| [ ] | `art/stage/archer_hit_0.png` | 「灼眼」被弾アニメ |
| [ ] | `art/stage/archer_hit_1.png` | 「灼眼」被弾アニメ |
| [ ] | `art/stage/archer_hit_2.png` | 「灼眼」被弾アニメ |
| [ ] | `art/stage/archer_hit_3.png` | 「灼眼」被弾アニメ |
| [ ] | `art/stage/archer_down.png` | 「灼眼」瀕死（HP35%以下） |
| [ ] | `art/stage/heavy_hit_0.png` | 「擬態箱」被弾アニメ |
| [ ] | `art/stage/heavy_hit_1.png` | 「擬態箱」被弾アニメ |
| [ ] | `art/stage/heavy_hit_2.png` | 「擬態箱」被弾アニメ |
| [ ] | `art/stage/heavy_hit_3.png` | 「擬態箱」被弾アニメ |
| [ ] | `art/stage/heavy_down.png` | 「擬態箱」瀕死（HP35%以下） |
| [ ] | `art/stage/plague_hit_0.png` | 「胞子塊」被弾アニメ |
| [ ] | `art/stage/plague_hit_1.png` | 「胞子塊」被弾アニメ |
| [ ] | `art/stage/plague_hit_2.png` | 「胞子塊」被弾アニメ |
| [ ] | `art/stage/plague_hit_3.png` | 「胞子塊」被弾アニメ |
| [ ] | `art/stage/plague_down.png` | 「胞子塊」瀕死（HP35%以下） |
| [ ] | `art/stage/captain_hit_0.png` | 「贄喰い」被弾アニメ |
| [ ] | `art/stage/captain_hit_1.png` | 「贄喰い」被弾アニメ |
| [ ] | `art/stage/captain_hit_2.png` | 「贄喰い」被弾アニメ |
| [ ] | `art/stage/captain_hit_3.png` | 「贄喰い」被弾アニメ |
| [ ] | `art/stage/captain_down.png` | 「贄喰い」瀕死（HP35%以下） |
| [ ] | `art/stage/boss_hit_0.png` | 「深淵の主」被弾アニメ |
| [ ] | `art/stage/boss_hit_1.png` | 「深淵の主」被弾アニメ |
| [ ] | `art/stage/boss_hit_2.png` | 「深淵の主」被弾アニメ |
| [ ] | `art/stage/boss_hit_3.png` | 「深淵の主」被弾アニメ |
| [ ] | `art/stage/boss_down.png` | 「深淵の主」瀕死（HP35%以下） |
| [ ] | `art/face/rest_node.png` | 休憩ノードのマップ顔 |
| [ ] | `art/face/shop_node.png` | 店ノードのマップ顔 |
| [ ] | `art/face/event_node.png` | イベントノードのマップ顔 |
| [ ] | `art/cg/shrine_scene.png` | イベント「打ち捨てられた祠」の挿絵 |
| [ ] | `art/cg/spring_scene.png` | イベント「湧き水」の挿絵 |
| [ ] | `art/cg/bargain_scene.png` | イベント「怪しい行商」の挿絵 |
| [ ] | `art/cg/cache_scene.png` | イベント「隠し袋」の挿絵 |
| [ ] | `art/cg/altar_scene.png` | イベント「血の祭壇」の挿絵 |

