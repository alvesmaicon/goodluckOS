#!/usr/bin/env python3
"""Shell over the console's USB serial (ttyGS0, root/root), on macOS, Linux or Windows.

  glserial.py cmd "uname -a" "df -h"     run commands, print their output
  glserial.py send <local> <remote>      copy a file to the console (base64), check the SHA-256
  glserial.py get <remote> <local>       copy a file from the console (gzip + base64)
  glserial.py get --cmd "dmesg" <local>  save a command's output

The port is found by the gadget's USB id (1d6b:0104); --port overrides it (/dev/cu.usbmodem*, COM3).
Serial is slow (~40 KB/s): a 10 MB package takes 4-5 min. When the port drops during a send, the
send waits for it to come back and goes on from what reached the console. Needs pyserial (pip install pyserial).
"""
import argparse, base64, gzip, hashlib, re, sys, time

import serial
from serial.tools import list_ports

PROMPT = re.compile(r"# $")


def find_port():
    for p in list_ports.comports():
        if p.vid == 0x1D6B and p.pid == 0x0104:
            return p.device
    for p in list_ports.comports():
        if "usbmodem" in p.device:
            return p.device
    sys.exit("console not found: is the USB cable in the data port? (--port to choose)")


class Console:
    def __init__(self, port):
        self.s = serial.Serial(port, 115200, timeout=0.05)
        self.s.dtr = self.s.rts = True

    def read_for(self, seconds, until=None):
        out, end = "", time.time() + seconds
        while time.time() < end:
            out += self.s.read(65536).decode("utf-8", "replace")
            if until and until.search(out):
                break
        return out

    def write(self, text):
        self.s.write(text.encode())

    def login(self):
        """A reconnected cable leaves a login prompt; get to a root shell."""
        for _ in range(3):
            self.write("\x03\n")
            o = self.read_for(1.5, PROMPT)
            if re.search(r"[Pp]assword:\s*$", o):
                self.write("\n")
                o = self.read_for(2.5, PROMPT)
            if re.search(r"login:\s*$", o):
                self.write("root\n")
                o = self.read_for(1.5)
                if re.search(r"[Pp]assword", o):
                    self.write("root\n")
                    o = self.read_for(2.5, PROMPT)
            if PROMPT.search(o):
                self.write("stty -echo\n")   # long commands wrap and their echo would mix with the output
                self.read_for(1.5, PROMPT)
                return
        sys.exit("no root prompt on the console")

    def close(self):
        try:
            self.write("stty echo\n")
            self.read_for(0.5, PROMPT)
            self.s.close()
        except serial.SerialException:
            pass

    def reopen(self):
        """The port drops now and then on a long send: wait for it to come back and log in again."""
        try:
            self.s.close()
        except serial.SerialException:
            pass
        for _ in range(20):
            time.sleep(3)
            try:
                self.s = serial.Serial(find_port(), 115200, timeout=0.05)
                self.s.dtr = self.s.rts = True
                self.login()
                return
            except (serial.SerialException, SystemExit):
                pass
        sys.exit("the serial did not come back")

    def run(self, cmd, timeout=30):
        marker = "@@DONE@@"
        self.write(f"{cmd}\necho {marker[:3]}''{marker[3:]}\n")
        o = self.read_for(timeout, re.compile(re.escape(marker) + r".*# $", re.S))
        return o.split(marker)[0].replace("\r", "").lstrip("\n")


def cmd_cmd(c, args):
    for command in args.commands:
        print(c.run(command, args.timeout), end="")


def cmd_send(c, args):
    data = open(args.local, "rb").read()
    b64 = base64.b64encode(data).decode()
    remote = args.remote
    c.write(f"rm -f {remote}.b64\n")
    c.read_for(1, PROMPT)
    chunk, n = 3000, (len(b64) + 2999) // 3000
    print(f"sending {len(data):,} bytes in {n} blocks", flush=True)
    start, shown, i, drops = time.time(), -1, 0, 0
    while i < n:
        try:
            c.write(f"printf '%s' '{b64[i * chunk:(i + 1) * chunk]}' >> {remote}.b64\n")
            if not PROMPT.search(c.read_for(5, PROMPT)):
                sys.exit(f"the console stopped answering at block {i + 1}/{n}")
            i += 1
        except serial.SerialException:
            # go on from the blocks that reached the file: a line cut short never ran
            drops += 1
            if drops > 20:
                sys.exit("the serial dropped 20 times, giving up")
            print(f"serial dropped at block {i + 1}/{n}, reconnecting", flush=True)
            c.reopen()
            i = int(c.run(f"wc -c < {remote}.b64").strip() or 0) // chunk
            continue
        pct = i * 100 // n
        if pct // 10 > shown:   # a line every 10 %, with the time left
            shown = pct // 10
            left = int((time.time() - start) / i * (n - i))
            sent = min(len(data), i * chunk * 3 // 4)
            print(f"{pct:3d}% ({sent / 1e6:.1f} of {len(data) / 1e6:.1f} MB), ~{left // 60}m{left % 60:02d}s left", flush=True)
    print("decoding on the console and checking the SHA-256", flush=True)
    out = c.run(f"base64 -d {remote}.b64 > {remote} && rm {remote}.b64 && sha256sum {remote}")
    local = hashlib.sha256(data).hexdigest()
    print(out.strip())
    print("local:", local)
    print("MATCH" if local in out else "MISMATCH")
    sys.exit(0 if local in out else 1)


def cmd_get(c, args):
    src = args.cmd if args.cmd else f"cat '{args.remote}'"
    c.write(f"echo; echo @@BEG''IN@@; {src} | gzip -c | base64; echo @@E''ND@@\n")
    t = c.read_for(args.timeout, re.compile("@@END@@"))
    if "@@BEGIN@@" not in t or "@@END@@" not in t:
        sys.exit(f"did not get the whole file ({len(t)} chars)")
    b64 = re.sub(r"[^A-Za-z0-9+/=]", "", t.split("@@BEGIN@@", 1)[1].split("@@END@@", 1)[0])
    data = gzip.decompress(base64.b64decode(b64))
    open(args.local, "wb").write(data)
    print(f"OK: {len(data):,} bytes -> {args.local}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port")
    sub = ap.add_subparsers(dest="action", required=True)
    p = sub.add_parser("cmd")
    p.add_argument("commands", nargs="+")
    p.add_argument("--timeout", type=float, default=30)
    p = sub.add_parser("send")
    p.add_argument("local")
    p.add_argument("remote")
    p = sub.add_parser("get")
    p.add_argument("remote", nargs="?")
    p.add_argument("local")
    p.add_argument("--cmd")
    p.add_argument("--timeout", type=float, default=300)
    args = ap.parse_args()
    if args.action == "get" and not (args.remote or args.cmd):
        ap.error("get needs a remote path or --cmd")

    c = Console(args.port or find_port())
    c.login()
    try:
        {"cmd": cmd_cmd, "send": cmd_send, "get": cmd_get}[args.action](c, args)
    finally:
        c.close()


if __name__ == "__main__":
    main()
