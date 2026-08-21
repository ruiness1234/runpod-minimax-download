#!/bin/bash

# ============================================
# ComfyUI 設定・ワークフロー 復元スクリプト
# バックアップ (backup_comfyui.sh) の対になる復元用
# ============================================
#
# 【RunPod Webターミナルでの実行方法】
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/ruiness1234/runpod-minimax/main/restore_comfyui.sh)
#   またはローカルに置いて:
#   bash restore_comfyui.sh
#
# 【動作】
#   1. /workspace/backup 内の comfyui_snapshot_YYYYMMDD_HHMMSS.tar.gz から
#      ファイル名の日付が最新のものを自動選択
#   2. 配置先 (COMFYUI_ROOT) に既に環境がある場合は、
#      削除してバックアップから戻すか確認してから実行
#   3. 解凍して元の位置に配置
#
# 【注意】
#   - 重いモデルファイル (.safetensors 等) はバックアップに含まれていないため、
#     既存の models/ 内のモデル本体は削除しません
#   - モデルは download_minimax.sh 等で別途再取得してください
#
# ============================================

set -e

# ========== 設定部分 ==========
COMFYUI_ROOT="/workspace/runpod-slim/ComfyUI"
BACKUP_DIR="/workspace/backup"

# バックアップで対象にしていた主なパス（復元時の存在チェック・上書き対象）
RESTORE_TARGETS=(
  "user"
  "custom_nodes"
  "input"
  "web"
  "comfy"
  "comfy_extras"
  "script_examples"
  "output"
  "extra_model_paths.yaml"
  "extra_model_paths.yaml.example"
  "config.ini"
  "config.json"
  "manager_config.ini"
  ".env"
  "requirements.txt"
  "requirements_versions.txt"
  "README.md"
)

# models は構造・軽量ファイルのみ復元（既存の重いモデルは残す）
# ==============================

echo "===== ComfyUI 設定・ワークフロー 復元 ====="
echo "ComfyUI ルート: $COMFYUI_ROOT"
echo "バックアップディレクトリ: $BACKUP_DIR"
echo ""

# ---------- 最新スナップショットを探す ----------
if [ ! -d "$BACKUP_DIR" ]; then
  echo "[ERROR] バックアップディレクトリがありません: $BACKUP_DIR"
  exit 1
fi

# comfyui_snapshot_YYYYMMDD_HHMMSS.tar.gz を日付順（新しい順）で列挙
mapfile -t SNAPSHOTS < <(
  find "$BACKUP_DIR" -maxdepth 1 -type f -name 'comfyui_snapshot_*.tar.gz' 2>/dev/null \
    | sort -r
)

if [ ${#SNAPSHOTS[@]} -eq 0 ]; then
  echo "[ERROR] バックアップが見つかりません。"
  echo "        パターン: ${BACKUP_DIR}/comfyui_snapshot_YYYYMMDD_HHMMSS.tar.gz"
  exit 1
fi

echo "見つかったスナップショット（新しい順）:"
for i in "${!SNAPSHOTS[@]}"; do
  f="${SNAPSHOTS[$i]}"
  base=$(basename "$f")
  size=$(stat -c%s "$f" 2>/dev/null || echo 0)
  human=$(numfmt --to=iec-i --suffix=B "$size" 2>/dev/null || echo "${size} bytes")
  # ファイル名から日付部分を抽出
  if [[ "$base" =~ comfyui_snapshot_([0-9]{8}_[0-9]{6})\.tar\.gz ]]; then
    ts="${BASH_REMATCH[1]}"
    # 表示用に整形 (YYYY-MM-DD HH:MM:SS)
    pretty="${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:9:2}:${ts:11:2}:${ts:13:2}"
  else
    pretty="?"
  fi
  marker=""
  [ "$i" -eq 0 ] && marker=" ← 最新（復元対象）"
  echo "  $((i+1))) $base  ($pretty, $human)$marker"
done
echo ""

LATEST="${SNAPSHOTS[0]}"
LATEST_BASE=$(basename "$LATEST")
echo "復元に使用するアーカイブ: $LATEST"
echo ""

# ---------- 配置先の状態を確認 ----------
EXISTING=()
if [ -d "$COMFYUI_ROOT" ]; then
  for t in "${RESTORE_TARGETS[@]}"; do
    if [ -e "${COMFYUI_ROOT}/${t}" ]; then
      EXISTING+=("$t")
    fi
  done
  # models ディレクトリ自体がある場合も「環境あり」とみなす
  if [ -d "${COMFYUI_ROOT}/models" ]; then
    EXISTING+=("models (構造のみ復元・既存モデルは保持)")
  fi
fi

if [ ${#EXISTING[@]} -gt 0 ]; then
  echo "【警告】配置先に既に環境が存在します:"
  for e in "${EXISTING[@]}"; do
    echo "  - $e"
  done
  echo ""
  echo "バックアップから復元すると、上記のうちバックアップに含まれる項目は"
  echo "削除されたうえで上書きされます。"
  echo "（models/ 内の .safetensors 等の重いモデルファイルは削除しません）"
  echo ""
  read -p "削除してバックアップから戻しますか？ [y/N]: " CONFIRM
  echo ""
  if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
    echo "キャンセルしました。何も変更していません。"
    exit 0
  fi
else
  echo "配置先に復元対象の既存環境はほぼありません。そのまま展開します。"
  echo ""
  if [ ! -d "$COMFYUI_ROOT" ]; then
    echo "[INFO] ComfyUI ルートが存在しないため作成します: $COMFYUI_ROOT"
    mkdir -p "$COMFYUI_ROOT"
  fi
fi

# ---------- 一時ディレクトリに解凍 ----------
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "----- アーカイブを解凍中 -----"
tar -xzf "$LATEST" -C "$TMP_DIR"

# 解凍後のトップディレクトリ（comfyui_snapshot_YYYYMMDD_HHMMSS）
EXTRACTED=$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)
if [ -z "$EXTRACTED" ] || [ ! -d "$EXTRACTED" ]; then
  echo "[ERROR] アーカイブの中身が想定と異なります。"
  exit 1
fi

echo "解凍先（一時）: $EXTRACTED"
if [ -f "${EXTRACTED}/BACKUP_INFO.txt" ]; then
  echo ""
  echo "----- バックアップ情報 -----"
  cat "${EXTRACTED}/BACKUP_INFO.txt"
  echo "----------------------------"
  echo ""
fi

# ---------- 復元実行 ----------
echo "----- 復元を実行中 -----"

mkdir -p "$COMFYUI_ROOT"

# スナップショット内の各エントリを処理
shopt -s nullglob dotglob
for item in "$EXTRACTED"/*; do
  name=$(basename "$item")

  # メタ情報はコピーするが必須ではない
  if [ "$name" = "BACKUP_INFO.txt" ]; then
    cp -a "$item" "${COMFYUI_ROOT}/BACKUP_INFO_RESTORED.txt" 2>/dev/null || true
    echo "[INFO] BACKUP_INFO.txt → BACKUP_INFO_RESTORED.txt として保存"
    continue
  fi

  dest="${COMFYUI_ROOT}/${name}"

  if [ -d "$item" ]; then
    # ディレクトリの場合
    if [ "$name" = "models" ]; then
      # models: 既存の重いモデルを消さない。構造と軽量ファイルのみマージ
      echo "[RESTORE] models/ （既存モデルを保持しつつ構造・軽量ファイルを反映）"
      mkdir -p "$dest"
      # ディレクトリ構造
      find "$item" -type d | while read -r d; do
        rel="${d#${item}/}"
        [ -z "$rel" ] && continue
        mkdir -p "${dest}/${rel}"
      done
      # ファイルは上書きコピー（バックアップには軽量ファイルのみ）
      find "$item" -type f | while read -r f; do
        rel="${f#${item}/}"
        mkdir -p "${dest}/$(dirname "$rel")"
        cp -a "$f" "${dest}/${rel}"
      done
    else
      # 通常ディレクトリ: 既存があれば削除してからコピー
      if [ -e "$dest" ]; then
        echo "[DELETE] 既存を削除: $name"
        rm -rf "$dest"
      fi
      echo "[RESTORE] $name/"
      cp -a "$item" "$dest"
    fi
  else
    # 単一ファイル
    if [ -e "$dest" ]; then
      echo "[DELETE] 既存ファイルを削除: $name"
      rm -f "$dest"
    fi
    echo "[RESTORE] $name"
    cp -a "$item" "$dest"
  fi
done
shopt -u nullglob dotglob

echo ""
echo "===== 復元完了 ====="
echo "使用したバックアップ: $LATEST_BASE"
echo "配置先:               $COMFYUI_ROOT"
echo ""
echo "【次のステップ】"
echo "  - モデル本体が必要な場合は download_minimax.sh 等で再ダウンロードしてください"
echo "  - custom_nodes に依存パッケージがある場合は、必要に応じて各ノードの"
echo "    requirements をインストールしてください"
echo "  - ComfyUI を再起動して動作を確認してください"
echo ""
