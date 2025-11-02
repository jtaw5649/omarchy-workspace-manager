#!/usr/bin/env bash

owm_install_stage_files() {
	local version="$1"
	local source_root="$OWM_INSTALL_ROOT"
	local dest_root="$OWM_INSTALL_DEST"
	local version_dir="$dest_root/$version"

	owm_install_info "installing version $version to $version_dir"

	rm -rf "$version_dir"
	mkdir -p "$version_dir"
	export OWM_INSTALL_VERSION_DIR="$version_dir"

	local item
	for item in bin lib config README.md version install scripts; do
		if [[ -e "$source_root/$item" ]]; then
			if [[ -d "$source_root/$item" ]]; then
				mkdir -p "$version_dir/$item"
				cp -a "$source_root/$item/." "$version_dir/$item/"
			else
				cp "$source_root/$item" "$version_dir/$item"
			fi
		fi
	done

	if [[ -f "$source_root/install.sh" ]]; then
		cp "$source_root/install.sh" "$version_dir/install.sh"
		chmod +x "$version_dir/install.sh"
	fi

	chmod +x "$version_dir/bin/omarchy-workspace-manager"
	if [[ -d "$version_dir/lib" ]]; then
		find "$version_dir/lib" -type f -name '*.sh' -exec chmod +x {} +
	fi
	if [[ -d "$version_dir/install" ]]; then
		find "$version_dir/install" -type f -name '*.sh' -exec chmod +x {} +
	fi
	if [[ -d "$version_dir/scripts" ]]; then
		find "$version_dir/scripts" -type f -name '*.sh' -exec chmod +x {} +
	fi

	ln -sfn "$version_dir" "$dest_root/current"

	mkdir -p "$OWM_INSTALL_BIN_DIR"
	cat <<EOF >"$OWM_INSTALL_BIN_DIR/omarchy-workspace-manager"
#!/usr/bin/env bash
set -euo pipefail
export OWM_ROOT="$dest_root/current"
exec "\$OWM_ROOT/bin/omarchy-workspace-manager" "\$@"
EOF
	chmod +x "$OWM_INSTALL_BIN_DIR/omarchy-workspace-manager"
}
