#!/usr/bin/env python3
"""BLE utilities for Brilliant Labs Monocle PrismOS deploy/test work."""

import argparse
import asyncio
import json
import os
import sys
import time
from pathlib import Path

from bleak import BleakClient, BleakScanner


NUS_SERVICE_UUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
NUS_RX_UUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"  # Host -> Monocle REPL
NUS_TX_UUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"  # Monocle REPL -> Host

RAW_SERVICE_UUID = "e5700001-7bac-429a-b4ce-57ff900f479d"

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / ".brilliant" / "device-files.json"


def norm_uuid_list(device):
    details = getattr(device, "details", None)
    uuids = []
    metadata = getattr(device, "metadata", None)
    if isinstance(metadata, dict):
        uuids.extend(metadata.get("uuids") or [])
    adv = getattr(device, "advertisement_data", None)
    if adv is not None:
        uuids.extend(getattr(adv, "service_uuids", None) or [])
    if isinstance(details, dict):
        uuids.extend(details.get("uuids") or [])
    return [str(u).lower() for u in uuids]


async def scan(timeout, all_devices=False):
    found = await BleakScanner.discover(timeout=timeout, return_adv=True)
    if isinstance(found, dict):
        devices = list(found.values())
    else:
        devices = [(dev, None) for dev in found]
    rows = []
    for dev, adv in devices:
        name = dev.name or ""
        uuids = norm_uuid_list(dev)
        if adv is not None:
            uuids.extend([str(u).lower() for u in (getattr(adv, "service_uuids", None) or [])])
        rssi = getattr(adv, "rssi", "") if adv is not None else ""
        is_monocle = "monocle" in name.lower() or NUS_SERVICE_UUID in uuids or RAW_SERVICE_UUID in uuids
        if all_devices or is_monocle:
            rows.append((name, dev.address, ",".join(uuids), rssi))
    return rows


async def find_monocle(timeout, prefer_safe=False):
    devices = await BleakScanner.discover(timeout=timeout, return_adv=False)
    best = None
    for dev in devices:
        name = dev.name or ""
        uuids = norm_uuid_list(dev)
        lname = name.lower()
        if prefer_safe and "monocle_safe" in lname:
            return dev
        if "monocle" in lname:
            return dev
        if NUS_SERVICE_UUID in uuids or RAW_SERVICE_UUID in uuids:
            best = dev
    return best


async def resolve_monocle(args):
    if args.address:
        return args.address
    if not getattr(args, "allow_scan", False):
        raise RuntimeError(
            "Refusing to auto-select a Monocle. Run `tools/monocle_ble.py scan`, "
            "then pass --address for the known-good device. Use --allow-scan only "
            "when exactly one Monocle-like device is advertising."
        )
    return await find_monocle(args.scan_timeout, prefer_safe=args.prefer_safe)


class NusRepl:
    def __init__(self, client, verbose=False):
        self.client = client
        self.verbose = verbose
        self.buf = bytearray()
        self.max_write = 20

    async def start(self):
        await self.client.start_notify(NUS_TX_UUID, self._on_notify)
        try:
            ch = self.client.services.get_characteristic(NUS_RX_UUID)
            size = getattr(ch, "max_write_without_response_size", None)
            if size and int(size) > 0:
                self.max_write = max(20, int(size))
        except Exception:
            self.max_write = 20

    def _on_notify(self, _char, data):
        self.buf.extend(bytes(data))
        if self.verbose:
            sys.stdout.write(bytes(data).decode("utf-8", "replace"))
            sys.stdout.flush()

    async def write_bytes(self, data):
        for off in range(0, len(data), self.max_write):
            chunk = data[off:off + self.max_write]
            await self.client.write_gatt_char(NUS_RX_UUID, chunk, response=False)
            await asyncio.sleep(0.01)

    async def wait_for(self, marker=b">>> ", timeout=8.0):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if marker in self.buf:
                out = bytes(self.buf)
                self.buf.clear()
                return out
            await asyncio.sleep(0.05)
        out = bytes(self.buf)
        self.buf.clear()
        raise TimeoutError("timed out waiting for REPL prompt; recent output: %r" % out[-200:])

    async def interrupt_to_prompt(self):
        self.buf.clear()
        await self.write_bytes(b"\x03\x03\r")
        try:
            await self.wait_for(timeout=4.0)
            return
        except TimeoutError:
            pass
        await self.write_bytes(b"\r")
        await self.wait_for(timeout=8.0)

    async def line(self, code, timeout=8.0, expect_prompt=True):
        self.buf.clear()
        await self.write_bytes(code.encode("utf-8") + b"\r")
        if not expect_prompt:
            return b""
        out = await self.wait_for(timeout=timeout)
        if b"Traceback" in out:
            raise RuntimeError(out.decode("utf-8", "replace"))
        return out

    async def exec_snippet(self, code, timeout=8.0):
        return await self.line("exec(%r)" % code, timeout=timeout)


async def ensure_services(client):
    getter = getattr(client, "get_services", None)
    if getter is not None:
        result = getter()
        if hasattr(result, "__await__"):
            await result
    return client.services


def mkdir_snippet(device_dirs):
    lines = ["import os"]
    for directory in sorted(device_dirs):
        lines.extend([
            "try:",
            "    os.mkdir(%r)" % directory,
            "except OSError:",
            "    pass",
        ])
    return "\n".join(lines)


def ordered_manifest(only=None):
    data = json.loads(MANIFEST.read_text())
    wanted = set(only or [])
    pairs = []
    for local, remote in data.items():
        if wanted and local.lstrip("/") not in wanted and remote not in wanted:
            continue
        src = (ROOT / local.lstrip("/")).resolve()
        pairs.append((src, remote))

    def priority(item):
        _src, remote = item
        if "/" in remote:
            return 0
        if remote == "kernel.py":
            return 10
        if remote == "main.py":
            return 11
        if remote == "boot.py":
            return 12
        return 9

    if wanted and not pairs:
        raise ValueError("no manifest entries matched --only values: %s" % ", ".join(sorted(wanted)))
    return sorted(pairs, key=priority)


async def deploy(args):
    dev = await resolve_monocle(args)
    if dev is None:
        raise RuntimeError("No Monocle found. Is it awake and advertising?")

    if isinstance(dev, str):
        print("Connecting to address %s" % dev)
    else:
        print("Connecting to %s (%s)" % (dev.name or "<unnamed>", dev.address))
    async with BleakClient(dev) as client:
        await ensure_services(client)
        repl = NusRepl(client, verbose=args.verbose)
        await repl.start()
        await repl.interrupt_to_prompt()

        pairs = ordered_manifest(args.only)
        dirs = {str(Path(remote).parent).replace(".", "") for _src, remote in pairs if str(Path(remote).parent) != "."}
        dirs = {d for d in dirs if d}
        if dirs:
            print("Ensuring directories:", ", ".join(sorted(dirs)))
            await repl.exec_snippet(mkdir_snippet(dirs), timeout=8.0)

        for src, remote in pairs:
            if not src.exists():
                raise FileNotFoundError(src)
            payload = src.read_bytes()
            tmp = remote + ".tmp"
            print("Uploading %-24s %6d bytes" % (remote, len(payload)))

            await repl.exec_snippet(
                "import os\n"
                "try:\n"
                "    os.remove(%r)\n"
                "except OSError:\n"
                "    pass\n"
                "f = open(%r, 'wb')" % (tmp, tmp),
                timeout=8.0,
            )
            for off in range(0, len(payload), args.chunk_size):
                chunk = payload[off:off + args.chunk_size]
                await repl.line("n=f.write(%r)" % chunk, timeout=8.0)
            await repl.line("f.close()", timeout=8.0)
            await repl.exec_snippet(
                "import os\n"
                "try:\n"
                "    os.remove(%r)\n"
                "except OSError:\n"
                "    pass\n"
                "os.rename(%r, %r)\n"
                "print('SIZE', os.stat(%r)[6])"
                % (remote, tmp, remote, remote),
                timeout=8.0,
            )

        print("Clearing recovery counters")
        await repl.exec_snippet(
            "import os\n"
            "try:\n"
            "    f = open('pm_boot_count.txt', 'w')\n"
            "    f.write('0')\n"
            "    f.close()\n"
            "except Exception:\n"
            "    pass\n"
            "try:\n"
            "    os.remove('pm_safe_request.txt')\n"
            "except OSError:\n"
            "    pass",
            timeout=8.0,
        )

        if args.reset:
            print("Resetting Monocle")
            await repl.line(
                "import device; device.reset()",
                timeout=1.0,
                expect_prompt=False,
            )
        else:
            print("Deploy complete. Reset the Monocle to boot PrismOS.")


async def repl_command(args):
    dev = await resolve_monocle(args)
    if dev is None:
        raise RuntimeError("No Monocle found. Is it awake and advertising?")
    async with BleakClient(dev) as client:
        await ensure_services(client)
        repl = NusRepl(client, verbose=True)
        await repl.start()
        await repl.interrupt_to_prompt()
        if args.code:
            await repl.line(args.code, timeout=args.timeout)


async def main_async(args):
    if args.command == "scan":
        rows = await scan(args.timeout, all_devices=args.all)
        if not rows:
            print("No Monocle-like BLE devices found.")
            return
        for row in rows:
            name, address, uuids, rssi = row
            print("%-24s %s rssi=%s %s" % (name or "<unnamed>", address, rssi, uuids))
        return
    if args.command == "deploy":
        await deploy(args)
        return
    if args.command == "repl":
        await repl_command(args)
        return
    raise ValueError(args.command)


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    scan_p = sub.add_parser("scan")
    scan_p.add_argument("--timeout", type=float, default=5.0)
    scan_p.add_argument("--all", action="store_true")

    deploy_p = sub.add_parser("deploy")
    deploy_p.add_argument("--scan-timeout", type=float, default=8.0)
    deploy_p.add_argument("--address", default=None, help="Connect to a known CoreBluetooth device UUID/address without scanning.")
    deploy_p.add_argument("--allow-scan", action="store_true", help="Permit auto-selecting a Monocle-like BLE device when --address is omitted.")
    deploy_p.add_argument("--chunk-size", type=int, default=160)
    deploy_p.add_argument("--prefer-safe", action="store_true")
    deploy_p.add_argument("--reset", action="store_true")
    deploy_p.add_argument("--verbose", action="store_true")
    deploy_p.add_argument("--only", action="append", help="Upload only a manifest local path or remote path; may be repeated.")

    repl_p = sub.add_parser("repl")
    repl_p.add_argument("--scan-timeout", type=float, default=8.0)
    repl_p.add_argument("--address", default=None, help="Connect to a known CoreBluetooth device UUID/address without scanning.")
    repl_p.add_argument("--allow-scan", action="store_true", help="Permit auto-selecting a Monocle-like BLE device when --address is omitted.")
    repl_p.add_argument("--timeout", type=float, default=8.0)
    repl_p.add_argument("--prefer-safe", action="store_true")
    repl_p.add_argument("code", nargs="?")

    try:
        asyncio.run(main_async(parser.parse_args()))
    except KeyboardInterrupt:
        raise SystemExit(130)


if __name__ == "__main__":
    main()
