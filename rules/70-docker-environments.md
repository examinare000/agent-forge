---
# `.claude/rules/docker.md` から symlink され、Docker/Compose/infra のファイル操作時に自動ロードされる（native path-scoped rule）。
paths:
  - "**/Dockerfile"
  - "**/*compose*.yml"
  - "**/*compose*.yaml"
  - "infra/**"
---

# 70. Docker環境管理

## 規約＆標準
- **ファイル・コマンド**: `compose.yml` (Compose V2) を使用。`docker compose` コマンドを使用（`version:` フィールド不要）。
- **compose.yml標準構造**:
```yaml
services:
  app:
    image: node:18-alpine
    ports: ["3000:3000"]
    env_file: [.env]
    volumes: [".:/app", "app_cache:/app/.cache"]
    working_dir: /app
    depends_on: [db]
  db:
    image: postgres:15-alpine
    volumes: ["db_data:/var/lib/postgresql/data"]
volumes:
  db_data:
  app_cache:
```

## Dockerfile 要件
1. **非root実行**: `USER` 指定必須。
2. **軽量化**: マルチステージビルドの採用。
3. **キャッシュ最適化**: 依存定義コピーとソースコードコピーを分離。
4. **ポート明示**: `EXPOSE` 必須。

## 開発フロー・トラブルシューティング
- **フロー**: 起動 (`docker compose up -d`) / ログ (`docker compose logs -f`) / 実行 (`docker compose exec app <cmd>`) / リセット (`docker compose down -v`)
- **プロファイル**: `docker compose --profile test run --rm test` でテスト/リンターを分離。
- **トラブル対応**: 競合 (`lsof -i :<port>`) / 権限 (`chown` / `USER`) / 再構築 (`docker compose build --no-cache`)

---
**適用優先度**: 🟠 高
