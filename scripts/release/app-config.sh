#!/usr/bin/env bash
# Shared release configuration for the supported app targets.
# Callers must define root_dir before sourcing this file.

release_app_variant="${FILMY_APP_VARIANT:-filmy}"
case "${release_app_variant}" in
  filmy)
    release_app_target="FilmyCamera"
    release_app_bundle_name="FilmyCamera"
    release_app_display_name="Filmy Camera"
    release_app_bundle_id="com.dheeraj.filmycamera"
    release_app_archive_default="${root_dir}/build/FilmyCamera.xcarchive"
    release_app_derived_data_default="${root_dir}/build/DerivedData"
    release_app_provenance_file="FilmyCamera.source-sha"
    release_app_icon_path="${root_dir}/FilmyCamera/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
    release_app_store_metadata_path="${root_dir}/docs/app-store/metadata-en-US.md"
    release_app_store_iphone_dir="${root_dir}/docs/app-store/screenshots/iphone-6.5-current"
    release_app_store_ipad_dir="${root_dir}/docs/app-store/screenshots/ipad-13-current"
    ;;
  g7)
    release_app_target="G7Camera"
    release_app_bundle_name="G7Camera"
    release_app_display_name="G7X Camera"
    release_app_bundle_id="com.dheeraj.g7camera"
    release_app_archive_default="${root_dir}/build/G7Camera.xcarchive"
    release_app_derived_data_default="${root_dir}/build/DerivedData-G7Camera"
    release_app_provenance_file="G7Camera.source-sha"
    release_app_icon_path="${root_dir}/G7Camera/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
    release_app_store_metadata_path="${root_dir}/docs/app-store/g7/metadata-en-US.md"
    release_app_store_iphone_dir="${root_dir}/docs/app-store/g7/screenshots/iphone"
    release_app_store_ipad_dir="${root_dir}/docs/app-store/g7/screenshots/ipad"
    ;;
  *)
    echo "ERROR: unsupported FILMY_APP_VARIANT '${release_app_variant}'; expected filmy or g7" >&2
    exit 64
    ;;
esac

release_app_dsym_name="${release_app_bundle_name}.app.dSYM"
release_app_iphone_width=1242
release_app_iphone_height=2688
release_app_ipad_width=2064
release_app_ipad_height=2752
