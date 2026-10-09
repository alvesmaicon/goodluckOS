@echo off
rem Converts the videos in this folder (or a folder dropped on it) for the goodluckOS Videos tab. See README.md.
setlocal
set "GL_SELF=%~f0"
set "GL_DIR=%~1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ([IO.File]::ReadAllText($env:GL_SELF, [Text.Encoding]::UTF8).Split([string[]]@('#' + 'POWERSHELL#'), 'None')[1])"
pause
exit /b
#POWERSHELL#
# What the A33 plays smoothly in software (README: up to 640x480 H.264); icons only need the launcher's preview
$maxW = 640; $maxH = 480; $iconW = 320; $iconH = 240
$turn = 'clock'
$outName = 'goodluckOS-videos'
# the Videos tab's extensions (apps.puppy), plus camera ones
$videoExts = 'mp4', 'mkv', 'avi', 'webm', 'mov', 'm4v', 'mpg', 'mpeg', 'wmv', 'flv', '3gp', 'ts', 'mts', 'm2ts'
$sidecarExts = 'srt', 'ass', 'ssa', 'vtt', 'sub', 'idx'
# embedded subtitles Matroska keeps as they are, or as SRT; others are dropped
$subCodecs = @{ subrip = 'copy'; ass = 'copy'; ssa = 'copy'; hdmv_pgs_subtitle = 'copy'; dvd_subtitle = 'copy'
                dvb_subtitle = 'copy'; mov_text = 'srt'; webvtt = 'srt'; text = 'srt' }

$pt = (Get-UICulture).TwoLetterISOLanguageName -eq 'pt'
function T($en, $ptText) { if ($pt) { $ptText } else { $en } }

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue) -or -not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    Write-Host (T 'ffmpeg not found. Install it with "winget install Gyan.FFmpeg", then run this again.' 'ffmpeg não encontrado. Instale com "winget install Gyan.FFmpeg" e rode de novo.') -ForegroundColor Red
    exit 1
}
$dir = if ($env:GL_DIR) { $env:GL_DIR } else { (Get-Location).Path }
if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
    Write-Host (T "Not a folder: $dir" "Não é uma pasta: $dir") -ForegroundColor Red
    exit 1
}
$dir = (Resolve-Path -LiteralPath $dir).ProviderPath.TrimEnd('\')
$outRoot = Join-Path $dir $outName

function Get-Videos($folder) {
    Get-ChildItem -LiteralPath $folder -File | Where-Object { $_.Name[0] -ne '.' -and $videoExts -contains $_.Extension.TrimStart('.').ToLower() } | Sort-Object Name
}

# Display size (pixel aspect and rotation applied), deinterlacing, frame rate cap and length of a video, or $null
function Probe($path) {
    $json = & ffprobe -v error -show_entries 'format=duration:stream=index,codec_type,codec_name,width,height,sample_aspect_ratio,field_order,avg_frame_rate:stream_disposition=attached_pic:stream_side_data=rotation' -of json $path | Out-String
    if ($LASTEXITCODE -ne 0) { return $null }
    $info = $json | ConvertFrom-Json
    $v = $info.streams | Where-Object { $_.codec_type -eq 'video' -and $_.disposition.attached_pic -ne 1 } | Select-Object -First 1
    if (-not $v -or -not $v.width) { return $null }
    $w = [double]$v.width; $h = [double]$v.height
    if ($v.sample_aspect_ratio -match '^(\d+):(\d+)$' -and $Matches[1] -ne '0' -and $Matches[2] -ne '0') { $w = $w * $Matches[1] / $Matches[2] }
    $rotation = $v.side_data_list | Where-Object { $null -ne $_.rotation } | Select-Object -First 1 -ExpandProperty rotation
    if ([math]::Abs([int]$rotation) % 180 -eq 90) { $w, $h = $h, $w }
    # 50/60 fps halved: twice the frames to decode
    $fps = $null
    if ($v.avg_frame_rate -match '^(\d+)/(\d+)$' -and $Matches[1] -ne '0' -and $Matches[2] -ne '0') {
        $num = [long]$Matches[1]; $den = [long]$Matches[2]
        if ($num / $den -gt 31) { while ($num / $den -gt 31) { $den *= 2 }; $fps = "$num/$den" }
    }
    [pscustomobject]@{ W = $w; H = $h; Fps = $fps; Interlaced = $v.field_order -in 'tt', 'bb', 'tb', 'bt'
                       Duration = [double]$info.format.duration; Streams = $info.streams }
}

# Largest even size within maxW x maxH with the same shape, never larger than the source
function Fit([double]$w, [double]$h, [int]$maxW, [int]$maxH) {
    $s = [math]::Min(1.0, [math]::Min($maxW / $w, $maxH / $h))
    , @([math]::Max(2, 2 * [int][math]::Round($w * $s / 2)), [math]::Max(2, 2 * [int][math]::Round($h * $s / 2)))
}

# Matroska with H.264 tuned for software decoding and AAC stereo; portrait videos turned to fill the screen
function Convert-Video($src, $p, $dest) {
    $w = $p.W; $h = $p.H
    $filters = @()
    if ($p.Interlaced) { $filters += 'bwdif=0' }
    if ($p.Fps) { $filters += "fps=$($p.Fps)" }
    if ($h -gt $w) { $filters += "transpose=$turn"; $w, $h = $h, $w }
    $size = Fit $w $h $maxW $maxH
    $filters += "scale=$($size[0]):$($size[1])", 'setsar=1'
    $subs = @(); $n = 0
    foreach ($s in $p.Streams | Where-Object { $_.codec_type -eq 'subtitle' -and $_.codec_name -and $subCodecs.ContainsKey($_.codec_name) }) {
        $subs += '-map', "0:$($s.index)", "-c:s:$n", $subCodecs[$s.codec_name]; $n++
    }
    $tmp = "$dest.tmp"
    $ffArgs = @('-hide_banner', '-nostdin', '-loglevel', 'error', '-stats', '-y', '-i', $src, '-map', '0:V:0', '-map', '0:a?') + $subs + @(
        '-map', '0:t?', '-vf', ($filters -join ','), '-c:v', 'libx264', '-tune', 'fastdecode', '-crf', '23', '-pix_fmt', 'yuv420p',
        '-c:a', 'aac', '-ac', '2', '-c:t', 'copy', '-f', 'matroska', $tmp)
    & ffmpeg @ffArgs
    if ($LASTEXITCODE -ne 0) { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue; return $false }
    [IO.File]::Move($tmp, $dest)
    $true
}

# The most typical frame of a second of video at a tenth of its length, upright, as a JPEG
function Save-Frame($src, $p, $dest) {
    $size = Fit $p.W $p.H $iconW $iconH
    & ffmpeg -hide_banner -nostdin -loglevel error -y -ss ([int]($p.Duration / 10)) -i $src -map 0:V:0 `
        -vf "thumbnail=30,scale=$($size[0]):$($size[1]),setsar=1" -frames:v 1 -update 1 -q:v 3 $dest
    $LASTEXITCODE -eq 0
}

# The first <name>.png/.jpg/.jpeg in a folder, in Puppy's order
function Find-Art($folder, [string[]]$names) {
    foreach ($name in $names) {
        foreach ($ext in 'png', 'jpg', 'jpeg') {
            $path = Join-Path $folder "$name.$ext"
            if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
        }
    }
}

# The folder's videos, then each subfolder with videos (a series: one entry with a cover.jpg)
$jobs = @()
foreach ($f in Get-Videos $dir) { $jobs += [pscustomobject]@{ Src = $f; Out = $outRoot; Series = $false } }
foreach ($d in Get-ChildItem -LiteralPath $dir -Directory | Where-Object { $_.Name -ne $outName -and $_.Name -ne 'icons' -and $_.Name[0] -ne '.' } | Sort-Object Name) {
    foreach ($f in Get-Videos $d.FullName) { $jobs += [pscustomobject]@{ Src = $f; Out = Join-Path $outRoot $d.Name; Series = $true } }
}
if (-not $jobs) {
    Write-Host (T "No videos in $dir" "Nenhum vídeo em $dir")
    exit
}

$converted = 0; $kept = 0; $failed = @()
for ($i = 0; $i -lt $jobs.Count; $i++) {
    $job = $jobs[$i]; $src = $job.Src
    $rel = $src.FullName.Substring($dir.Length + 1)
    $tag = "[$($i + 1)/$($jobs.Count)] $rel"
    $p = Probe $src.FullName
    if (-not $p) {
        Write-Host "$tag - $(T 'ffmpeg cannot read it, skipped' 'o ffmpeg não consegue ler, pulado')" -ForegroundColor Red
        $failed += $rel; continue
    }
    [void][IO.Directory]::CreateDirectory($job.Out)
    $dest = Join-Path $job.Out "$($src.BaseName).mkv"
    if (Test-Path -LiteralPath $dest) {
        Write-Host "$tag - $(T 'already converted' 'já convertido')" -ForegroundColor DarkGray
        $kept++
    } else {
        $length = [TimeSpan]::FromSeconds($p.Duration).ToString('h\:mm\:ss')
        $turned = if ($p.H -gt $p.W) { T ', portrait: turned 90°' ', vertical: girado 90°' }
        Write-Host "$tag ($length$turned)" -ForegroundColor Cyan
        if (-not (Convert-Video $src.FullName $p $dest)) { $failed += $rel; continue }
        $converted++
    }
    # subtitle files next to the video, which mpv loads by name
    Get-ChildItem -LiteralPath $src.DirectoryName -File | Where-Object {
        $_.Name.StartsWith("$($src.BaseName).", [StringComparison]::OrdinalIgnoreCase) -and $sidecarExts -contains $_.Extension.TrimStart('.').ToLower()
    } | ForEach-Object { [IO.File]::Copy($_.FullName, (Join-Path $job.Out $_.Name), $true) }
    # art: what is already there, then the source's own, then a frame
    if ($job.Series) { $artDir = $job.Out; $artIn = $src.DirectoryName; $names = 'cover', 'folder' }
    else { $artDir = Join-Path $outRoot 'icons'; $artIn = Join-Path $dir 'icons'; $names = , $src.BaseName }
    if (-not (Find-Art $artDir $names)) {
        [void][IO.Directory]::CreateDirectory($artDir)
        $art = Find-Art $artIn $names
        if ($art) { [IO.File]::Copy($art, (Join-Path $artDir ([IO.Path]::GetFileName($art))), $true) }
        elseif (-not (Save-Frame $src.FullName $p (Join-Path $artDir "$($names[0]).jpg"))) {
            Write-Host (T '  could not save a frame as its icon' '  não deu para salvar um frame como ícone') -ForegroundColor Yellow
        }
    }
}

Write-Host ''
Write-Host (T "$converted converted, $kept already done, $($failed.Count) failed." "$converted convertidos, $kept já prontos, $($failed.Count) com erro.") -ForegroundColor Green
foreach ($f in $failed) { Write-Host "  $f" -ForegroundColor Red }
Write-Host (T "Copy what is inside $outRoot to HOME > media > videos (or media\videos on the second card)." "Copie o que está dentro de $outRoot para HOME > media > videos (ou media\videos no segundo cartão).")
