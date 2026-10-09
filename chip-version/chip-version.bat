@echo off
rem Tells an A23 console from an A33 one by the stock microSD card. Read only. See README.md.
net session >nul 2>&1 || (powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" & exit /b)
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ([IO.File]::ReadAllText('%~f0', [Text.Encoding]::UTF8).Split([string[]]@('#' + 'POWERSHELL#'), 'None')[1])"
pause
exit /b
#POWERSHELL#
# script.bin hashes, same table as the Firmware Builder (docs/download.html)
$variants = @{
    '4bdfa6b7deacf59d821063accdd5bf7789c70d240dc695fffa3e16f2e83dba6c' = @('A33', 'GA36-MB A33 Rhododendron')
    'f6b72e9705f528c42ca5bef7ee39fddfd9ddc5369d365c17324ca6d9f8770898' = @('A33', 'GA36-MB A33 Gecko')
    'ad0b836c8b3cc6dd2b3b0d8c1817e2fdfe9ed48998a3bed758a73603f05f96e1' = @('A23', 'GA36-MB A23 Esisla')
    '755aae75f7df87348a1427b94532e6a1ef758e3071fb5bf52f10a7f7032318e4' = @('A23', 'GA36-MB A23 Underscore')
    '39a74a42c3d4f9d0599bf5f0db136a7f53bb6a072aa117eaae14e0f27872c798' = @('A23', 'GA36-MB A23 Xeno')
}
$scriptBinOffset = 20340736; $scriptBinMax = 131072; $readBytes = 128MB

$pt = (Get-UICulture).TwoLetterISOLanguageName -eq 'pt'
function T($en, $ptText) { if ($pt) { $ptText } else { $en } }

Add-Type -TypeDefinition @'
public static class ChipVersion {
    public static int IndexOf(byte[] h, byte[] n) {
        for (int i = 0; i <= h.Length - n.Length; i++) {
            int j = 0; while (j < n.Length && h[i + j] == n[j]) j++;
            if (j == n.Length) return i;
        }
        return -1;
    }
    static int I32(byte[] b, int o) { return System.BitConverter.ToInt32(b, o); }
    // computeScriptBinLength from the Firmware Builder; -1 if it isn't a script.bin
    public static int ScriptBinLength(byte[] b) {
        if (b.Length < 16) return -1;
        uint sections = System.BitConverter.ToUInt32(b, 0);
        if (sections > 0x100) return -1;
        long max = 16 + sections * 40L;
        if (max > b.Length) return -1;
        for (int i = 0; i < sections; i++) {
            int so = 16 + i * 40, count = I32(b, so + 32), table = I32(b, so + 36) * 4;
            if (count < 0 || table < 0 || table + count * 40L > b.Length) return -1;
            max = System.Math.Max(max, table + count * 40L);
            for (int j = 0; j < count; j++) {
                int eo = table + j * 40, data = I32(b, eo + 32) * 4;
                long end = data + (System.BitConverter.ToUInt32(b, eo + 36) & 0xffff) * 4L;
                if (data < 0 || end > b.Length) return -1;
                max = System.Math.Max(max, end);
            }
        }
        return (int)max;
    }
}
'@

function Read-Start($stream, [int64]$size) {
    $buf = New-Object byte[] ([int][math]::Min([int64]$readBytes, [int64]$size)); $done = 0
    while ($done -lt $buf.Length) { $n = $stream.Read($buf, $done, [math]::Min(4MB, $buf.Length - $done)); if ($n -le 0) { break }; $done += $n }
    if ($done -lt $buf.Length) { [Array]::Resize([ref]$buf, $done) }
    return , $buf
}

function Test-Card([byte[]]$b) {
    $latin = [Text.Encoding]::GetEncoding(28591)
    $boot0 = $b.Length -gt 0x200c -and $latin.GetString($b, 0x2004, 8) -eq 'eGON.BT0'
    $variant = $null
    if ($b.Length -ge $scriptBinOffset + $scriptBinMax) {
        $sb = New-Object byte[] $scriptBinMax; [Array]::Copy($b, $scriptBinOffset, $sb, 0, $scriptBinMax)
        $len = [ChipVersion]::ScriptBinLength($sb)
        if ($len -gt 0) {
            $hash = -join ([Security.Cryptography.SHA256]::Create().ComputeHash($sb, 0, $len) | ForEach-Object { $_.ToString('x2') })
            $variant = $variants[$hash]
        }
    }
    $kernel = if ([ChipVersion]::IndexOf($b, $latin.GetBytes('sun8iw3')) -ge 0) { 'A23' } elseif ([ChipVersion]::IndexOf($b, $latin.GetBytes('sun8iw5')) -ge 0) { 'A33' }
    $chip = if ($variant) { $variant[0] } else { $kernel }
    return [pscustomobject]@{ Boot0 = $boot0; Chip = $chip; Board = $(if ($variant) { $variant[1] }); Kernel = $kernel }
}

function Show-Result($r) {
    if (-not $r.Boot0 -and -not $r.Chip) { Write-Host (T '  Not a R36S/GA36-MB console card (or it was flashed with another system).' '  Não é o cartão de um console R36S/GA36-MB (ou já foi regravado com outro sistema).') -ForegroundColor Gray; return }
    if (-not $r.Chip) { Write-Host (T '  An Allwinner console card, but the chip could not be told.' '  Cartão de console Allwinner, mas não deu para saber o chip.') -ForegroundColor Yellow; return }
    $color = if ($r.Chip -eq 'A23') { 'Green' } else { 'Yellow' }
    Write-Host ''
    Write-Host ("  >>>  CHIP {0}  <<<" -f $r.Chip) -ForegroundColor $color
    if ($r.Chip -eq 'A23') { Write-Host (T '  This is the one we are looking for!' '  É este que procuramos!') -ForegroundColor Green } else { Write-Host (T '  Not an A23.' '  Não é o A23.') -ForegroundColor Yellow }
    if ($r.Board) { Write-Host ((T '  board: {0}' '  placa: {0}') -f $r.Board) } else { Write-Host (T '  board: unknown variant (also interesting!)' '  placa: variante ainda desconhecida (também interessa!)') }
    if ($r.Kernel -and $r.Kernel -ne $r.Chip) { Write-Host ((T '  warning: the kernel says {0}' '  atenção: o kernel diz {0}') -f $r.Kernel) -ForegroundColor Red }
}

function Main {
    Write-Host '=================================================================='
    Write-Host (T '  Which chip does this console have? (A23 or A33)  R36S / GA36-MB' '  Qual chip tem este console? (A23 ou A33)  R36S / GA36-MB')
    Write-Host (T '  This only READS the card. Nothing is written or erased.' '  Só LÊ o cartão. Nada é gravado nem apagado.')
    Write-Host (T '  If Windows offers to format the card, click CANCEL.' '  Se o Windows perguntar se quer formatar o cartão, clique em CANCELAR.')
    Write-Host '=================================================================='
    $disks = @(Get-Disk | Where-Object { -not $_.IsBoot -and -not $_.IsSystem -and $_.Size -ge 128MB -and $_.Size -le 300GB })
    if (-not $disks) { Write-Host ''; Write-Host (T '  No card found. Put the console''s card in a USB reader and open this file again.' '  Nenhum cartão encontrado. Coloque o cartão do console num leitor USB e abra este arquivo de novo.') -ForegroundColor Yellow; return }
    foreach ($d in $disks) {
        Write-Host ''
        Write-Host ((T 'Disk {0}: {1:n1} GB ({2}), reading...' 'Disco {0}: {1:n1} GB ({2}), lendo...') -f $d.Number, ($d.Size / 1GB), $d.FriendlyName)
        try {
            $s = New-Object IO.FileStream("\\.\PhysicalDrive$($d.Number)", [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            try { $b = Read-Start $s $d.Size } finally { $s.Close() }
            Show-Result (Test-Card $b)
        } catch { Write-Host ((T '  Could not read it: {0}' '  Erro ao ler: {0}') -f $_.Exception.Message) -ForegroundColor Red }
    }
    Write-Host ''
    Write-Host (T 'Done. You can take the card out and put it back in the console.' 'Pronto. Pode tirar o cartão e devolver ao console.')
}

if (-not $ChipVersionNoMain) { Main }
