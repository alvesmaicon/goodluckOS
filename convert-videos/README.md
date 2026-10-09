# convert-videos: videos ready for the console

The console decodes video in software: up to 640x480 H.264 plays smoothly, but phone videos (1080p or 4K, often H.265 at 60 fps) stutter or don't play. `convert-videos.bat` converts a whole folder of videos on a Windows PC for the Videos tab, and saves a picture of each one as its art in the launcher.

1. Install ffmpeg: open a terminal and run `winget install Gyan.FFmpeg`.
2. Download [convert-videos.bat](https://github.com/alvesmaicon/goodluckOS/raw/develop/convert-videos/convert-videos.bat) into the folder with your videos and double-click it, or drag a folder onto it.
3. Each video shows its length and then its progress (`time=`).
4. Copy what is inside the new `goodluckOS-videos` folder to `HOME -> media -> videos` (or `media/videos` on the second card).

The original videos are never changed. Running it again only converts what is new: videos already in `goodluckOS-videos` are skipped.

```
goodluckOS-videos/
  Holidays.mkv
  icons/Holidays.jpg
  Some Series/
    Episode 01.mkv
    Episode 01.pt-BR.srt
    cover.jpg
```

## What it does

- Scales each video to fit 640x480 and keeps its shape: 16:9 becomes 640x360, and the player adds the bars. Smaller videos are not enlarged.
- Turns portrait videos 90° clockwise so they fill the screen; hold the console turned to the left to watch them. Phone videos stored sideways with a rotation flag count as portrait too. To turn them the other way, change `$turn = 'clock'` to `'cclock'` at the top of the script.
- Halves 50/60 fps to 25/30, and deinterlaces camera footage (1080i).
- Encodes H.264 with `-tune fastdecode` and stereo AAC in `.mkv`, the same recipe as the main README. Every audio track and the subtitles are kept (L2/R2 switch them), and subtitle files next to a video (`name.srt`, `name.pt-BR.srt`) are copied along.
- Art: a frame from a tenth of the way in (the most typical frame of that second, so not a black one), upright, saved as `icons/<name>.jpg`.
- A subfolder with videos is a series, one entry in the launcher: its videos go to a subfolder with the same name, with a `cover.jpg` from the first episode.
- Art that already exists in the source folder (`icons/<name>.png` or `.jpg`, a series' `cover.jpg` or `folder.jpg`) is copied instead of a frame.

HDR phone videos are converted without tone mapping, so their colors may look washed out.

The script runs on Windows only. On macOS or Linux, the ffmpeg line in the main README converts one file.

Tested on a PC with ffmpeg 9.0.1: phone videos with and without a rotation flag, 60 fps, an anamorphic DVD file with 5.1 audio and two subtitle tracks, 1080i camera footage, a small AVI, a series, an unreadable file, and names with accents and `[ ] ' &`.

## Português

O console decodifica vídeo por software: até 640x480 em H.264 roda liso, mas vídeo de celular (1080p ou 4K, muitas vezes H.265 a 60 fps) trava ou nem abre. O `convert-videos.bat` converte uma pasta inteira no PC com Windows para a aba Videos, e salva um frame de cada vídeo como imagem no launcher.

1. Instale o ffmpeg: abra um terminal e rode `winget install Gyan.FFmpeg`.
2. Baixe o [convert-videos.bat](https://github.com/alvesmaicon/goodluckOS/raw/develop/convert-videos/convert-videos.bat) na pasta dos vídeos e dê dois cliques, ou arraste uma pasta em cima dele.
3. Copie o que está dentro da pasta nova `goodluckOS-videos` para `HOME -> media -> videos` (ou `media/videos` no segundo cartão).

Os vídeos originais não são alterados, e rodar de novo só converte o que é novo. Vídeos em pé são girados 90° no sentido horário para ocupar a tela: assista com o console virado para a esquerda. Uma subpasta com vídeos vira uma série, com um `cover.jpg` do primeiro episódio. Legendas embutidas e arquivos `.srt` com o mesmo nome do vídeo vão junto.
