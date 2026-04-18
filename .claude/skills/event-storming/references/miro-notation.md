# Miro記法（Event Storming）

Miro MCP の `mcp__claude_ai_Miro__diagram_create` で flowchart DSL を使って Event Storming 図を出力する。

---

## 基本原則

1. **図形は2種類のみ** — ホットスポット以外すべて `flowchart-process`（長方形）、ホットスポットのみ `flowchart-data`
2. **矢印はドメインイベント同士だけを結ぶ** — LR（横）レイアウトを維持するため
3. **クラスタはフェーズ単位**（BC単位ではない）
4. **左端に凡例クラスタを必ず入れる**
5. **レイアウトは自動配置に任せる**（Miro MCP は要素位置の微調整APIを持たない）

---

## 色マッピング（8要素）

Zenn記事（bitkey_dev）の慣例に準拠。

| 要素 | 色（fillColor） | 図形 |
|---|---|---|
| ドメインイベント | `#f8d3af` オレンジ | flowchart-process |
| コマンド | `#c6dcff` 青 | flowchart-process |
| 集約 | `#fff6b6` 黄 | flowchart-process |
| ポリシー | `#dedaff` 紫 | flowchart-process |
| リードモデル / ビュー | `#adf0c7` 緑 | flowchart-process |
| アクター | `#e7e7e7` グレー | flowchart-process |
| ビュー（参照情報） | `#ccf4ff` 水色 | flowchart-process |
| ホットスポット | `#ffc6c6` 赤 | **flowchart-data** |

ビューとリードモデルは厳密には同じ概念だが、Zenn記法では UI画面系を水色で分けて表現できる。使い分けは任意。

---

## クラスタ構成

### 凡例クラスタ（左端・必須）

図の読み手が最初に見る場所。全色と意味を列挙する。

```
凡例
  ├─ ドメインイベント（オレンジ）
  ├─ コマンド（青）
  ├─ 集約（黄）
  ├─ ポリシー（紫）
  ├─ リードモデル（緑）
  ├─ ビュー（水色）
  ├─ アクター（グレー）
  └─ ホットスポット（赤・八角形）
```

### フェーズクラスタ（本体）

業務フローの段階ごとにクラスタを作る。1 フェーズ = 1 クラスタ。

例（休暇申請フロー）:
```
[凡例] | [申請] → [承認] → [反映] → [集計]
```

各クラスタ内には、そのフェーズで登場するすべての要素（アクター、コマンド、集約、イベント、ポリシー、リードモデル、ホットスポット）を含める。

### BC の表現

BC 単位のクラスタは作らない。BC 名は各フェーズクラスタのタイトルに含める（例: 「申請（休暇管理BC）」）か、図の外の Markdown テーブルで補足する。

---

## 矢印ルール

- **つなぐのはドメインイベント同士のみ**（時系列を示す）
- 集約 → イベント、ポリシー → コマンド などの内部遷移は**矢印を引かない**（近接配置で意味を伝える）
- 各イベントは直前イベント1本、直後イベント1本の矢印のみ

**理由:** すべての要素を矢印で結ぶとレイアウトが崩れ、縦積みされて時系列が読めなくなる。イベント間矢印だけにすることで LR 配置を Miro に強制できる。

---

## diagram_create 呼び出しテンプレート

```
mcp__claude_ai_Miro__diagram_create(
  boardId: "<ユーザー指定のボードID>",
  nodes: [
    # --- 凡例クラスタ ---
    {id:"legend_event",    shape:"flowchart-process", text:"ドメインイベント", fillColor:"#f8d3af"},
    {id:"legend_command",  shape:"flowchart-process", text:"コマンド",         fillColor:"#c6dcff"},
    {id:"legend_aggregate",shape:"flowchart-process", text:"集約",             fillColor:"#fff6b6"},
    {id:"legend_policy",   shape:"flowchart-process", text:"ポリシー",         fillColor:"#dedaff"},
    {id:"legend_readmodel",shape:"flowchart-process", text:"リードモデル",     fillColor:"#adf0c7"},
    {id:"legend_view",     shape:"flowchart-process", text:"ビュー",           fillColor:"#ccf4ff"},
    {id:"legend_actor",    shape:"flowchart-process", text:"アクター",         fillColor:"#e7e7e7"},
    {id:"legend_hotspot",  shape:"flowchart-data",    text:"ホットスポット",   fillColor:"#ffc6c6"},

    # --- フェーズ1: 申請 ---
    {id:"actor_applicant", shape:"flowchart-process", text:"申請者",           fillColor:"#e7e7e7"},
    {id:"cmd_apply",       shape:"flowchart-process", text:"休暇を申請する",   fillColor:"#c6dcff"},
    {id:"agg_leave",       shape:"flowchart-process", text:"休暇申請",         fillColor:"#fff6b6"},
    {id:"ev_applied",      shape:"flowchart-process", text:"休暇が申請された", fillColor:"#f8d3af"},
    # ...

    # --- ホットスポット ---
    {id:"hs_1", shape:"flowchart-data", text:"⚠ 承認後の取り消し可否が未確定", fillColor:"#ffc6c6"}
  ],
  edges: [
    # ドメインイベント同士のみ接続
    {from:"ev_applied", to:"ev_approved"},
    {from:"ev_approved", to:"ev_reflected"},
    ...
  ],
  clusters: [
    {id:"cluster_legend", nodeIds:["legend_event","legend_command",...], title:"凡例"},
    {id:"cluster_apply",  nodeIds:["actor_applicant","cmd_apply","agg_leave","ev_applied"], title:"申請"},
    ...
  ]
)
```

> 上記は概念擬似コード。実際のパラメータ名は `mcp__claude_ai_Miro__diagram_create` の現行シグネチャに合わせて調整する。

---

## 命名規則（ノードID）

ノードIDは後続の edge で参照されるため、一貫した規則で付ける：

| 要素 | プレフィックス | 例 |
|---|---|---|
| アクター | `actor_` | `actor_applicant` |
| コマンド | `cmd_` | `cmd_apply` |
| 集約 | `agg_` | `agg_leave` |
| ドメインイベント | `ev_` | `ev_applied` |
| ポリシー | `pol_` | `pol_notify_attendance` |
| リードモデル | `rm_` | `rm_leave_balance` |
| ビュー | `view_` | `view_apply_form` |
| ホットスポット | `hs_` | `hs_1` |
| 凡例 | `legend_` | `legend_event` |

---

## 既存ボードとの共存

- 書き出す前に `mcp__claude_ai_Miro__context_get` / `board_list_items` で既存要素を把握する
- 新規 ES は既存要素と重ならない位置に自動配置される（レイアウトは自動のため明示的な座標指定は不要）
- 同じボードに複数回書き出す場合、ユーザーに**追記 / 新規作成**のどちらかを必ず確認する

---

## ユーザーへの完了報告（テンプレート）

```
Miroボードに Event Storming 図を書き出しました。

ボード: <Miro URL>
生成ノード数: <n>
凡例クラスタID: <id>
主要フェーズ: 申請 → 承認 → 反映 → 集計

ホットスポット:
- ⚠ <内容1>
- ⚠ <内容2>

DE/LEで意見が割れた論点:
- <論点>: <最終判断と根拠>
```
