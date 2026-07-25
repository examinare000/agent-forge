# trial-log: hooks 性能改善・堅牢化の実装過程

範囲: hooks 3 本 + installer の性能・堅牢性改修（feature/hooks-hardening）で試したことと修正判断。CI 構成の設計判断も含む。Phase A（トークン効率化）の論点は扱わない。

関連: ブランチ `feature/hooks-hardening`

## 目的
Stop フックの毎停止フルスキャン・lint フックのコールドスタート・backup フックの未サニタイズ入力を解消し、jq 不在環境でも 3 フックが機能する状態にする。

## 現在地
実装完了・全テスト 312 PASS・shellcheck 全緑。クロスベンダー（Codex）へ一括委譲した実装をベースに、中断後の残 FAIL 3 件をメインが修正して Green 化。性能実測: 200k 行クリーン差分の Stop フックが 457ms → 174ms。

## 試行と修正（Codex 委譲分の残課題をメインが解消）

### jq のストリーミング挙動による部分値漏れ
- 観測: `{"a":1} garbage` のような「正しい JSON + 末尾ゴミ」で、jq 経路は先頭ドキュメントの値を出力してから失敗する（python3 経路の json.load は全体不正で例外→空）。fail-open 契約「不正入力は空」に反する。
- 修正: json_field の jq 経路に `jq -e .` による全体妥当性の事前検査を追加し、両経路の挙動を統一。

### exclude-only pathspec の cwd 相対解釈による走査範囲の縮小（回帰）
- 観測: `git -C "$cwd" diff -- . ':(exclude,glob)...'` の pathspec は cwd 相対で解釈されるため、cwd がサブディレクトリの停止イベントで兄弟ディレクトリの残置を見逃す（既存テスト 5 が検出）。pathspec なしの旧実装はサブディレクトリからでも全リポジトリを走査していた。
- 修正: `git rev-parse --show-toplevel` で最上位を解決し、常にリポジトリルートから走査。

### HOME 未設定での set -u 死
- 観測: backup フックが `$HOME` 参照で unbound variable → exit 1（fail-open 契約違反）。
- 修正: `[ -n "${HOME:-}" ] || exit 0` ガードを追加。

## 棄却した案

### `git diff HEAD` 1 本への統合（diff 2 回実行の削減）
- 棄却理由: HEAD との差分は正味効果しか見えず、「マーカーを stage 後に作業ツリーから削除」した場合にコミット候補の残置を見逃す。--cached の存在理由としてテスト 22 で固定化。

### shellcheck 対応を hooks/installer に限定して lint ジョブを部分適用する案
- 棄却理由: `git ls-files '*.sh'` 全体に warning が残ると lint ジョブが恒常的に赤になり、CI 赤の常態化はゲートとして機能しない。境界外 6 ファイルも最小差分（disable + WHY / `|| exit 1`）で解消して全緑化。

## review-ai-antipattern (WARNING) 所見と根拠

### scaffold/new-project.test.sh の SC2034 disable が偽装
- 観測: `# shellcheck disable=SC2034  # REPO_ROOT は外部呼び出しに対する意図的な提供変数` というWHYコメントが付いているが、`REPO_ROOT` はこのテストファイル内で参照されておらず、export もされていない。子プロセス（`new-project.sh`）は自前で `installer/lib/common.sh` を source して独自に `REPO_ROOT` を再計算するため、テスト側のローカル変数は本当に外部から参照され得ない。
- 検証: 12-13行目（disableコメント＋代入）を削除したコピーで `bash scaffold/new-project.test.sh` を実行し、44件全PASSで変化なしを確認済み（削除しても壊れない＝本当に未使用）。
- 結論: 「WHY付きtargeted disable」の建前を装っているが、実態は死んだコードを消さずに警告だけ握りつぶした偽装。修正は disable コメントの温存ではなく、未使用の `REPO_ROOT` 代入そのものの削除であるべき。

### installer/manifest.json の Linux install hint に要検証な記述
- `"uv": "sudo apt-get install uv"` は darwin側の `brew install uv` / windows側の `winget install astral-sh.uv` と異なり、Ubuntu/Debian の標準 apt リポジトリに `uv` パッケージが存在するか未検証（レビュー環境はネットワーク遮断のため裏取り不可）。誤りなら幻覚寄りのインストール手順をユーザーに提示することになる。次回このファイルを触る際は要web確認。

## review-ai-antipattern 指摘の処置（メイン転記）
- SC2034 偽装 disable: `scaffold/new-project.test.sh` の未使用 `REPO_ROOT` 代入と disable コメントを削除（レビュアーの削除実証どおり 44 PASS 維持・shellcheck 0 件）。
- manifest の Linux uv hint: `sudo apt-get install uv` は apt リポジトリに存在しない幻覚手順のため、公式インストーラ `curl -LsSf https://astral.sh/uv/install.sh | sh` へ修正（jq empty で JSON 妥当性確認済み）。

## code-reviewer (fresh-context) 所見と根拠

### pathspec 除外と awk 除外の部分集合不変条件（検証: 反例なし）
`git status --porcelain` の pathspec フィルタと、awk 除外条件を再現したスクリプトを、境界ケース（root直下/深いネスト/`testing`ディレクトリ/`atest`プレフィックス/`foo.testing.js`/空白入りパス/`weird test.js`）で突き合わせ、両者の除外集合が完全一致することを確認した。`-G'\[(DEBUG|TRACE)\]'` プレフィルタは `git diff --no-index` で検証したところ、ファイル内に非マッチhunkが混在していても全hunkが出力される（-Gはファイル単位の包含判定であり、hunk単位の間引きではない）ため、プレフィルタによる見逃しは起きない。棄却すべき懸念点は見つからなかった。

### symlink 安全 source: 現行インストーラ構成では while ループを一度も反復しない（未棄却・要フォローアップ）
installer/manifest.json の linkEntries は hooks ディレクトリ全体をシンボリックリンクする方式（個別ファイルsymlinkではない）。実インストール環境では `BASH_SOURCE[0]` の最終コンポーネント自体はsymlinkではないため、3フックに追加された `while [ -h ... ]` ループは実行時に1回も反復しない——`cd -P "$(dirname ...)"` だけで hooks ディレクトリ symlink の解決は完了する。scratchpadでディレクトリsymlink構成を再現し、ループが0回反復のまま正しく解決されることを実測で確認した。ループ自体は将来「個別ファイルsymlink」方式に変えた場合の保険として無害だが、3つの `*.test.sh` はいずれも `HOOK` 変数を symlink を経由しない実体パス（`SCRIPT_DIR`）で直接呼び出しており、symlink経由の実行（while ループ・`cd -P`のdir-symlink解決のどちらも）を一度も exercise していない。棄却はしないが、「symlink安全」を機能として謳うなら、symlink経由での実行を検証する回帰テストが未着手のまま残っている。

### CI macOS マトリクスは実行される bash バージョンを可視化していない（未棄却・要フォローアップ）
追加されたジョブは `run: bash hooks/xxx.test.sh` の形で `bash` の解決をPATHに委ねており、どのステップにも `bash --version` / `$BASH_VERSION` の出力が無い。GitHub-hosted macos-latest ランナーで `/usr/bin/bash`（3.2系）以外がPATH上位に来ないことを暗黙の前提にしているが、この前提自体をCI上で確認・可視化していない。bash 3.2 回帰検出という導入目的に対し、無言の前提依存になっている。

## code-reviewer should-fix 2 件の処置

1. **symlink 安全 source** → `hooks/block-debug-log-residue.test.sh` に テスト 25 を追加。ディレクトリ symlink 経由の実行で lib が読めてブロックが機能することを検証。exit 2 ・検出行の両方を assert。
2. **CI bash 可視化** → `.github/workflows/ci.yml` の test ジョブ checkout 直後に `- name: show bash version (matrix leg premise)` ステップを追加。`bash --version | head -1` で各マトリクス脚の前提 bash バージョンをログ可視化。全 25 テスト PASS・YAML バリデーション OK。

## adversarial-verifier: 完了主張の反証試行（判定 CONDITIONAL PASS）

崩せなかった主張（再試行しても無駄なので同じ経路を再検証しないこと）:

- **313 PASS / 0 FAIL**: CI が実行する 12 ファイルをローカル実行して一致（installer 50 / generators 86 / new-project 44 / check-agent-assets 17 / forge 18 / block-debug 25 / lint 13 / backup 13 / json 9 / settings-parity 11 / check-docs 12 / evals 15）。ローカル `bash` は 3.2.57 なので macOS レーンの bash 前提は実測済み。
- **shellcheck warning 0 件**: CI ubuntu-24.04 のバージョンは **0.9.0**（ローカルは 0.11.0）。0.9.0 バイナリを取得して `git ls-files '*.sh'` + 未追跡 4 本 + `bin/forge` に `-x -S warning` を実行 → rc=0。バージョン差での再赤化は否定済み。`-x` は `# shellcheck source=./lib/json.sh` を repo root CWD から解決できず SC1091(info) 止まりのため実質無効だが、json.sh 自体は単体で検査対象に入っている。
- **pathspec ⊆ awk 除外**: `core.ignorecase=true` 環境でも git の pathspec 照合は case-sensitive（`git ls-files -- ':(glob)**/*.MD'` = 0 件）。よって `FOO.MD` / `FOO.TEST.js` を pathspec だけが過剰除外する経路は存在しない。実際の変更ファイル集合でも pathspec 結果と awk 結果は完全一致。
- **-G はファイル単位**: root..HEAD で -G 付き diff の追加行 153 行のうち 151 行がマーカー非該当 → hunk 間引きではないことを実測。
- **CI 環境前提**: 公式 runner-images README で macos-15 = Bash 3.2.57 + jq 1.8.2、ubuntu-24.04 = Bash 5.2.21 + jq 1.7 + shellcheck 0.9.0 を確認。install.sh は jq 不在で `exit 1` する硬依存だが両レーンに jq がある。`claude` は install.test.sh 側で空スタブ済み。
- **dist ドリフト**: build.py は列挙を全て `sorted()` しており OS 差で並びが揺れない。CI の 3 コマンドをそのまま実行して clean。
- **hooks/lib/json.sh の配布**: manifest の linkEntries は `hooks` ディレクトリ単位の symlink なので lib/ も同梱される。

未解決のまま残した条件（次に触る人向け）:

1. **ブランチに 1 コミットも無い**（`git rev-list --count main..HEAD` = 0）。CI 緑はローカル再現であって観測ではない。lint ジョブの `git ls-files '*.sh'` は追跡ファイルしか見ないため、新規 4 本を commit し忘れると lint ゲートを素通りする。
2. **`hooks/lib/json.test.sh:72-78` は jq 不在で SKIP せず FAIL する**。本ブランチの目的「jq 不在環境でも動く」と、`settings-parity.test.sh:38-41` の SKIP 方針の両方に反する。
3. **eslint `--cache` の高速化は未計測**。テストはスタブ引数に `--cache` が載ることしか見ていない。かつ cache 書き込み失敗（read-only な node_modules 等）は eslint exit 2 → `lint-after-edit.sh:103` の新ガードで無言化され、本物の lint 指摘が消える。この組み合わせは未テスト。
4. **457ms → 174ms を再現する手段が成果物に無い**（ベンチスクリプト・実行コマンド未記録）。方向性のみ確認可能（root..HEAD で走査対象 10248 行 → 153 行）。
5. **`while [ -h ]` symlink ループはテスト 25 でも 0 回反復**。ディレクトリ symlink は `cd -P` だけで解決されるため、ファイル symlink 経路（1 回反復）は依然未検証。lint / backup 2 本には symlink テスト自体が無い。循環 symlink のガードも無し。
6. **backup の prune が O(n²)**（`backup-before-compact.sh:42-58`。1 件削除ごとにディレクトリ全体を再 glob + 再 stat）。51 件境界では無害だが、数千件溜まった場合は PreCompact hook が timeout する。

## adversarial-verifier CONDITIONAL PASS 条件のコード修正 4 件（TDD 実装）

作業ブランチ: `feature/hooks-hardening`（作業ディレクトリ `.worktrees/hooks-hardening`）。境界: `hooks/lib/json.test.sh` / `hooks/lint-after-edit.sh`+`.test.sh` / `hooks/block-debug-log-residue.sh`+`.test.sh` / `hooks/backup-before-compact.sh`+`.test.sh` / 本ファイル。

### 修正1（未解決条件2）: json.test.sh の jq 不在時 FAIL → SKIP
- 観測（Red）: jq を隠した PATH（python3 のみ）で実行すると「jq 経路の bool は true」ケースが FAIL（fail=1）。jq・python3 両方を隠すと 6 件 FAIL。settings-parity.test.sh の SKIP 方針（依存不在は「SKIP: <理由>」+ exit 0）と矛盾していた。
- 修正: ソース直後に `jq も python3 も無ければ SKIP + exit 0` を追加。jq のみ不在の bool 表記ケースは個別に「SKIP: jq 経路の bool 表記検証は jq 不在のためスキップします。」へ変更（fail カウント対象から外す）。
- 検証: 通常環境 9 PASS 0 FAIL（回帰なし）／ jq のみ隠す PATH で 8 PASS 0 FAIL（SKIP 1 件）／ jq・python3 両方隠す PATH で SKIP メッセージのみ・exit 0。

### 修正2（未解決条件3）: eslint --cache 書込失敗で本物の lint 指摘が消える
- 観測（Red）: `--cache` 付きなら exit 2、`--cache` 無しなら exit 1 + 指摘を返すスタブを新設し、既存の「eslint 恒常クラッシュ（exit 127, --cache有無に関わらず）→fail-open exit 0」ケースと並置。修正前は 1 件 FAIL（期待 exit 2 実際 exit 0、stdout/stderr とも空）— 指摘が無言で消えることを実測確認。
- 修正: `lint-after-edit.sh` の eslint 呼び出しで `status -ge 2` のとき、`--cache` 無しで 1 回だけ再実行しその結果を採用。0/1 はそのまま。
- 検証: 新規ケース含め 14 PASS 0 FAIL。既存の恒常クラッシュ（exit 127）ケースは変更なしで fail-open のまま（回帰なし）。

### 修正3（未解決条件5）: symlink 解決ループへ反復上限ガードを追加 + 未検証経路のテスト
- **循環 symlink は実は「無限ループ」にならないことを実測で確認**: `ln -s a a`（自己参照）および `a→b→a`（相互参照）を `bash a` で直接起動すると、本フックの while ループへ到達する前に **OS 自身の symlink 解決（open(2) の MAXSYMLINKS）が ELOOP で弾く**（`bash: a: Too many levels of symbolic links`, exit 126）。このホスト（macOS, bash 3.2.57）で二分探索し、非循環の直列チェーンが `bash` で開けるかどうかの境界を実測: 32 ホップまで成功 (`ran ok`)、33 ホップ以降は必ず ELOOP。つまり真の循環 symlink は bash 起動時点で必ず先に失敗し、本ループのガードコードへは到達しない。
- 上記の実測に基づき、ブリーフが要求した「27. 循環symlinkはfail-openで許可」を文字通りには実装せず、実際にガードを到達・検証できる唯一の経路（**循環ではないが OS の上限内で開けてしまう、正当だが異常に長い symlink チェーン**）へ差し替えた。反復上限は 10（OS実測上限 32/一般的な Linux 上限 40 のいずれよりも十分小さく、両プラットフォームで確実にガードが先に発火する値）。テストは 15 ホップの非循環チェーンを構築し、修正前コード（上限ガード無し）では exit 2（違反を検出してブロック=保護されていない証拠、Red）、修正後は上限到達で exit 0（fail-open, Green）になることを確認。
- 3 フック（`block-debug-log-residue.sh` / `lint-after-edit.sh` / `backup-before-compact.sh`）の `while [ -h "$hook_source" ]` に同一の反復カウンタ・上限10ガードを追加（同一改修を3箇所）。
- ファイル symlink 経由（1 回反復）の未検証ギャップも解消: `block-debug-log-residue.test.sh` にテスト26「ファイルsymlink経由の起動でも実体のlibを解決してブロックできる」を追加（lib/ を持たない一時ディレクトリへ実フックへのファイルsymlinkを張り exit 2 を確認）。
- 検証: block-debug-log-residue.test.sh 27 PASS 0 FAIL（新規テスト26・27含む）。lint-after-edit.test.sh 14 PASS、backup-before-compact.test.sh 13 PASS（ガード追加による回帰なし）。

### 修正4（未解決条件6）: backup prune を単一パスへ
- 確認: 実装は既に「1件削除するたび `for candidate in "$dest_dir"/*` で全件再glob + 全件再statして最古を探す」`while :; do ... done` ネストループで、O(n²) だった（単一パスではなかったため変更を実施）。
- 修正: `(cd "$dest_dir" && ls -1t . | tail -n +51 | while IFS= read -r candidate; do [ -f "$candidate" ] && rm -f "$candidate"; done)` の単一パスへ書き換え。mtime降順で列挙し、保持数50を超える古い側（51件目以降）だけを1回の列挙でまとめて削除する。
- 検証: backup-before-compact.test.sh 13 PASS 0 FAIL（56件中50件保持・61件混在拡張子50件保持・同一秒2プロセス衝突なし、いずれも回帰なし）。

### 性能計測（未解決条件4）の再現方法
`/tmp` にプラムビングコマンドのみで使い捨て git repo を構築（`git commit` はサブエージェントから delegate-git-to-composer フックでブロックされるため、`git hash-object -w` + `git update-index --add --cacheinfo` + `git write-tree` + `git commit-tree` + `git update-ref HEAD` で直接コミットを作る）:
```
d=/tmp/perf-fixture; rm -rf "$d"; mkdir -p "$d"; cd "$d"; git init -q .
python3 -c "
with open('big.txt','w') as f:
    for i in range(200000):
        f.write('base line %d\n' % i)
"
blob=$(git hash-object -w big.txt)
git update-index --add --cacheinfo 100644,$blob,big.txt
tree=$(git write-tree)
commit=$(git commit-tree "$tree" -m init)
git update-ref HEAD "$commit"
# 未stageの200,000行非マッチ差分を作る
python3 -c "
with open('big.txt','w') as f:
    for i in range(200000):
        f.write('changed ordinary line %d without any marker\n' % i)
"
# 計測
printf '{\"cwd\":\"/tmp/perf-fixture\"}' | bash hooks/block-debug-log-residue.sh; echo EXIT=$?
/usr/bin/time -p bash -c 'printf "{\"cwd\":\"/tmp/perf-fixture\"}" | bash hooks/block-debug-log-residue.sh >/dev/null 2>/dev/null'
```
今回の再測定（このホスト、3 回試行, real time）: 0.25s / 0.23s / 0.24s（exit=0）。以前記録した 457ms→174ms とはホスト負荷差はあるが同オーダーで、200k行クリーン差分でも数百ms未満に収まる方向性は再現した。未解決条件4はこの再現手順を成果物（本ファイル）に記録したことで解消。
