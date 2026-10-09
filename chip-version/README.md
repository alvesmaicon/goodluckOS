# chip-version: is this console an A23 or an A33?

R36S clones with the GA36-MB board come with an Allwinner A23 or A33, and goodluckOS builds for one don't boot on the other. The console can't tell you which one it has: the stock menu reports a 64-bit CPU and 1 GB of RAM on both, and the marking on the chip can't be trusted either. The microSD card that came with the console can: its boot data is made for its chip.

`chip-version.bat` reads the start of that card on a Windows PC and prints the chip.

1. Take the microSD card out of the console (slot TF1-OS) and put it in a USB card reader.
2. Download [chip-version.bat](https://github.com/alvesmaicon/goodluckOS/raw/develop/chip-version/chip-version.bat) and double-click it. Allow it to run as administrator: Windows only lets a program read a disk directly with admin rights.
3. If Windows offers to format the card, click **Cancel**.
4. A few seconds later it shows **CHIP A23** or **CHIP A33**, and the board name when it knows it.

The script only reads the first 128 MiB of each disk that isn't the system disk. Nothing is written. Windows SmartScreen or an antivirus may warn about it, since it is an unsigned script that asks for admin rights and reads a disk. The whole program is the `.bat` file: open it in Notepad to read it.

## What it checks

- The Allwinner boot0 signature, `eGON.BT0` at 8 KiB.
- The SHA-256 of `script.bin` at byte 20340736, against the same table as the [Firmware Builder](https://codezombie.github.io/goodluckOS/download.html): Rhododendron and Gecko are A33; Esisla, Underscore and Xeno are A23.
- For a board that isn't in the table, the stock kernel's platform name: `sun8iw3` is the A23, `sun8iw5` the A33.

Without Windows, `sudo dd if=/dev/sdX of=stock.img bs=1M count=128` makes the same dump, and step 1 of the Firmware Builder reads the variant and the chip from it.

Tested on the stock cards of two A33 Rhododendron consoles and on a goodluckOS card. Not tested on an A23 card yet.

## Português

Os clones do R36S com a placa GA36-MB vêm com um chip Allwinner A23 ou A33. O menu do console sempre diz "64 bits, 1 GB", e o nome gravado no chip também não é confiável. O cartão microSD que veio com o console diz qual é.

1. Tire o cartão do console (entrada TF1-OS) e coloque num leitor de cartão USB.
2. Baixe o [chip-version.bat](https://github.com/alvesmaicon/goodluckOS/raw/develop/chip-version/chip-version.bat) e dê dois cliques. Permita rodar como administrador: o Windows só deixa ler o cartão direto assim.
3. Se o Windows perguntar se quer formatar o cartão, clique em **Cancelar**.
4. Em poucos segundos aparece **CHIP A23** ou **CHIP A33**.

O programa só lê o cartão; nada é gravado. O Windows ou o antivírus podem avisar, porque é um script sem assinatura que pede administrador e lê um disco. O programa inteiro é o arquivo `.bat` e pode ser lido no Bloco de Notas.
