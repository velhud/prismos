#!/usr/bin/env python3
"""Print detailed BLE advertisements for Monocle recovery triage."""

import argparse
import asyncio
import binascii
import time

from bleak import BleakScanner


def fmt_mapping_bytes(mapping):
    parts = []
    for key, value in sorted((mapping or {}).items(), key=lambda item: str(item[0])):
        raw = bytes(value)
        parts.append(f"{key}:{binascii.hexlify(raw).decode()}")
    return ",".join(parts)


def device_name(device, advertisement):
    return (
        getattr(advertisement, "local_name", None)
        or getattr(device, "name", None)
        or "<unnamed>"
    )


async def main_async(args):
    rows = {}

    def on_detect(device, advertisement):
        name = device_name(device, advertisement)
        address = getattr(device, "address", "")
        service_uuids = ",".join(str(u).lower() for u in (advertisement.service_uuids or []))
        service_data = fmt_mapping_bytes(advertisement.service_data)
        manufacturer_data = fmt_mapping_bytes(advertisement.manufacturer_data)
        tx_power = getattr(advertisement, "tx_power", None)
        rows[address] = (
            name,
            address,
            getattr(advertisement, "rssi", ""),
            service_uuids,
            service_data,
            manufacturer_data,
            "" if tx_power is None else str(tx_power),
        )

    scanner = BleakScanner(detection_callback=on_detect)
    await scanner.start()
    await asyncio.sleep(args.timeout)
    await scanner.stop()

    for name, address, rssi, uuids, service_data, manufacturer_data, tx_power in sorted(
        rows.values(),
        key=lambda row: (str(row[0]).lower(), str(row[1])),
    ):
        print(f"name={name} address={address} rssi={rssi} tx={tx_power}")
        if uuids:
            print(f"  services={uuids}")
        if service_data:
            print(f"  service_data={service_data}")
        if manufacturer_data:
            print(f"  manufacturer={manufacturer_data}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=10.0)
    args = parser.parse_args()
    started = time.monotonic()
    asyncio.run(main_async(args))
    print(f"elapsed={time.monotonic() - started:.1f}s")


if __name__ == "__main__":
    main()
