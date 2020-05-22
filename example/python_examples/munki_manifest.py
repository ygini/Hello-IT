#!/usr/bin/env python3

from helloit_lib import HelloIT
import plistlib

h = HelloIT()


def munki_manifest():
    try:
        with open("/Library/Managed Preferences/ManagedInstalls.plist", "rb") as fp:
            pl = plistlib.load(fp)
            return pl["ClientIdentifier"]
    except FileNotFoundError:
        try:
            with open("/Library/Preferences/ManagedInstalls.plist", "rb") as fp:
                pl = plistlib.load(fp)
                return pl["ClientIdentifier"]
        except FileNotFoundError:
            return False


def main():
    if munki_manifest() is not None:
        h.updateTitle(f"Manifest: {munki_manifest()}")
    else:
        h.updateTitle(
            "Your manifest is not found. Managed Software Center requires this. Please contact IT."
        )


if __name__ == "__main__":
    main()
