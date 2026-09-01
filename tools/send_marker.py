#!/usr/bin/env python3
"""Send a plain, integer, or JSON UDP marker to the unified app."""

import argparse
import socket

parser = argparse.ArgumentParser()
parser.add_argument("marker")
parser.add_argument("--host", default="127.0.0.1")
parser.add_argument("--port", type=int, default=15333)
args = parser.parse_args()

with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
    sock.sendto(args.marker.encode("utf-8"), (args.host, args.port))
