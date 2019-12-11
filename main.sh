#!/usr/bin/env bash

set -Eeuo pipefail

print_help() {
	echo "Not implemented"
}

while getopts o: opt; do
	case "$opt" in
		o) dst_image="$OPTARG"  ;;
		h) print_help; exit 0   ;;
	esac
done
