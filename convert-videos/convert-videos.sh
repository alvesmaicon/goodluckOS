#!/bin/bash
# Converts the videos in this script's folder (or a folder given to it) for the goodluckOS Videos tab. See README.md.

# What the A33 plays smoothly in software (README: up to 640x480 H.264); icons only need the launcher's preview
max_w=640; max_h=480; icon_w=320; icon_h=240
turn=clock
out_name=goodluckOS-videos
# the Videos tab's extensions (apps.puppy), plus camera ones
video_exts=' mp4 mkv avi webm mov m4v mpg mpeg wmv flv 3gp ts mts m2ts '
sidecar_exts=' srt ass ssa vtt sub idx '
# embedded subtitles Matroska keeps as they are, or as SRT; others are dropped
sub_codecs='subrip=copy ass=copy ssa=copy hdmv_pgs_subtitle=copy dvd_subtitle=copy dvb_subtitle=copy mov_text=srt webvtt=srt text=srt'

shopt -s nocasematch
case ${LC_ALL:-${LC_MESSAGES:-$LANG}} in pt*) pt=1 ;; *) pt= ;; esac
if [ -t 1 ]; then red=$'\033[31m'; green=$'\033[32m'; yellow=$'\033[33m'; cyan=$'\033[36m'; gray=$'\033[90m'; off=$'\033[0m'; fi
say() { if [ -n "$pt" ]; then printf '%s%s%s\n' "$1" "$3" "$off"; else printf '%s%s%s\n' "$1" "$2" "$off"; fi; }

if ! command -v ffmpeg >/dev/null || ! command -v ffprobe >/dev/null; then
    if [ "$(uname)" = Darwin ]; then how='brew install ffmpeg'; else how='sudo apt install ffmpeg'; fi
    say "$red" "ffmpeg not found. Install it with \"$how\", then run this again." "ffmpeg não encontrado. Instale com \"$how\" e rode de novo."
    exit 1
fi
dir=${1:-$(dirname "$0")}
if [ ! -d "$dir" ]; then
    say "$red" "Not a folder: $dir" "Não é uma pasta: $dir"
    exit 1
fi
dir=$(cd "$dir" && pwd)
out_root=$dir/$out_name

has_ext() { [[ $2 == *" ${1##*.} "* ]]; }

videos_in() {
    vids=()
    local f
    for f in "$1"/*; do
        [ -f "$f" ] && has_ext "$f" "$video_exts" && vids+=("$f")
    done
}

# From ffprobe's flat output: the filters (display size with pixel aspect and rotation applied, deinterlacing,
# frame rate cap, portrait turned), the icon's size, where to take it, the length and the subtitles to keep
probe_awk='
function fit(w, h, mw, mh,   s) {
    s = mw / w; if (mh / h < s) s = mh / h; if (s > 1) s = 1
    fw = 2 * int(w * s / 2 + 0.5); fh = 2 * int(h * s / 2 + 0.5)
    if (fw < 2) fw = 2; if (fh < 2) fh = 2
}
{ i = index($0, "="); key = substr($0, 1, i - 1); val = substr($0, i + 1); gsub(/"/, "", val) }
key == "format.duration" { dur = val + 0 }
key ~ /^streams\.stream\.[0-9]+\./ {
    split(key, k, "."); s = k[3]; f = key; sub(/^streams\.stream\.[0-9]+\./, "", f)
    if (f ~ /rotation$/) f = "rotation"
    st[s, f] = val; if (!(s in seen)) { seen[s] = 1; order[n++] = s }
}
END {
    v = ""
    for (j = 0; j < n; j++) {
        s = order[j]
        if (st[s, "codec_type"] == "video" && st[s, "disposition.attached_pic"] != "1" && st[s, "width"] + 0 > 0) { v = s; break }
    }
    if (v == "") exit 1
    w = st[v, "width"] + 0; h = st[v, "height"] + 0
    if (split(st[v, "sample_aspect_ratio"], a, ":") == 2 && a[1] + 0 > 0 && a[2] + 0 > 0) w = w * a[1] / a[2]
    r = st[v, "rotation"] + 0; if (r < 0) r = -r
    if (r % 180 == 90) { t = w; w = h; h = t }
    fit(w, h, iconw, iconh); icon = "scale=" fw ":" fh
    vf = ""
    if (st[v, "field_order"] ~ /^(tt|bb|tb|bt)$/) vf = vf "bwdif=0,"
    # 50/60 fps halved: twice the frames to decode
    if (split(st[v, "avg_frame_rate"], q, "/") == 2 && q[1] + 0 > 0 && q[2] + 0 > 0) {
        num = q[1] + 0; den = q[2] + 0
        if (num / den > 31) { while (num / den > 31) den *= 2; vf = vf "fps=" num "/" den "," }
    }
    turned = h > w
    if (turned) { vf = vf "transpose=" turn ","; t = w; w = h; h = t }
    fit(w, h, maxw, maxh); vf = vf "scale=" fw ":" fh ",setsar=1"
    split(subcodecs, pairs, " ")
    for (p in pairs) { split(pairs[p], kv, "="); mode[kv[1]] = kv[2] }
    subs = ""
    for (j = 0; j < n; j++) {
        s = order[j]
        if (st[s, "codec_type"] == "subtitle" && (st[s, "codec_name"] in mode)) subs = subs " " st[s, "index"] ":" mode[st[s, "codec_name"]]
    }
    d = int(dur)
    printf "%s %s %d %d %d:%02d:%02d%s\n", vf, icon, turned, int(dur / 10), int(d / 3600), int(d % 3600 / 60), d % 60, subs
}'

probe() {
    local flat line
    flat=$(ffprobe -v error -show_entries 'format=duration:stream=index,codec_type,codec_name,width,height,sample_aspect_ratio,field_order,avg_frame_rate:stream_disposition=attached_pic:stream_side_data=rotation' -of flat "$1") || return 1
    line=$(printf '%s\n' "$flat" | awk -v maxw=$max_w -v maxh=$max_h -v iconw=$icon_w -v iconh=$icon_h -v turn=$turn -v subcodecs="$sub_codecs" "$probe_awk") || return 1
    read -r p_vf p_icon p_turned p_start p_length p_subs <<< "$line"
}

# Matroska with H.264 tuned for software decoding and AAC stereo; portrait videos turned to fill the screen
convert() {
    local subs=() n=0 s
    for s in $p_subs; do subs+=(-map "0:${s%%:*}" "-c:s:$n" "${s#*:}"); n=$((n + 1)); done
    tmp=$2.tmp
    ffmpeg -hide_banner -nostdin -loglevel error -stats -y -i "$1" -map 0:V:0 -map '0:a?' "${subs[@]}" \
        -map '0:t?' -vf "$p_vf" -c:v libx264 -tune fastdecode -crf 23 -pix_fmt yuv420p \
        -c:a aac -ac 2 -c:t copy -f matroska "$tmp" && mv "$tmp" "$2"
    s=$?
    rm -f "$tmp"; tmp=
    return $s
}

# The most typical frame of a second of video at a tenth of its length, upright, as a JPEG
save_frame() {
    ffmpeg -hide_banner -nostdin -loglevel error -y -ss "$p_start" -i "$1" -map 0:V:0 \
        -vf "thumbnail=30,$p_icon,setsar=1" -frames:v 1 -update 1 -q:v 3 "$2" || { rm -f "$2"; return 1; }
}

# The first <name>.png/.jpg/.jpeg in a folder, in Puppy's order
find_art() {
    local folder=$1 name ext
    shift
    for name; do
        for ext in png jpg jpeg; do
            art=$folder/$name.$ext
            [ -f "$art" ] && return 0
        done
    done
    return 1
}

# The folder's videos, then each subfolder with videos (a series: one entry with a cover.jpg)
job_src=(); job_out=(); job_series=()
videos_in "$dir"
for f in "${vids[@]}"; do job_src+=("$f"); job_out+=("$out_root"); job_series+=(''); done
for d in "$dir"/*/; do
    d=${d%/}
    case ${d##*/} in "$out_name" | icons) continue ;; esac
    videos_in "$d"
    for f in "${vids[@]}"; do job_src+=("$f"); job_out+=("$out_root/${d##*/}"); job_series+=(1); done
done
total=${#job_src[@]}
if [ "$total" -eq 0 ]; then
    say '' "No videos in $dir" "Nenhum vídeo em $dir"
    exit 0
fi
trap '[ -n "$tmp" ] && rm -f "$tmp"; exit 130' INT

converted=0; kept=0; failed=()
for ((i = 0; i < total; i++)); do
    src=${job_src[i]}; out=${job_out[i]}
    rel=${src#"$dir"/}
    tag="[$((i + 1))/$total] $rel"
    if ! probe "$src"; then
        say "$red" "$tag - ffmpeg cannot read it, skipped" "$tag - o ffmpeg não consegue ler, pulado"
        failed+=("$rel"); continue
    fi
    mkdir -p "$out"
    base=${src##*/}; base=${base%.*}
    dest=$out/$base.mkv
    if [ -e "$dest" ]; then
        say "$gray" "$tag - already converted" "$tag - já convertido"
        kept=$((kept + 1))
    else
        if [ "$p_turned" = 1 ]; then say "$cyan" "$tag ($p_length, portrait: turned 90°)" "$tag ($p_length, vertical: girado 90°)"
        else say "$cyan" "$tag ($p_length)" "$tag ($p_length)"; fi
        if ! convert "$src" "$dest"; then failed+=("$rel"); continue; fi
        converted=$((converted + 1))
    fi
    # subtitle files next to the video, which mpv loads by name
    for f in "${src%/*}"/*; do
        [[ -f $f && ${f##*/} == "$base".* ]] && has_ext "$f" "$sidecar_exts" && cp -f "$f" "$out/"
    done
    # art: what is already there, then the source's own, then a frame
    if [ -n "${job_series[i]}" ]; then art_dir=$out; art_in=${src%/*}; names=(cover folder)
    else art_dir=$out_root/icons; art_in=$dir/icons; names=("$base"); fi
    if ! find_art "$art_dir" "${names[@]}"; then
        mkdir -p "$art_dir"
        if find_art "$art_in" "${names[@]}"; then cp -f "$art" "$art_dir/"
        elif ! save_frame "$src" "$art_dir/${names[0]}.jpg"; then
            say "$yellow" '  could not save a frame as its icon' '  não deu para salvar um frame como ícone'
        fi
    fi
done

echo
say "$green" "$converted converted, $kept already done, ${#failed[@]} failed." "$converted convertidos, $kept já prontos, ${#failed[@]} com erro."
for f in "${failed[@]}"; do printf '%s  %s%s\n' "$red" "$f" "$off"; done
say '' "Copy what is inside $out_root to HOME > media > videos (or media/videos on the second card)." "Copie o que está dentro de $out_root para HOME > media > videos (ou media/videos no segundo cartão)."
