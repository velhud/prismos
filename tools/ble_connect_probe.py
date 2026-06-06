#!/usr/bin/env python3
"""Read-only BLE GATT service probe for explicit CoreBluetooth UUIDs."""

import argparse
import asyncio

from bleak import BleakClient


async def probe(address, timeout):
    print(f"PROBE {address}")
    try:
        async with BleakClient(address, timeout=timeout) as client:
            getter = getattr(client, "get_services", None)
            if getter is not None:
                result = getter()
                if hasattr(result, "__await__"):
                    await result
            services = list(client.services)
            if not services:
                print("  connected; no services listed")
                return
            for service in services:
                print(f"  service {service.uuid} {service.description}")
                for characteristic in service.characteristics:
                    props = ",".join(characteristic.properties or [])
                    print(f"    char {characteristic.uuid} props={props}")
    except Exception as exc:
        print(f"  ERROR {type(exc).__name__}: {exc}")


async def main_async(args):
    for address in args.address:
        await probe(address, args.timeout)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=4.0)
    parser.add_argument("address", nargs="+")
    asyncio.run(main_async(parser.parse_args()))


if __name__ == "__main__":
    main()
