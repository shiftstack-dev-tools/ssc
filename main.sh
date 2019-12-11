#!/usr/bin/env bash

set -Eeuo pipefail

default_release_image_base='registry.svc.ci.openshift.org/ocp/release'
default_release_image_tag='4.3'

print_help() {
	echo "This is the help."
}

unknown_flag() {
	print_help
	exit 1
}

which_docker_runtime() {
	local -a docker_runtimes=("podman" "docker")
	for runtime in "${docker_runtimes[@]}"; do
		local which
		which="$(command -v "$runtime")"
		if [ -x "$which" ]; then
			echo "$which"
			return 0
		fi
	done

	# shellcheck disable=SC2016
	>&2 echo 'Docker runtime not found. Please make podman or docker available in $path.'

	return 1
}

while getopts i:o:f:h opt; do
	case "$opt" in
		i) release_image="$OPTARG" ;;
		o) dst_image="$OPTARG"     ;;
		f) cert_file="$OPTARG"     ;;
		h) print_help; exit 0      ;;
		*) unknown_flag            ;;
	esac
done

release_image="${release_image:-${default_release_image_base}:${default_release_image_tag}}"
docker_runtime="$(which_docker_runtime)"

image_references="$(mktemp)"
"$docker_runtime" pull "$release_image"
"$docker_runtime" run --rm -it \
	--entrypoint sh \
	"$release_image" \
	-c ' cat /release-manifests/image-references' > "$image_references"

echo "image_references in $image_references"
