# スプライト必要箇所 一覧

`tools/art_manifest.py` が `Main.gd` のデータ表から生成します。
敵やイベントを増やしたら再実行してください。手で編集しても次の
実行で消えます。チェック欄は実ファイルの有無を見ています。

```
python3 tools/art_manifest.py
```

**進捗: 0 / 87**

## 優先度の意味

| | 意味 |
| --- | --- |
| **P0** | 無いとプレイヤーにマゼンタのプレースホルダが見える。ここが商品の下限 |
| **P1** | 無くても既存の描画で成立するが、商品としては要る |
| **P2** | あると良い。無ければ静かに他のスロットへ落ちる |

## 規格

| 種別 | フォルダ | 形式 | 推奨サイズ |
| --- | --- | --- | --- |
| 立ち絵 | `art/stage/` | 縦長 / 透過PNG | 600 x 900 以上（2:3 〜 3:5） |
| 全画面CG | `art/cg/` | 16:9 / 不透過 | 1920 x 1080 |
| 背景 | `art/bg/` | 16:9 / 不透過 | 1920 x 1080 |
| マップ顔 | `art/face/` | 正方形 / 透過PNG | 256 x 256 |

連番（`_0`, `_1`, …）はアニメーションになります。番号は0から連続
している必要があり、抜けたところでクリップが終わります。

## P0 — これが無いと画面が壊れて見える　（0 / 22）

| | パス | 内容 |
| --- | --- | --- |
| [ ] | `art/stage/knight_idle.png` | 自機「剣士」の立ち絵・通常 |
| [ ] | `art/stage/stray_idle.png` | 「はぐれ兵」の立ち絵・通常 |
| [ ] | `art/stage/scout_idle.png` | 「斥候」の立ち絵・通常 |
| [ ] | `art/stage/archer_idle.png` | 「射手」の立ち絵・通常 |
| [ ] | `art/stage/heavy_idle.png` | 「重装」の立ち絵・通常 |
| [ ] | `art/stage/plague_idle.png` | 「疫病持ち」の立ち絵・通常 |
| [ ] | `art/stage/captain_idle.png` | 「隊長」の立ち絵・通常 |
| [ ] | `art/stage/boss_idle.png` | 「ボス」の立ち絵・通常 |
| [ ] | `art/cg/stray_win.png` | 「はぐれ兵」に勝利したときのCG |
| [ ] | `art/cg/stray_lose.png` | 「はぐれ兵」に敗北したときのCG |
| [ ] | `art/cg/scout_win.png` | 「斥候」に勝利したときのCG |
| [ ] | `art/cg/scout_lose.png` | 「斥候」に敗北したときのCG |
| [ ] | `art/cg/archer_win.png` | 「射手」に勝利したときのCG |
| [ ] | `art/cg/archer_lose.png` | 「射手」に敗北したときのCG |
| [ ] | `art/cg/heavy_win.png` | 「重装」に勝利したときのCG |
| [ ] | `art/cg/heavy_lose.png` | 「重装」に敗北したときのCG |
| [ ] | `art/cg/plague_win.png` | 「疫病持ち」に勝利したときのCG |
| [ ] | `art/cg/plague_lose.png` | 「疫病持ち」に敗北したときのCG |
| [ ] | `art/cg/captain_win.png` | 「隊長」に勝利したときのCG |
| [ ] | `art/cg/captain_lose.png` | 「隊長」に敗北したときのCG |
| [ ] | `art/cg/boss_win.png` | 「ボス」に勝利したときのCG |
| [ ] | `art/cg/boss_lose.png` | 「ボス」に敗北したときのCG |

## P1 — 商品として要る　（0 / 15）

| | パス | 内容 |
| --- | --- | --- |
| [ ] | `art/bg/scene_default.png` | 全画面の下地。**これ1枚で全画面をカバーする**ので最初に描く |
| [ ] | `art/bg/scene_title.png` | タイトルのキービジュアル。ストアと配信で最初に映る画面 |
| [ ] | `art/bg/scene_map.png` | ノードマップの背景 |
| [ ] | `art/bg/scene_battle.png` | 通常戦闘の背景 |
| [ ] | `art/stage/knight_hit_0.png` | 自機「剣士」被弾アニメ |
| [ ] | `art/stage/knight_hit_1.png` | 自機「剣士」被弾アニメ |
| [ ] | `art/stage/knight_hit_2.png` | 自機「剣士」被弾アニメ |
| [ ] | `art/stage/knight_hit_3.png` | 自機「剣士」被弾アニメ |
| [ ] | `art/face/stray_node.png` | 「はぐれ兵」のマップ顔 |
| [ ] | `art/face/scout_node.png` | 「斥候」のマップ顔 |
| [ ] | `art/face/archer_node.png` | 「射手」のマップ顔 |
| [ ] | `art/face/heavy_node.png` | 「重装」のマップ顔 |
| [ ] | `art/face/plague_node.png` | 「疫病持ち」のマップ顔 |
| [ ] | `art/face/captain_node.png` | 「隊長」のマップ顔 |
| [ ] | `art/face/boss_node.png` | 「ボス」のマップ顔 |

## P2 — あると良い　（0 / 50）

| | パス | 内容 |
| --- | --- | --- |
| [ ] | `art/bg/scene_rest.png` | 休憩ノードの背景 |
| [ ] | `art/bg/scene_shop.png` | 店ノードの背景 |
| [ ] | `art/bg/scene_event.png` | イベントノードの背景 |
| [ ] | `art/bg/scene_elite.png` | 強敵戦の背景（無ければ戦闘背景） |
| [ ] | `art/bg/scene_boss.png` | ボス戦の背景（無ければ戦闘背景） |
| [ ] | `art/bg/scene_gallery.png` | 回想画面の背景（無ければマップ背景） |
| [ ] | `art/stage/knight_down.png` | 自機「剣士」瀕死（HP35%以下） |
| [ ] | `art/stage/stray_hit_0.png` | 「はぐれ兵」被弾アニメ |
| [ ] | `art/stage/stray_hit_1.png` | 「はぐれ兵」被弾アニメ |
| [ ] | `art/stage/stray_hit_2.png` | 「はぐれ兵」被弾アニメ |
| [ ] | `art/stage/stray_hit_3.png` | 「はぐれ兵」被弾アニメ |
| [ ] | `art/stage/stray_down.png` | 「はぐれ兵」瀕死 |
| [ ] | `art/stage/scout_hit_0.png` | 「斥候」被弾アニメ |
| [ ] | `art/stage/scout_hit_1.png` | 「斥候」被弾アニメ |
| [ ] | `art/stage/scout_hit_2.png` | 「斥候」被弾アニメ |
| [ ] | `art/stage/scout_hit_3.png` | 「斥候」被弾アニメ |
| [ ] | `art/stage/scout_down.png` | 「斥候」瀕死 |
| [ ] | `art/stage/archer_hit_0.png` | 「射手」被弾アニメ |
| [ ] | `art/stage/archer_hit_1.png` | 「射手」被弾アニメ |
| [ ] | `art/stage/archer_hit_2.png` | 「射手」被弾アニメ |
| [ ] | `art/stage/archer_hit_3.png` | 「射手」被弾アニメ |
| [ ] | `art/stage/archer_down.png` | 「射手」瀕死 |
| [ ] | `art/stage/heavy_hit_0.png` | 「重装」被弾アニメ |
| [ ] | `art/stage/heavy_hit_1.png` | 「重装」被弾アニメ |
| [ ] | `art/stage/heavy_hit_2.png` | 「重装」被弾アニメ |
| [ ] | `art/stage/heavy_hit_3.png` | 「重装」被弾アニメ |
| [ ] | `art/stage/heavy_down.png` | 「重装」瀕死 |
| [ ] | `art/stage/plague_hit_0.png` | 「疫病持ち」被弾アニメ |
| [ ] | `art/stage/plague_hit_1.png` | 「疫病持ち」被弾アニメ |
| [ ] | `art/stage/plague_hit_2.png` | 「疫病持ち」被弾アニメ |
| [ ] | `art/stage/plague_hit_3.png` | 「疫病持ち」被弾アニメ |
| [ ] | `art/stage/plague_down.png` | 「疫病持ち」瀕死 |
| [ ] | `art/stage/captain_hit_0.png` | 「隊長」被弾アニメ |
| [ ] | `art/stage/captain_hit_1.png` | 「隊長」被弾アニメ |
| [ ] | `art/stage/captain_hit_2.png` | 「隊長」被弾アニメ |
| [ ] | `art/stage/captain_hit_3.png` | 「隊長」被弾アニメ |
| [ ] | `art/stage/captain_down.png` | 「隊長」瀕死 |
| [ ] | `art/stage/boss_hit_0.png` | 「ボス」被弾アニメ |
| [ ] | `art/stage/boss_hit_1.png` | 「ボス」被弾アニメ |
| [ ] | `art/stage/boss_hit_2.png` | 「ボス」被弾アニメ |
| [ ] | `art/stage/boss_hit_3.png` | 「ボス」被弾アニメ |
| [ ] | `art/stage/boss_down.png` | 「ボス」瀕死 |
| [ ] | `art/face/rest_node.png` | 休憩ノードのマップ顔 |
| [ ] | `art/face/shop_node.png` | 店ノードのマップ顔 |
| [ ] | `art/face/event_node.png` | イベントノードのマップ顔 |
| [ ] | `art/cg/shrine_scene.png` | イベント「打ち捨てられた祠」の挿絵 |
| [ ] | `art/cg/spring_scene.png` | イベント「湧き水」の挿絵 |
| [ ] | `art/cg/bargain_scene.png` | イベント「怪しい行商」の挿絵 |
| [ ] | `art/cg/cache_scene.png` | イベント「隠し袋」の挿絵 |
| [ ] | `art/cg/altar_scene.png` | イベント「血の祭壇」の挿絵 |

