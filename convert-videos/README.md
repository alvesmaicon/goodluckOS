# convert-videos: videos ready for the console

The console decodes video in software: up to 640x480 H.264 plays smoothly, but phone videos (1080p or 4K, often H.265 at 60 fps) stutter or don't play. `convert-videos.bat` (Windows) and `convert-videos.sh` (macOS and Linux) convert a whole folder of videos on a PC for the Videos tab, and save a picture of each one as its art in the launcher.

1. Install ffmpeg:
   - Windows: open a terminal and run `winget install Gyan.FFmpeg`.
   - macOS: with [Homebrew](https://brew.sh), run `brew install ffmpeg` in Terminal. Linux: `sudo apt install ffmpeg`, or your distribution's package.
2. Download the script into the folder with your videos and run it:
   - Windows: [convert-videos.bat](https://github.com/alvesmaicon/goodluckOS/raw/develop/convert-videos/convert-videos.bat). Double-click it, or drag a folder onto it.
   - macOS or Linux: [convert-videos.sh](https://github.com/alvesmaicon/goodluckOS/raw/develop/convert-videos/convert-videos.sh). In Terminal, type `bash ` (with the space), drag the script into the window and press Enter. To convert another folder, drag that folder in after the script.
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
- Turns portrait videos 90° clockwise so they fill the screen; hold the console turned to the left to watch them. Phone videos stored sideways with a rotation flag count as portrait too. To turn them the other way, change `$turn = 'clock'` (`.bat`) or `turn=clock` (`.sh`) at the top of the script to `cclock`.
- Halves 50/60 fps to 25/30, and deinterlaces camera footage (1080i).
- Encodes H.264 with `-tune fastdecode` and stereo AAC in `.mkv`, the same recipe as the main README. Every audio track and the subtitles are kept (L2/R2 switch them), and subtitle files next to a video (`name.srt`, `name.pt-BR.srt`) are copied along.
- Art: a frame from a tenth of the way in (the most typical frame of that second, so not a black one), upright, saved as `icons/<name>.jpg`.
- A subfolder with videos is a series, one entry in the launcher: its videos go to a subfolder with the same name, with a `cover.jpg` from the first episode.
- Art that already exists in the source folder (`icons/<name>.png` or `.jpg`, a series' `cover.jpg` or `folder.jpg`) is copied instead of a frame.

HDR phone videos are converted without tone mapping, so their colors may look washed out.

Tested on a PC with ffmpeg 9.0.1: phone videos with and without a rotation flag, 60 fps, an anamorphic DVD file with 5.1 audio and two subtitle tracks, 1080i camera footage, a small AVI, a series, an unreadable file, and names with accents and `[ ] ' &`. `convert-videos.sh` was tested with the same set on a Mac (bash 3.2, ffmpeg 8.1.1 from Homebrew) and in Ubuntu 24.04 (ffmpeg 6.1), plus Ctrl+C in the middle of a video, which leaves no partial file.

## Português

O console decodifica vídeo por software: até 640x480 em H.264 roda liso, mas vídeo de celular (1080p ou 4K, muitas vezes H.265 a 60 fps) trava ou nem abre. O `convert-videos.bat` (Windows) e o `convert-videos.sh` (macOS e Linux) convertem uma pasta inteira no PC para a aba Videos, e salvam um frame de cada vídeo como imagem no launcher.

1. Instale o ffmpeg:
   - Windows: abra um terminal e rode `winget install Gyan.FFmpeg`.
   - macOS: com o [Homebrew](https://brew.sh), rode `brew install ffmpeg` no Terminal. Linux: `sudo apt install ffmpeg`, ou o pacote da sua distribuição.
2. Baixe o script na pasta dos vídeos e rode:
   - Windows: [convert-videos.bat](https://github.com/alvesmaicon/goodluckOS/raw/develop/convert-videos/convert-videos.bat). Dê dois cliques, ou arraste uma pasta em cima dele.
   - macOS ou Linux: [convert-videos.sh](https://github.com/alvesmaicon/goodluckOS/raw/develop/convert-videos/convert-videos.sh). No Terminal, digite `bash ` (com o espaço), arraste o script para a janela e aperte Enter. Para converter outra pasta, arraste a pasta depois do script.
3. Copie o que está dentro da pasta nova `goodluckOS-videos` para `HOME -> media -> videos` (ou `media/videos` no segundo cartão).

Os vídeos originais não são alterados, e rodar de novo só converte o que é novo. Vídeos em pé são girados 90° no sentido horário para ocupar a tela: assista com o console virado para a esquerda. Uma subpasta com vídeos vira uma série, com um `cover.jpg` do primeiro episódio. Legendas embutidas e arquivos `.srt` com o mesmo nome do vídeo vão junto.
