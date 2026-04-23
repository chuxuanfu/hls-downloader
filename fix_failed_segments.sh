#!/bin/zsh
# 专门修复失败的分段

FAILED_SEGS=(7 52 59 82 124 208 237 347 357 408 425 473 491 504 543 549 564 567 596 668 674 678 707 712 719)
M3U8_BASE="https://events-delivery.apple.com/1208epinirnubocgyngedcvpuacuxred/vod_main_thyQUHMGRRKFgEaEVkDMKRbPKZstDPjTx"
WORK_DIR="./hls_download_temp"
MIN_SIZE=100000

echo "╔════════════════════════════════════════════════╗"
echo "║  修复失败的分段                               ║"
echo "╚════════════════════════════════════════════════╝"
echo ""

SUCCESS=0
FAILED=0

for seg_num in "${FAILED_SEGS[@]}"; do
    FILE="$WORK_DIR/video/sdr_avc_1080p_8500_${seg_num}.m4s"
    URL="$M3U8_BASE/sdr_avc_1080p_8500/sdr_avc_1080p_8500_${seg_num}.m4s"
    
    echo -n "修复分段 $seg_num ... "
    
    # 删除旧的小文件
    [[ -f "$FILE" ]] && rm -f "$FILE"
    
    # 使用更强的下载参数
    if curl -L -f --retry 10 --retry-delay 2 --max-time 60 \
        -H "User-Agent: Mozilla/5.0" \
        -o "$FILE" "$URL" 2>/dev/null; then
        
        SIZE=$(stat -f%z "$FILE" 2>/dev/null || echo 0)
        if [[ $SIZE -ge $MIN_SIZE ]]; then
            echo "✅ 成功 ($(echo "scale=1; $SIZE/1024/1024" | bc)MB)"
            SUCCESS=$((SUCCESS + 1))
        else
            echo "❌ 失败 (只有 $SIZE 字节)"
            FAILED=$((FAILED + 1))
            rm -f "$FILE"
        fi
    else
        echo "❌ 下载失败"
        FAILED=$((FAILED + 1))
    fi
    
    sleep 0.5
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "结果："
echo "  成功: $SUCCESS 个"
echo "  失败: $FAILED 个"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo "✅ 全部修复成功！现在可以继续运行 ./download_apple_video.sh"
else
    echo "⚠️  还有 $FAILED 个分段失败"
    echo "   这些分段可能在拼接时被跳过，视频会有轻微跳帧"
    echo "   但不会影响整体播放"
fi
