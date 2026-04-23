#!/bin/zsh
# 检查失败的分段

FAILED_SEGS=(7 52 59 82 124 208 237 347 357 408 425 473 491 504 543 549 564 567 596 668 674 678 707 712 719)
M3U8_BASE="https://events-delivery.apple.com/1208epinirnubocgyngedcvpuacuxred/vod_main_thyQUHMGRRKFgEaEVkDMKRbPKZstDPjTx"
WORK_DIR="./hls_download_temp"

echo "检查失败的分段..."
echo ""

for seg_num in "${FAILED_SEGS[@]}"; do
    FILE="$WORK_DIR/video/sdr_avc_1080p_8500_${seg_num}.m4s"
    URL="$M3U8_BASE/sdr_avc_1080p_8500/sdr_avc_1080p_8500_${seg_num}.m4s"
    
    if [[ -f "$FILE" ]]; then
        SIZE=$(stat -f%z "$FILE" 2>/dev/null || echo 0)
        echo "分段 $seg_num: 文件存在，大小 $SIZE 字节"
        
        if [[ $SIZE -lt 100000 ]]; then
            echo "  -> 文件太小，尝试手动下载..."
            curl -I "$URL" 2>&1 | head -5
        fi
    else
        echo "分段 $seg_num: 文件不存在"
        echo "  -> 检查 URL..."
        curl -I "$URL" 2>&1 | head -5
    fi
    echo ""
done
