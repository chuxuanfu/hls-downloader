#!/bin/zsh
# 视频验证工具

if [[ $# -lt 1 ]]; then
    echo "用法: $0 <video_file>"
    exit 1
fi

VIDEO="$1"

if [[ ! -f "$VIDEO" ]]; then
    echo "❌ 文件不存在: $VIDEO"
    exit 1
fi

echo "╔════════════════════════════════════════════════╗"
echo "║  视频验证工具                                 ║"
echo "╚════════════════════════════════════════════════╝"
echo ""
echo "文件: $VIDEO"
echo "大小: $(du -h "$VIDEO" | cut -f1)"
echo ""

# 获取流信息
V_DUR=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO" 2>/dev/null)
A_DUR=$(ffprobe -v error -select_streams a:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO" 2>/dev/null)
TOTAL_DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO" 2>/dev/null)

V_MIN=$(printf "%.1f" $(echo "$V_DUR / 60" | bc -l))
A_MIN=$(printf "%.1f" $(echo "$A_DUR / 60" | bc -l))
TOTAL_MIN=$(printf "%.1f" $(echo "$TOTAL_DUR / 60" | bc -l))

echo "时长信息:"
echo "  总时长: ${TOTAL_MIN} 分钟 (${TOTAL_DUR} 秒)"
echo "  视频流: ${V_MIN} 分钟 (${V_DUR} 秒)"
echo "  音频流: ${A_MIN} 分钟 (${A_DUR} 秒)"
echo ""

# 检查差异
DIFF=$(echo "$TOTAL_DUR - $V_DUR" | bc | tr -d '-')
DIFF_INT=$(printf "%.0f" $DIFF)

if (( DIFF_INT < 5 )); then
    echo "✅ 视频完整！时长匹配，没有黑屏问题"
else
    echo "❌ 问题：视频流和总时长不匹配"
    echo "   差异: ${DIFF_INT} 秒"
    echo "   可能在 ${V_MIN} 分钟后出现黑屏"
fi

echo ""
echo "详细流信息:"
ffprobe -v error -show_entries stream=index,codec_type,codec_name,width,height,duration \
    -of default=noprint_wrappers=1 "$VIDEO" 2>/dev/null
