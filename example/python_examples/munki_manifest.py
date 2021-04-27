#!/usr/bin/env python3

"""
this requires pyobjc to be installed
"""

from CoreFoundation import CFPreferencesCopyAppValue
from helloit_lib import HelloIT

h = HelloIT()

def get_pref_value(bundle_id, pref_name):
    """
    borrowed this from https://gist.github.com/gregneagle/010b369e86410a2f279ff8e980585c68
    """
    return CFPreferencesCopyAppValue(pref_name, bundle_id)

def main():
    manifest = get_pref_value('ManagedInstalls', 'ClientIdentifier')
    if manifest is not None:
        h.updateTitle(f"Manifest: {manifest}")
    else:
        h.updateTitle(
            "Your manifest is not found. Managed Software Center requires this. Please contact IT."
        )


if __name__ == "__main__":
    main()
