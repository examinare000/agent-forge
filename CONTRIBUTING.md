# 貢献ガイド

agent-forge への貢献を歓迎します。

## Issue・PR のガイドライン

- **日本語・英語**: どちらでも可
- **Issue**: バグ報告・機能リクエストは詳細な背景・再現方法を記載してください
- **PR**: 以下の条件を満たしてください
  - テストを含める（新機能・バグ修正の場合）
    - hooks: `.test.sh` で必須
    - 生成器: `selftest` で検証
  - コミットメッセージは日本語 1-2 文（WHY/WHAT を説明）
  - existing テストが pass すること

## テスト実行

```bash
# hooks のテスト
bash hooks/block-debug-log-residue.test.sh

# installer のテスト
bash installer/install.test.sh

# evals のテスト
bash evals/harness-selftest.sh
```

## 質問・議論

質問や設計上の議論は Issue で遠慮なく開始してください。背景や制約を共有することで、より良い提案につながります。
