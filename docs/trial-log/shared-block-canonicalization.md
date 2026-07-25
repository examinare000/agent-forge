# trial-log: エージェント共有ブロックの重複解消方式

範囲: agents/*.md 間で複製されている定型ブロック（報告規範・trial-log 義務・no-nesting 等）の重複をどう解消するかの方式選定と、その実装過程。個々のブロックの文言内容の議論は扱わない。

関連: ブランチ `feature/token-efficiency`

## 目的
agents/*.md に複製された共有ブロック（6/8 エージェントの報告規範ほか）の文言ドリフトを防ぎつつ、トークン量を削減する。

## 現在地
実装完了。`generators/check-agent-blocks.sh`（新規）が 6 ブロック × 24 対象ファイルのバイト一致包含を検査し、CI（`.github/workflows/ci.yml`）の generators selftest 直後に組み込み済み。agents/*.md 8 ファイル・skills/review-ai-antipattern/SKILL.md・skills/trial-log/SKILL.md への埋め込みと重複圧縮を実施し、`python3 generators/build.py` / `bash generators/selftest.sh` とも Green を確認済み。

## 棄却した案

### ビルド時パーシャル展開（agents/ を生成物化する）
- 内容: `{{include}}` 等で共有ブロックをビルド時に展開し、agents/*.md を build.py の生成物にする。
- 棄却理由（観測）: agents/ は installer が `~/.claude/agents/` へ直接 symlink する正本（`installer/manifest.json` linkEntries）。生成物化すると (1) installer の symlink 対象変更、(2) 編集フロー複雑化（テンプレート編集→ビルド→確認）、(3) CI の dist ドリフトチェックの agents/ への拡張、(4) `rules/hosts/claude/02` の降格手順（`sed` で `~/.claude/agents/` を直接書き換え）の破綻、という連鎖改修が必要になる。共有ブロックは高々 6 種 × 8 ファイル・変更頻度低で、機械展開の投資に見合わない。
- 再検討条件: エージェント数が大幅に増える、または共有ブロックの変更頻度が高くなった場合。

### 正準ブロックを agents/ 配下に置く案
- 棄却理由（観測）: agents/ ディレクトリは丸ごと `~/.claude/agents/` へ symlink されるため、ブロックファイルがエージェント定義として誤認識されうる。`generators/agent-blocks/` に置けば配布経路に乗らない。

## レビュー指摘と修正（ai-antipattern-reviewer → メイン転記）
- WARNING 1件: `agents/tdd-strict-coder.md` の Project Rules Compliance 圧縮時に「エージェント固有ルール（hosts/claude/01 等）は当該エージェントに最優先」の第三階層が脱落し、`rules/README.md` を正本と称するポインタが実体（README に当該規則なし）と不一致になっていた（Silent Code Drop）。原因はオーケストレータのブリーフに書いた圧縮文言自体の欠落（ワーカーは仕様どおり適用）。
- 修正: 同節に第三階層を1文で復元。`rules/README.md` 側への追記は本ブランチのスコープ外として見送り（README の優先順位節は 00 憲法と番号順のみを定めており、エージェント固有優先はエージェント定義側のローカル規則として保持する）。

## code-reviewer 指摘の処置（メイン転記）
- 🟠 ai-antipattern-reviewer の「修正は行わず」（正準ブロック）と出力フォーマットの「正しい実装」提示要求が自己矛盾 → 出力フォーマット節に「提示は指摘の一部、実ファイルへの適用をしないという意味」の注記を追加して整合（正準ブロック側は skill と共有のため触らない）。
- 🟠 check-agent-blocks.sh の回帰テスト欠如 → check-agent-blocks.test.sh を追加（別タスクで実装）。
- nit: tdd-strict-coder から rules/91 への参照が圧縮で消えた件は意図的削除として確定（91 の実質はオーケストレータ側手続きで、ワーカー自身の義務は本文に明記済みのため代替ポインタ不要）。

## adversarial-verifier REJECT の処置（メイン転記）
- (i) check-agent-blocks.test.sh の `sed -i ''` は BSD 専用で CI（ubuntu/GNU sed）では suffix 解釈により削除が空振りし偽 PASS になる（同じ知見は rules/hosts/claude/02 の降格手順注記に既出だった）→ python3 ワンライナーの行削除へ置換して両 OS 対応。
- (ii) ai-antipattern-reviewer への矛盾解消注記の後、dist/ 再生成を忘れており dist ドリフト状態だった → 正本ブロック検査（check-agent-blocks）は dist 再生成漏れを捕まえない。dist の番人は build.py 再実行 + `git diff --exit-code dist/`（CI 既存）のみ。**エージェント定義を 1 行でも触ったら build.py を回す**。
- (iii) trial-log 書き手ロスターの整合確認範囲に rules/94 の書き手記述（L27）が漏れていた → rules/94 を転記方式に修正。1行参照の書式と完了報告ポインタ契約は rules/30 から削った際に受け皿が無かったため Skill trial-log へ移設。
- (iv) tdd-strict-coder の Security 圧縮で resource bound が脱落 → 復元。
- (v) リポジトリ直下の未追跡 `.claude/agents/`（8 ファイル）は eval ラッパーのプローブ実行時の生成物と特定し削除（`eval-against-checkout.md` 参照）。
