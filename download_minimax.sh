#!/bin/bash

# ============================================
# MiniMax H3 モデル自動ダウンロードスクリプト
# PinkCherry beta-0.6-fl2va 対応版
# ============================================

set -e

# ========== 設定部分 ==========
BASE_DIR="/workspace/runpod-slim/ComfyUI/models"
HF_TOKEN=""                            # 必要ならトークンを入れる

# ダウンロードリスト（URL | 保存先相対パス | ファイル名）
declare -a DOWNLOADS=(
  # Diffusion Model（PinkCherry beta-0.6）
  "https://huggingface.co/SexGod1979/PinkCherry_MiniMax-H3/resolve/main/beta-0.6-fl2va/PinkCherry_fl2va_MiniMax_H3_int8_convrot-beta-0.6.safetensors|diffusion_models|PinkCherry_fl2va_MiniMax_H3_int8_convrot-beta-0.6.safetensors"

  # Text Encoder（必要に応じて変更可）
  "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors|text_encoders|qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"

  # VAE
  "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_video_vae_fp16.safetensors|vae|minimax_h3_video_vae_fp16.safetensors"
  "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_audio_vae_fp32.safetensors|vae|minimax_h3_audio_vae_fp32.safetensors"
)

# aria2c 設定
CONNECTIONS=16
MAX_TRIES=0
RETRY_WAIT=10
# ==============================

echo "===== MiniMax H3 自動ダウンロード開始 ====="
echo "ベースディレクトリ: $BASE_DIR"
echo ""

# 1. aria2c のインストール確認・インストール
if ! command -v aria2c &> /dev/null; then
    echo "[INFO] aria2c が見つかりません。インストールします..."
    apt-get update -qq
    apt-get install -y -qq aria2
    echo "[OK] aria2c インストール完了"
else
    echo "[OK] aria2c は既にインストール済み"
fi

# 2. ディレクトリ作成
mkdir -p "$BASE_DIR"/{text_encoders,vae,diffusion_models,loras}

# 3. ダウンロード関数（失敗しても自動再開）
download_file() {
    local url="$1"
    local subdir="$2"
    local filename="$3"
    local dest_dir="$BASE_DIR/$subdir"
    local dest_path="$dest_dir/$filename"

    mkdir -p "$dest_dir"

    # 既に存在してある程度のサイズがあればスキップ
    if [ -f "$dest_path" ] && [ $(stat -c%s "$dest_path" 2>/dev/null || echo 0) -gt 1000000 ]; then
        echo "[SKIP] 既に存在: $filename"
        return 0
    fi

    echo "[DOWNLOAD] $filename を開始..."
    
    local header_opt=""
    if [ -n "$HF_TOKEN" ]; then
        header_opt="--header=Authorization: Bearer $HF_TOKEN"
    fi

    while true; do
        if aria2c -c \
            -x $CONNECTIONS \
            -s $CONNECTIONS \
            -k 1M \
            --max-tries=$MAX_TRIES \
            --retry-wait=$RETRY_WAIT \
            --file-allocation=none \
            --console-log-level=notice \
            --summary-interval=10 \
            $header_opt \
            -d "$dest_dir" \
            -o "$filename" \
            "$url"; then
            echo "[SUCCESS] $filename ダウンロード完了"
            break
        else
            echo "[WARN] $filename 失敗。${RETRY_WAIT}秒後に再開します..."
            sleep $RETRY_WAIT
        fi
    done
}

# 4. 全ファイルを順次ダウンロード
for item in "${DOWNLOADS[@]}"; do
    IFS='|' read -r url subdir filename <<< "$item"
    download_file "$url" "$subdir" "$filename"
done

echo ""
echo "===== 全てのダウンロードが完了しました ====="
echo "保存先: $BASE_DIR"
echo "  - diffusion_models/"
echo "  - text_encoders/"
echo "  - vae/"
