#!/usr/bin/env python3

from helloit_lib import HelloIT
# pylint: disable=no-name-in-module
from SystemConfiguration import SCDynamicStoreCreate, SCDynamicStoreCopyValue

h = HelloIT()

def get_interface(net_config):
    """Returns the active network interface of the Mac"""
    try:
        states = SCDynamicStoreCopyValue(net_config, "State:/Network/Global/IPv4")
        return states["PrimaryInterface"]
    except TypeError:
        pass


def get_info(net_config, interface):
    """Returns the IP address of the primary network interface"""
    addresses = SCDynamicStoreCopyValue(
        net_config, f"State:/Network/Interface/{interface}/IPv4"
    )
    try:
        return addresses["Addresses"][0]
    except TypeError:
        pass


def get_ip():
    net_config = SCDynamicStoreCreate(None, "net", None, None)
    interface = get_interface(net_config)
    ip = get_info(net_config, interface)

    return ip


def copy_ip(item):
    """Copies IP to clipboard"""
    from AppKit import NSPasteboard, NSArray

    pb = NSPasteboard.generalPasteboard()
    pb.clearContents()
    a = NSArray.arrayWithObject_(item)
    pb.writeObjects_(a)



def main():
    ip_address = get_ip()

    if ip_address:
        h.updateTitle(f"IP: {ip_address}")
        HelloIT.onClickAction(copy_ip(ip_address))
    elif ip_address is None:
        h.updateTitle("No network connection.")
        h.updateState(2)


if __name__ == "__main__":
    main()
