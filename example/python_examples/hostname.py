#!/usr/bin/env python3

import platform
from helloit_lib import HelloIT

h = HelloIT()
hostname = platform.node()


def main():
    h.setEnabled("YES")
    h.updateTitle(f"Hostname: {hostname}")
    h.updateState("none")


if __name__ == "__main__":
    main()
