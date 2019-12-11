#!/usr/bin/env bash

set -Eeuo pipefail

declare dst_image='' cert_file='' release_image='' prefix=''
declare -ra images_needing_ca=(
	'cloud-credential-operator'
	'cloud-provider-openstack'
	'cluster-api-provider-openstack'
	'cluster-image-registry-operator'
	'image-registry'
	'kubernetes-apiserver'
)

prefix="$(date +'%s')"

image_needs_ca() {
	declare current_image
	current_image="$1"

	for image_needing_ca in "${images_needing_ca[@]}"; do
		if [ "$image_needing_ca" == "$current_image" ]; then
			return 0
		fi
	done

	return 1
}

get_installer_release_image() {
	declare installer
	installer="$(command -v 'openshift-install')" || {
		# shellcheck disable=SC2016
		>&2 echo 'Could not determine the default OpenShift release image: `openshift-install` not found in $PATH.'
		>&2 echo 'Specify an image with the -i flag.'
		exit 3
	}

	"$installer" version | grep 'release image' | cut -d ' ' -f3
}

print_help() {
	echo 'ShiftStack SSC'
	echo
	echo 'Prepares an OpenShift installation over an OpenStack cluster running on self-signed certificates.'
	echo 'This script rebuilds administrative pod images for the OpenShift parts that need to interact with OpenStack, adding the given CA bundle.'
	echo
	echo -e 'Requirements:'
	echo -e '\t* bash 4.4+'
	echo -e '\t* grep'
	echo -e '\t* jq [ https://stedolan.github.io/jq ]'
	echo -e '\t* either podman or docker'
	echo -e '\t* openshift-installer for automatic image detection (required if "-i" is not used)'
	echo -e '\t* oc, the OpenShift command-line client'
	echo
	echo -e 'Usage:'
	echo -e "${0} [-i release_image] -o dst_image -f cert_file"
	# shellcheck disable=SC2016
	echo -e '\t-i\tSpecify the release image to be used in the build. By default, the image is determined using `openshift-install`, which must be in $PATH'
	echo -e '\t-o\tSpecify the destination registry image. The container runtime must have push privileges, as several images will be pushed there.'
	echo -e '\t-f\tSpecify the PEM or DER file containing the certificate.'
	echo -e '\t-h\tPrint this help'
}

unknown_flag() {
	print_help
	exit 1
}

which_docker_runtime() {
	declare -a docker_runtimes=("podman" "docker")
	for runtime in "${docker_runtimes[@]}"; do
		declare which
		which="$(command -v "$runtime")" || true
		if [ -x "$which" ]; then
			echo "$which"
			return 0
		fi
	done

	# shellcheck disable=SC2016
	>&2 echo 'Docker runtime not found. Please make podman or docker available in $path.'

	return 1
}

# Outputs the image-references JSON file from the given release image
extract_release_image_references() {
	declare release_image docker_runtime local_image
	release_image="$1"
	docker_runtime="$(which_docker_runtime)"

	local_image="$("$docker_runtime" pull "$release_image" 2>/dev/null)"
	"$docker_runtime" run --rm \
		--entrypoint sh \
		"$local_image" \
		-c 'cat /release-manifests/image-references'
}

# Parses the JSON data from `extract_release_image_references` and outputs the
# images one per line, in the format:
#
# image_name image_kind image_from
collect_image_references() {
	declare release_image image_references
	release_image="$1"

	image_references="$(mktemp)"
	extract_release_image_references "$release_image" > "$image_references"
	jq -r '.spec.tags[] | "\(.name) \(.from.kind) \(.from.name)"' "$image_references"
}

docker_push() {
	declare docker_runtime image_name
	docker_runtime="$(which_docker_runtime)"
	image_name="$1"

	"$docker_runtime" push -q "$image_name"
}

# On success, echoes the newly-built image ID
add_ca() {
	declare docker_runtime image_name image_kind image_from image_override cert_file
	docker_runtime="$(which_docker_runtime)"
	image_name="$1"
	image_kind="$2"
	image_from="$3"
	cert_file="$4"
	image_override="$5"

	if [ "$image_kind" != "DockerImage" ]; then
		echo "Unknown image kind for '${image_name}': '${image_kind}'"
		exit 2
	fi

	# Build a Docker image:
	# * using the original image as base
	# * injecting the CA bundle
	# * using the folder where the CA bundle sits as the Context folder
	"$docker_runtime" build -t "$image_override" -f <(cat <<EOF
FROM $image_from
COPY ./$(basename "$cert_file") /etc/pki/ca-trust/source/anchors/
RUN update-ca-trust extract
EOF
) "$(dirname "$cert_file")"
}


### Done with declarations, start doing something

# Parse flags
while getopts i:o:f:h opt; do
	case "$opt" in
		i) release_image="$OPTARG" ;;
		o) dst_image="$OPTARG"     ;;
		f) cert_file="$OPTARG"     ;;
		h) print_help; exit 0      ;;
		*) unknown_flag            ;;
	esac
done


# Validate inputs
if [ -z "$cert_file" ]; then
	>&2 echo 'Specify the CA-bundle file with "-f"'
	exit 4
fi
if [ -z "$dst_image" ]; then
	>&2 echo 'Specify with "-o" the destination where the built images will be pushed'
	exit 4
fi


# If release_image is not specified with the "-i" flag, then ask openshift-install
release_image="${release_image:-$(get_installer_release_image)}"
>&2 echo "Using release image: ${release_image}"

parsed_lines="$(mktemp)"
collect_image_references "$release_image" > "$parsed_lines"
>&2 echo "Parsed the release data, found $(cat "$parsed_lines" | wc -l) images"

declare -A override_images

while read -r line; do
	declare image_name image_kind image_from image_override
	mapfile -td ' ' < <(printf "%s" "$line")
	image_name="${MAPFILE[0]}"
	image_kind="${MAPFILE[1]}"
	image_from="${MAPFILE[2]}"

	image_needs_ca "$image_name" && {
		>&2 echo "Adding CA to $image_name"
		image_override="${dst_image}:${prefix}_${image_name}"
		>&2 echo "pulling $image_from"
		add_ca "$image_name" "$image_kind" "$image_from" "$cert_file" "$image_override" >/dev/null
		>&2 echo "pushing $image_override"
		docker_push "$image_override" >/dev/null
		override_images["$image_name"]="$image_override"
	} || true
done < "$parsed_lines"

# Build a new release image
oc adm release new -n ocp \
	--from-release "$release_image" \
	--to-image "${dst_image}:${prefix}_release" \
	$(for name in ${!override_images[*]}; do printf '%s=%s ' "$name" "${override_images[$name]}" ; done)
