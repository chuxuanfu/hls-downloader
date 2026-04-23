#!/bin/zsh
# Apple Event HLS 视频下载器 - 完整版
# 使用经过验证的可靠方法

set -e

# ========== 配置区域 ==========
M3U8_BASE="https://events-delivery.apple.com/1208epinirnubocgyngedcvpuacuxred/vod_main_thyQUHMGRRKFgEaEVkDMKRbPKZstDPjTx"
OUTPUT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="$OUTPUT_DIR/hls_download_temp"
FINAL_OUTPUT="$OUTPUT_DIR/apple_event_complete.mp4"

VIDEO_STREAM="sdr_avc_1080p_8500"  # 1080p H.264
AUDIO_STREAM="audio_main_en_2ch_aac_128"  # AAC 128k

MIN_VIDEO_SIZE=100000  # 视频分段最小100KB
MIN_AUDIO_SIZE=10000   # 音频分段最小10KB

# ========== 参数解析 ==========
MAX_SEGS=99999  # 默认下载全部
TEST_MODE=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --test)
            MAX_SEGS=100
            TEST_MODE=1
            FINAL_OUTPUT="$OUTPUT_DIR/apple_event_test_10min.mp4"
            echo "🧪 测试模式：只下载前10分钟"
            shift
            ;;
        --segments)
            MAX_SEGS=$2
            shift 2
            ;;
        *)
            echo "未知参数: $1"
            echo "用法: $0 [--test] [--segments N]"
            exit 1
            ;;
    esac
done

# ========== 函数定义 ==========
download_with_validation() {
    local url="$1"
    local output="$2"
    local min_size=$3
    local max_retries=5
    
    for ((retry=1; retry<=max_retries; retry++)); do
        if curl -sS -f -m 30 -o "$output" "$url" 2>/dev/null; then
            if [[ -f "$output" ]]; then
                local size=$(stat -f%z "$output" 2>/dev/null || echo 0)
                if [[ $size -ge $min_size ]]; then
                    return 0
                else
                    rm -f "$output"
                    [[ $retry -lt $max_retries ]] && sleep 1
                fi
            fi
        else
            [[ $retry -lt $max_retries ]] && sleep 1
        fi
    done
    
    return 1
}

# ========== 主程序 ==========
mkdir -p "$WORK_DIR"/{video,audio}

echo "╔════════════════════════════════════════════════╗"
echo "║  Apple Event HLS 视频下载器                   ║"
echo "╚════════════════════════════════════════════════╝"
echo ""
[[ $TEST_MODE -eq 1 ]] && echo "🧪 测试模式：下载前 10 分钟" || echo "📹 完整模式：下载全部视频"
echo ""

# ========== Step 1: 获取分段列表 ==========
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Step 1/5: 获取分段列表"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

curl -sS "$M3U8_BASE/$VIDEO_STREAM/prog_index.m3u8" > "$WORK_DIR/video.m3u8"
curl -sS "$M3U8_BASE/$AUDIO_STREAM/prog_index.m3u8" > "$WORK_DIR/audio.m3u8"

VIDEO_INIT=$(grep 'EXT-X-MAP:URI=' "$WORK_DIR/video.m3u8" | sed 's/.*URI="\(.*\)"/\1/')
AUDIO_INIT=$(grep 'EXT-X-MAP:URI=' "$WORK_DIR/audio.m3u8" | sed 's/.*URI="\(.*\)"/\1/')

if [[ $MAX_SEGS -eq 99999 ]]; then
    VIDEO_SEGS=($(grep '\.m4s' "$WORK_DIR/video.m3u8"))
    AUDIO_SEGS=($(grep '\.m4s' "$WORK_DIR/audio.m3u8"))
else
    VIDEO_SEGS=($(grep '\.m4s' "$WORK_DIR/video.m3u8" | head -$MAX_SEGS))
    AUDIO_SEGS=($(grep '\.m4s' "$WORK_DIR/audio.m3u8" | head -$MAX_SEGS))
fi

TOTAL_MINUTES=$(( ${#VIDEO_SEGS[@]} * 6 / 60 ))
echo "  ✅ 视频: ${#VIDEO_SEGS[@]} 个分段 (~$TOTAL_MINUTES 分钟)"
echo "  ✅ 音频: ${#AUDIO_SEGS[@]} 个分段"
echo ""

# ========== Step 2: 下载初始化文件 ==========
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Step 2/5: 下载初始化文件"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ ! -f "$WORK_DIR/video/init.mp4" ]]; then
    curl -sS -f -o "$WORK_DIR/video/init.mp4" "$M3U8_BASE/$VIDEO_STREAM/$VIDEO_INIT"
    echo "  ✅ Video init: $(du -h "$WORK_DIR/video/init.mp4" | cut -f1)"
else
    echo "  ✅ Video init 已存在"
fi

if [[ ! -f "$WORK_DIR/audio/init.mp4" ]]; then
    curl -sS -f -o "$WORK_DIR/audio/init.mp4" "$M3U8_BASE/$AUDIO_STREAM/$AUDIO_INIT"
    echo "  ✅ Audio init: $(du -h "$WORK_DIR/audio/init.mp4" | cut -f1)"
else
    echo "  ✅ Audio init 已存在"
fi
echo ""

# ========== Step 3: 下载视频分段 ==========
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📹 Step 3/5: 下载视频分段（带验证和重试）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

COUNT=0
SUCCESS=0
FAILED=0
SKIPPED=0

for seg in "${VIDEO_SEGS[@]}"; do
    COUNT=$((COUNT + 1))
    PCT=$(( COUNT * 100 / ${#VIDEO_SEGS[@]} ))
    
    # 检查是否已存在且有效
    if [[ -f "$WORK_DIR/video/$seg" ]]; then
        SIZE=$(stat -f%z "$WORK_DIR/video/$seg" 2>/dev/null || echo 0)
        if [[ $SIZE -ge $MIN_VIDEO_SIZE ]]; then
            SKIPPED=$((SKIPPED + 1))
            printf "\r  [%3d%%] %d/%d (成功:%d 跳过:%d 失败:%d)" \
                $PCT $COUNT ${#VIDEO_SEGS[@]} $SUCCESS $SKIPPED $FAILED
            continue
        fi
    fi
    
    printf "\r  [%3d%%] %d/%d (成功:%d 跳过:%d 失败:%d)" \
        $PCT $COUNT ${#VIDEO_SEGS[@]} $SUCCESS $SKIPPED $FAILED
    
    if download_with_validation \
        "$M3U8_BASE/$VIDEO_STREAM/$seg" \
        "$WORK_DIR/video/$seg" \
        $MIN_VIDEO_SIZE; then
        SUCCESS=$((SUCCESS + 1))
    else
        FAILED=$((FAILED + 1))
        printf "\n  ⚠️  第 %d 个分段失败: %s\n" $COUNT $seg
    fi
    
    if (( COUNT % 10 == 0 )); then
        SIZE=$(du -sh "$WORK_DIR/video" | cut -f1)
        printf "\r  [%3d%%] %d/%d - 已下载: %s (成功:%d 跳过:%d 失败:%d)\n" \
            $PCT $COUNT ${#VIDEO_SEGS[@]} $SIZE $SUCCESS $SKIPPED $FAILED
    fi
    
    sleep 0.1
done

echo ""
echo ""
TOTAL_VIDEO_OK=$((SUCCESS + SKIPPED))
echo "  📊 视频下载统计："
echo "     成功: $SUCCESS 个"
echo "     跳过: $SKIPPED 个（已存在）"
echo "     失败: $FAILED 个"
echo "     总计: $TOTAL_VIDEO_OK / ${#VIDEO_SEGS[@]}"

if [[ $FAILED -gt 50 ]]; then
    echo ""
    echo "  ❌ 失败太多（$FAILED 个，超过7%），建议："
    echo "     1. 检查网络连接"
    echo "     2. 重新运行脚本（会自动跳过已下载的）"
    exit 1
elif [[ $FAILED -gt 0 ]]; then
    echo "  ⚠️  有 $FAILED 个分段失败，视频会有少量跳帧但可以观看。建议先运行 ./fix_failed_segments.sh 修复"
fi
echo ""

# ========== Step 4: 下载音频分段 ==========
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔊 Step 4/5: 下载音频分段"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

COUNT=0
SUCCESS=0
FAILED=0
SKIPPED=0

for seg in "${AUDIO_SEGS[@]}"; do
    COUNT=$((COUNT + 1))
    PCT=$(( COUNT * 100 / ${#AUDIO_SEGS[@]} ))
    
    if [[ -f "$WORK_DIR/audio/$seg" ]]; then
        SIZE=$(stat -f%z "$WORK_DIR/audio/$seg" 2>/dev/null || echo 0)
        if [[ $SIZE -ge $MIN_AUDIO_SIZE ]]; then
            SKIPPED=$((SKIPPED + 1))
            printf "\r  [%3d%%] %d/%d" $PCT $COUNT ${#AUDIO_SEGS[@]}
            continue
        fi
    fi
    
    printf "\r  [%3d%%] %d/%d" $PCT $COUNT ${#AUDIO_SEGS[@]}
    
    if download_with_validation \
        "$M3U8_BASE/$AUDIO_STREAM/$seg" \
        "$WORK_DIR/audio/$seg" \
        $MIN_AUDIO_SIZE; then
        SUCCESS=$((SUCCESS + 1))
    else
        FAILED=$((FAILED + 1))
    fi
    
    if (( COUNT % 10 == 0 )); then
        SIZE=$(du -sh "$WORK_DIR/audio" | cut -f1)
        printf "\r  [%3d%%] %d/%d - 已下载: %s\n" $PCT $COUNT ${#AUDIO_SEGS[@]} $SIZE
    fi
    
    sleep 0.1
done

echo ""
echo ""
echo "  📊 音频下载统计："
echo "     成功: $SUCCESS 个"
echo "     跳过: $SKIPPED 个"
echo "     失败: $FAILED 个"
echo ""

# ========== Step 5: 拼接视频 ==========
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔨 Step 5/5: 拼接视频"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

MERGED_V="$WORK_DIR/merged_video.mp4"
MERGED_A="$WORK_DIR/merged_audio.m4a"

echo "  📹 拼接视频分段..."
cat "$WORK_DIR/video/init.mp4" > "$MERGED_V"
CONCAT_COUNT=0
for seg in "${VIDEO_SEGS[@]}"; do
    F="$WORK_DIR/video/$seg"
    if [[ -f "$F" ]]; then
        SIZE=$(stat -f%z "$F" 2>/dev/null || echo 0)
        if [[ $SIZE -ge $MIN_VIDEO_SIZE ]]; then
            cat "$F" >> "$MERGED_V"
            CONCAT_COUNT=$((CONCAT_COUNT + 1))
        fi
    fi
done
echo "     拼接了 $CONCAT_COUNT 个视频分段 -> $(du -h "$MERGED_V" | cut -f1)"

echo "  🔊 拼接音频分段..."
cat "$WORK_DIR/audio/init.mp4" > "$MERGED_A"
CONCAT_COUNT=0
for seg in "${AUDIO_SEGS[@]}"; do
    F="$WORK_DIR/audio/$seg"
    if [[ -f "$F" && -s "$F" ]]; then
        cat "$F" >> "$MERGED_A"
        CONCAT_COUNT=$((CONCAT_COUNT + 1))
    fi
done
echo "     拼接了 $CONCAT_COUNT 个音频分段 -> $(du -h "$MERGED_A" | cut -f1)"

echo ""
echo "  🎬 合并视频+音频..."
ffmpeg -y -hide_banner -loglevel error \
    -i "$MERGED_V" \
    -i "$MERGED_A" \
    -map 0:v -map 1:a \
    -c copy \
    -movflags +faststart \
    "$FINAL_OUTPUT"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "╔════════════════════════════════════════════════╗"
echo "║  ✅ 下载完成！                                 ║"
echo "╚════════════════════════════════════════════════╝"
echo ""
echo "📁 输出文件: $FINAL_OUTPUT"
echo "📦 文件大小: $(du -h "$FINAL_OUTPUT" | cut -f1)"
echo ""

# ========== 验证 ==========
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 验证视频完整性"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

V_DUR=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$FINAL_OUTPUT" 2>/dev/null)
A_DUR=$(ffprobe -v error -select_streams a:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$FINAL_OUTPUT" 2>/dev/null)
TOTAL_DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$FINAL_OUTPUT" 2>/dev/null)

V_MIN=$(printf "%.1f" $(echo "$V_DUR / 60" | bc -l))
A_MIN=$(printf "%.1f" $(echo "$A_DUR / 60" | bc -l))
TOTAL_MIN=$(printf "%.1f" $(echo "$TOTAL_DUR / 60" | bc -l))

echo "  总时长:   ${TOTAL_MIN} 分钟"
echo "  视频流:   ${V_MIN} 分钟"
echo "  音频流:   ${A_MIN} 分钟"
echo ""

DIFF=$(echo "$TOTAL_DUR - $V_DUR" | bc | tr -d '-')
DIFF_INT=$(printf "%.0f" $DIFF)

if (( DIFF_INT < 5 )); then
    echo "╔════════════════════════════════════════════════╗"
    echo "║  ✅✅✅ 成功！视频完整，没有黑屏问题！         ║"
    echo "╚════════════════════════════════════════════════╝"
else
    echo "⚠️  警告：视频流时长和总时长差异 ${DIFF_INT} 秒"
    echo "   可能在 ${V_MIN} 分钟后出现黑屏"
    echo ""
    echo "建议："
    echo "  1. 重新运行脚本补充下载"
    echo "  2. 检查失败的分段"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
