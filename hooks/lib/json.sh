#!/usr/bin/env bash
# フック共通の JSON 抽出。判定不能時に衛生ゲートを閉じないため、壊れた入力や
# パーサ異常は常に空文字列へ倒し、非ゼロを返さない。
#
# python3 経路は既存契約との互換性のため bool を Python の str() 表記
# （True / False）で出力する。jq 経路の true / false とは大文字小文字が異なる。

json_tools_available() {
  command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1
}

json_field() {
  local json="${1:-}" path="${2:-}"

  if command -v jq >/dev/null 2>&1; then
    # jq はストリーミング動作のため「正しい JSON の後ろにゴミ」の入力でも
    # 先頭ドキュメントの値を出力してから失敗する（部分値の漏れ）。python3 経路
    # （json.load = 全体が正しくなければ例外）と挙動を揃えるため、先に全体の
    # 妥当性を検査し、不正なら空へ倒す。
    if ! printf '%s' "$json" | jq -e . >/dev/null 2>&1; then
      return 0
    fi
    printf '%s' "$json" | jq -r ".${path} // empty" 2>/dev/null || true
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$json" | python3 -c '
import json
import sys

try:
    value = json.load(sys.stdin)
    for key in sys.argv[1].split("."):
        value = value.get(key)
    print("" if value is None else value)
except Exception:
    print("")
' "$path" 2>/dev/null || true
  fi

  return 0
}
