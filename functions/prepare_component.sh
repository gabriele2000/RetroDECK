#!/bin/bash

prepare_component() {
  # This function will perform one of several actions on one or more components
  # The actions currently include "reset" and "postmove"
  # The "reset" action will initialize the component
  # The "postmove" action will update the component settings after one or more RetroDECK folders were moved
  # An component can be called by name, by parent folder name in the $XDG_CONFIG_HOME root or use the option "all" to perform the action on all components equally
  # USAGE: prepare_component "$action" "$component" "$call_source(optional)"

  if [[ "$1" == "--list" ]]; then
    # uses jq to extract all the emulators (components) that don't have resettable: false in the features.json and separate them with "|"
    resettable_components=$(jq -r '
      [(.emulator | to_entries[]) |
      select(.value.core == null and .value.resettable != false and .value.ponzu != true ) |
      .key] | sort | join("|")
    ' "$features")

    # uses sed to create a list like this
    pretty_resettable_components=$(echo "$resettable_components" | sed 's/|/ /g')

    isponzu=""
    if [[ $(get_setting_value "$rd_conf" "akai_ponzu" "retrodeck" "options") == "true" ]]; then
      isponzu+=" citra"
    fi
    if [[ $(get_setting_value "$rd_conf" "kiroi_ponzu" "retrodeck" "options") == "true" ]]; then
      isponzu+=" yuzu"
    fi

    echo "${pretty_resettable_components}${isponzu}"
    exit 0
  fi

  if [[ "$1" == "--factory-reset" ]]; then
    log i "User requested full RetroDECK reset"
    rm -f "$lockfile" && log d "Lockfile removed"
  fi

  action="$1"
  components=$(echo "${@:2}" | tr '[:upper:]' '[:lower:]' | tr ',' ' ')
  call_source="$3"
  component_found="false"

  if [[ -z "$components" ]]; then
    echo "No components or action specified. Exiting."
    exit 1
  fi
  log d "Preparing components: \"$components\", action: \"$action\""

  for component in $components; do
    if [[ "$component" == "retrodeck" ]]; then
      log i "--------------------------------"
      log i "Prepearing RetroDECK framework"
      log i "--------------------------------"
      component_found="true"
      if [[ "$action" == "reset" ]]; then # Update the paths of all folders in retrodeck.cfg and create them
        while read -r config_line; do
          local current_setting_name=$(get_setting_name "$config_line" "retrodeck")
          if [[ ! $current_setting_name =~ (rdhome|sdcard) ]]; then # Ignore these locations
            local current_setting_value=$(get_setting_value "$rd_conf" "$current_setting_name" "retrodeck" "paths")
            log d "Red setting: $current_setting_name=$current_setting_value"
            # Extract the part of the setting value after "retrodeck/"
            local relative_path="${current_setting_value#*retrodeck/}"
            # Construct the new setting value
            local new_setting_value="$rdhome/$relative_path"
            log d "New setting: $current_setting_name=$new_setting_value"
            # Declare the global variable with the new setting value
            declare -g "$current_setting_name=$new_setting_value"
            log d "Setting: $current_setting_name=$current_setting_value"
            if [[ ! $current_setting_name == "logs_folder" ]]; then # Don't create a logs folder normally, we want to maintain the current files exactly to not lose early-install logs.
              create_dir "$new_setting_value"
            else # Log folder-specific actions
              mv "$rd_logs_folder" "$logs_folder" # Move existing logs folder from internal to userland
              ln -sf "$logs_folder" "$rd_logs_folder" # Link userland logs folder back to statically-written location
              log d "Logs folder moved to $logs_folder and linked back to $rd_logs_folder"
            fi
          fi
        done < <(grep -v '^\s*$' "$rd_conf" | awk '/^\[paths\]/{f=1;next} /^\[/{f=0} f')
        create_dir "$XDG_CONFIG_HOME/retrodeck/godot" # TODO: what is this for? Can we delete it or add it to the retrodeck.cfg so the folder will be created by the above script?
        
      fi
      if [[ "$action" == "postmove" ]]; then # Update the paths of any folders that came with the retrodeck folder during a move
        while read -r config_line; do
          local current_setting_name=$(get_setting_name "$config_line" "retrodeck")
          if [[ ! $current_setting_name =~ (rdhome|sdcard) ]]; then # Ignore these locations
            local current_setting_value=$(get_setting_value "$rd_conf" "$current_setting_name" "retrodeck" "paths")
            if [[ -d "$rdhome/${current_setting_value#*retrodeck/}" ]]; then # If the folder exists at the new ~/retrodeck location
                declare -g "$current_setting_name=$rdhome/${current_setting_value#*retrodeck/}"
            fi
          fi
        done < <(grep -v '^\s*$' "$rd_conf" | awk '/^\[paths\]/{f=1;next} /^\[/{f=0} f')
        dir_prep "$logs_folder" "$rd_logs_folder"
      fi
    fi

    if [[ "$component" =~ ^(es-de|all)$ ]]; then # For use after ESDE-related folders are moved or a reset
      component_found="true"
      log i "--------------------------------"
      log i "Prepearing ES-DE"
      log i "--------------------------------"
      if [[ "$action" == "reset" ]]; then
        rm -rf "$XDG_CONFIG_HOME/ES-DE"
        create_dir "$XDG_CONFIG_HOME/ES-DE/settings"
        log d "Prepearing es_settings.xml"
        cp -f "/app/retrodeck/es_settings.xml" "$XDG_CONFIG_HOME/ES-DE/settings/es_settings.xml"
        set_setting_value "$es_settings" "ROMDirectory" "$roms_folder" "es_settings"
        set_setting_value "$es_settings" "MediaDirectory" "$media_folder" "es_settings"
        set_setting_value "$es_settings" "UserThemeDirectory" "$themes_folder" "es_settings"
        dir_prep "$rdhome/ES-DE/gamelists" "$XDG_CONFIG_HOME/ES-DE/gamelists"
        dir_prep "$rdhome/ES-DE/collections" "$XDG_CONFIG_HOME/ES-DE/collections"
        dir_prep "$rdhome/ES-DE/custom_systems" "$XDG_CONFIG_HOME/ES-DE/custom_systems"
        log d "Generating roms system folders"
        es-de --create-system-dirs
        update_splashscreens
      fi
      if [[ "$action" == "postmove" ]]; then
        set_setting_value "$es_settings" "ROMDirectory" "$roms_folder" "es_settings"
        set_setting_value "$es_settings" "MediaDirectory" "$media_folder" "es_settings"
        set_setting_value "$es_settings" "UserThemeDirectory" "$themes_folder" "es_settings"
        dir_prep "$rdhome/gamelists" "$XDG_CONFIG_HOME/ES-DE/gamelists"
      fi
    fi

    if [[ "$component" =~ ^(steam-rom-manager|steamrommanager|all)$ ]]; then
    component_found="true"
      log i "-----------------------------"
      log i "Prepearing Steam ROM Manager"
      log i "-----------------------------"
      
      create_dir -d "$srm_userdata"
      cp -fv "$config/steam-rom-manager/"*.json "$srm_userdata"
      cp -fvr "$config/steam-rom-manager/manifests" "$srm_userdata"

      log i "Updating steamDirectory and romDirectory lines in $srm_userdata/userSettings.json"
      jq '.environmentVariables.steamDirectory = "'"$HOME"'/.steam/steam"' "$srm_userdata/userSettings.json" > "$srm_userdata/tmp.json" && mv -f "$srm_userdata/tmp.json" "$srm_userdata/userSettings.json"
      jq '.environmentVariables.romsDirectory = "'"$rdhome"'/.sync"' "$srm_userdata/userSettings.json" > "$srm_userdata/tmp.json" && mv -f "$srm_userdata/tmp.json" "$srm_userdata/userSettings.json"

      get_steam_user
    fi

    if [[ "$component" =~ ^(retroarch|all)$ ]]; then
    component_found="true"
      log i "--------------------------------"
      log i "Prepearing RetroArch"
      log i "--------------------------------"
      if [[ "$action" == "reset" ]]; then # Run reset-only commands
        if [[ $multi_user_mode == "true" ]]; then # Multi-user actions
          create_dir -d "$multi_user_data_folder/$SteamAppUser/config/retroarch"
          cp -fv "$config/retroarch/retroarch.cfg" "$multi_user_data_folder/$SteamAppUser/config/retroarch/"
          cp -fv "$config/retroarch/retroarch-core-options.cfg" "$multi_user_data_folder/$SteamAppUser/config/retroarch/"
        else # Single-user actions
          create_dir -d "$XDG_CONFIG_HOME/retroarch"
          dir_prep "$bios_folder" "$XDG_CONFIG_HOME/retroarch/system"
          dir_prep "$rdhome/logs/retroarch" "$XDG_CONFIG_HOME/retroarch/logs"
          create_dir -d "$XDG_CONFIG_HOME/retroarch/shaders/"
          if [[ -d "$cheats_folder/retroarch" && "$(ls -A "$cheats_folder/retroarch")" ]]; then
            backup_file="$backups_folder/cheats/retroarch-$(date +%y%m%d).tar.gz"
            create_dir "$(dirname "$backup_file")"
            tar -czf "$backup_file" -C "$cheats_folder" retroarch
            log i "RetroArch cheats backed up to $backup_file"
          fi
          create_dir -d "$cheats_folder/retroarch"
          tar --strip-components=1 -xzf "/app/retrodeck/cheats/retroarch.tar.gz" -C "$cheats_folder/retroarch" --overwrite
          cp -rf "/app/share/libretro/shaders" "$XDG_CONFIG_HOME/retroarch/"
          dir_prep "$shaders_folder/retroarch" "$XDG_CONFIG_HOME/retroarch/shaders"
          cp -fv "$config/retroarch/retroarch.cfg" "$XDG_CONFIG_HOME/retroarch/"
          cp -fv "$config/retroarch/retroarch-core-options.cfg" "$XDG_CONFIG_HOME/retroarch/"
          rsync -rlD --mkpath "$config/retroarch/core-overrides/" "$XDG_CONFIG_HOME/retroarch/config/"
          rsync -rlD --mkpath "$config/retrodeck/presets/remaps/" "$XDG_CONFIG_HOME/retroarch/config/remaps/"
          dir_prep "$borders_folder" "$XDG_CONFIG_HOME/retroarch/overlays/borders"
          set_setting_value "$raconf" "savefile_directory" "$saves_folder" "retroarch"
          set_setting_value "$raconf" "savestate_directory" "$states_folder" "retroarch"
          set_setting_value "$raconf" "screenshot_directory" "$screenshots_folder" "retroarch"
          set_setting_value "$raconf" "log_dir" "$logs_folder" "retroarch"
          set_setting_value "$raconf" "rgui_browser_directory" "$roms_folder" "retroarch"
          set_setting_value "$raconf" "cheat_database_path" "$cheats_folder/retroarch" "retroarch"
        fi
        # Shared actions

        create_dir "$bios_folder/np2kai"
        create_dir "$bios_folder/dc"
        create_dir "$bios_folder/Mupen64plus"
        create_dir "$bios_folder/quasi88"

        retroarch_updater

        # FBNEO
        log i "--------------------------------"
        log i "Prepearing FBNEO_LIBRETRO"
        log i "--------------------------------"
        create_dir "$bios_folder/fbneo/samples"
        # TODO: cheats support
        create_dir "$bios_folder/fbneo/cheats"
        create_dir "$bios_folder/fbneo/blend"
        dir_prep "$mods_folder/FBNeo" "$bios_folder/fbneo/patched"

        # PPSSPP
        log i "--------------------------------"
        log i "Prepearing PPSSPP_LIBRETRO"
        log i "--------------------------------"
        if [ -d "$bios_folder/PPSSPP/flash0/font" ]
        then
          mv -fv "$bios_folder/PPSSPP/flash0/font" "$bios_folder/PPSSPP/flash0/font.bak"
        fi
        cp -rf "/app/retrodeck/extras/PPSSPP" "$bios_folder/PPSSPP"
        if [ -d "$bios_folder/PPSSPP/flash0/font.bak" ]
        then
          mv -f "$bios_folder/PPSSPP/flash0/font.bak" "$bios_folder/PPSSPP/flash0/font"
        fi

        # MSX / SVI / ColecoVision / SG-1000
        log i "-----------------------------------------------------------"
        log i "Prepearing MSX / SVI / ColecoVision / SG-1000 LIBRETRO"
        log i "-----------------------------------------------------------"
        log i "Copying \"/app/retrodeck/extras/MSX/Databases\" in \"$bios_folder/Databases\""
        cp -rf "/app/retrodeck/extras/MSX/Databases" "$bios_folder/Databases"
        log i "Copying \"/app/retrodeck/extras/MSX/Machines\" in \"$bios_folder/Machines\""
        cp -rf "/app/retrodeck/extras/MSX/Machines" "$bios_folder/Machines"

        # AMIGA
        log i "-----------------------------------------------------------"
        log i "Prepearing AMIGA LIBRETRO"
        log i "-----------------------------------------------------------"
        log i "Copying \"/app/retrodeck/extras/Amiga/capsimg.so\" in \"$bios_folder/capsimg.so\""
        cp -f "/app/retrodeck/extras/Amiga/capsimg.so" "$bios_folder/capsimg.so"

        # ScummVM
        log i "-----------------------------------------------------------"
        log i "Prepearing ScummVM LIBRETRO"
        log i "-----------------------------------------------------------"
        cp -fv "$config/retroarch/scummvm.ini" "$ra_scummvm_conf"
        create_dir "$mods_folder/RetroArch/ScummVM/icons"
        log i "Installing ScummVM assets"
        unzip -o "$config/retroarch/ScummVM.zip" 'scummvm/extra/*' -d /tmp
        unzip -o "$config/retroarch/ScummVM.zip" 'scummvm/theme/*' -d /tmp
        mv -f /tmp/scummvm/extra "$mods_folder/RetroArch/ScummVM"
        mv -f /tmp/scummvm/theme "$mods_folder/RetroArch/ScummVM"
        rm -rf /tmp/extra /tmp/theme
        set_setting_value "$ra_scummvm_conf" "iconspath" "$mods_folder/RetroArch/ScummVM/icons" "libretro_scummvm" "scummvm"
        set_setting_value "$ra_scummvm_conf" "extrapath" "$mods_folder/RetroArch/ScummVM/extra" "libretro_scummvm" "scummvm"
        set_setting_value "$ra_scummvm_conf" "themepath" "$mods_folder/RetroArch/ScummVM/theme" "libretro_scummvm" "scummvm"
        set_setting_value "$ra_scummvm_conf" "savepath" "$saves_folder/scummvm" "libretro_scummvm" "scummvm"
        set_setting_value "$ra_scummvm_conf" "browser_lastpath" "$roms_folder/scummvm" "libretro_scummvm" "scummvm"

        dir_prep "$texture_packs_folder/RetroArch-Mesen" "$XDG_CONFIG_HOME/retroarch/system/HdPacks"
        dir_prep "$texture_packs_folder/RetroArch-Mupen64Plus/cache" "$XDG_CONFIG_HOME/retroarch/system/Mupen64plus/cache"
        dir_prep "$texture_packs_folder/RetroArch-Mupen64Plus/hires_texture" "$XDG_CONFIG_HOME/retroarch/system/Mupen64plus/hires_texture"

        # Reset default preset settings
        set_setting_value "$rd_conf" "retroarch" "$(get_setting_value "$rd_defaults" "retroarch" "retrodeck" "cheevos")" "retrodeck" "cheevos"
        set_setting_value "$rd_conf" "retroarch" "$(get_setting_value "$rd_defaults" "retroarch" "retrodeck" "cheevos_hardcore")" "retrodeck" "cheevos_hardcore"
        set_setting_value "$rd_conf" "gb" "$(get_setting_value "$rd_defaults" "gb" "retrodeck" "borders")" "retrodeck" "borders"
        set_setting_value "$rd_conf" "gba" "$(get_setting_value "$rd_defaults" "gba" "retrodeck" "borders")" "retrodeck" "borders"
        set_setting_value "$rd_conf" "gbc" "$(get_setting_value "$rd_defaults" "gbc" "retrodeck" "borders")" "retrodeck" "borders"
        set_setting_value "$rd_conf" "genesis" "$(get_setting_value "$rd_defaults" "genesis" "retrodeck" "borders")" "retrodeck" "borders"
        set_setting_value "$rd_conf" "gg" "$(get_setting_value "$rd_defaults" "gg" "retrodeck" "borders")" "retrodeck" "borders"
        set_setting_value "$rd_conf" "n64" "$(get_setting_value "$rd_defaults" "n64" "retrodeck" "borders")" "retrodeck" "borders"
        set_setting_value "$rd_conf" "psx_ra" "$(get_setting_value "$rd_defaults" "psx_ra" "retrodeck" "borders")" "retrodeck" "borders"
        set_setting_value "$rd_conf" "snes" "$(get_setting_value "$rd_defaults" "snes" "retrodeck" "borders")" "retrodeck" "borders"
        set_setting_value "$rd_conf" "genesis" "$(get_setting_value "$rd_defaults" "genesis" "retrodeck" "widescreen")" "retrodeck" "widescreen"
        set_setting_value "$rd_conf" "n64" "$(get_setting_value "$rd_defaults" "n64" "retrodeck" "widescreen")" "retrodeck" "widescreen"
        set_setting_value "$rd_conf" "psx_ra" "$(get_setting_value "$rd_defaults" "psx_ra" "retrodeck" "widescreen")" "retrodeck" "widescreen"
        set_setting_value "$rd_conf" "snes" "$(get_setting_value "$rd_defaults" "snes" "retrodeck" "widescreen")" "retrodeck" "widescreen"
        set_setting_value "$rd_conf" "gb" "$(get_setting_value "$rd_defaults" "gb" "retrodeck" "abxy_button_swap")" "retrodeck" "abxy_button_swap"
        set_setting_value "$rd_conf" "gba" "$(get_setting_value "$rd_defaults" "gba" "retrodeck" "abxy_button_swap")" "retrodeck" "abxy_button_swap"
        set_setting_value "$rd_conf" "gbc" "$(get_setting_value "$rd_defaults" "gbc" "retrodeck" "abxy_button_swap")" "retrodeck" "abxy_button_swap"
        set_setting_value "$rd_conf" "n64" "$(get_setting_value "$rd_defaults" "gb" "retrodeck" "abxy_button_swap")" "retrodeck" "abxy_button_swap"
        set_setting_value "$rd_conf" "snes" "$(get_setting_value "$rd_defaults" "gba" "retrodeck" "abxy_button_swap")" "retrodeck" "abxy_button_swap"
        set_setting_value "$rd_conf" "retroarch" "$(get_setting_value "$rd_defaults" "retroarch" "retrodeck" "savestate_auto_load")" "retrodeck" "savestate_auto_load"
        set_setting_value "$rd_conf" "retroarch" "$(get_setting_value "$rd_defaults" "retroarch" "retrodeck" "savestate_auto_save")" "retrodeck" "savestate_auto_save"
      fi
      if [[ "$action" == "postmove" ]]; then # Run only post-move commands
        dir_prep "$bios_folder" "$XDG_CONFIG_HOME/retroarch/system"
        dir_prep "$logs_folder/retroarch" "$XDG_CONFIG_HOME/retroarch/logs"
        dir_prep "$shaders_folder/retroarch" "$XDG_CONFIG_HOME/retroarch/shaders"
        dir_prep "$texture_packs_folder/RetroArch-Mesen" "$XDG_CONFIG_HOME/retroarch/system/HdPacks"
        dir_prep "$texture_packs_folder/RetroArch-Mupen64Plus/cache" "$XDG_CONFIG_HOME/retroarch/system/Mupen64plus/cache"
        dir_prep "$texture_packs_folder/RetroArch-Mupen64Plus/hires_texture" "$XDG_CONFIG_HOME/retroarch/system/Mupen64plus/hires_texture"
        set_setting_value "$raconf" "savefile_directory" "$saves_folder" "retroarch"
        set_setting_value "$raconf" "savestate_directory" "$states_folder" "retroarch"
        set_setting_value "$raconf" "screenshot_directory" "$screenshots_folder" "retroarch"
        set_setting_value "$raconf" "log_dir" "$logs_folder" "retroarch"
      fi
    fi

    if [[ $(get_setting_value "$rd_conf" "akai_ponzu" "retrodeck" "options") == "true" ]]; then
      if [[ "$component" =~ ^(citra|citra-emu|all)$ ]]; then
      component_found="true"
        if [[ "$action" == "reset" ]]; then # Run reset-only commands
          log i "------------------------"
          log i "Prepearing CITRA"
          log i "------------------------"
          if [[ $multi_user_mode == "true" ]]; then # Multi-user actions
            create_dir -d "$multi_user_data_folder/$SteamAppUser/config/citra-emu"
            cp -fv "$config/citra/qt-config.ini" "$multi_user_data_folder/$SteamAppUser/config/citra-emu/qt-config.ini"
            set_setting_value "$multi_user_data_folder/$SteamAppUser/config/citra-emu/qt-config.ini" "nand_directory" "$saves_folder/n3ds/citra/nand/" "citra" "Data%20Storage"
            set_setting_value "$multi_user_data_folder/$SteamAppUser/config/citra-emu/qt-config.ini" "sdmc_directory" "$saves_folder/n3ds/citra/sdmc/" "citra" "Data%20Storage"
            set_setting_value "$multi_user_data_folder/$SteamAppUser/config/citra-emu/qt-config.ini" "Paths\gamedirs\3\path" "$roms_folder/n3ds" "citra" "UI"
            set_setting_value "$multi_user_data_folder/$SteamAppUser/config/citra-emu/qt-config.ini" "Paths\screenshotPath" "$screenshots_folder" "citra" "UI"
            dir_prep "$multi_user_data_folder/$SteamAppUser/config/citra-emu" "$XDG_CONFIG_HOME/citra-emu"
          else # Single-user actions
            create_dir -d "$XDG_CONFIG_HOME/citra-emu/"
            cp -f "$config/citra/qt-config.ini" "$XDG_CONFIG_HOME/citra-emu/qt-config.ini"
            set_setting_value "$citraconf" "nand_directory" "$saves_folder/n3ds/citra/nand/" "citra" "Data%20Storage"
            set_setting_value "$citraconf" "sdmc_directory" "$saves_folder/n3ds/citra/sdmc/" "citra" "Data%20Storage"
            set_setting_value "$citraconf" "Paths\gamedirs\3\path" "$roms_folder/n3ds" "citra" "UI"
            set_setting_value "$citraconf" "Paths\screenshotPath" "$screenshots_folder" "citra" "UI"
          fi
          # Shared actions
          create_dir "$saves_folder/n3ds/citra/nand/"
          create_dir "$saves_folder/n3ds/citra/sdmc/"
          dir_prep "$bios_folder/citra/sysdata" "$XDG_DATA_HOME/citra-emu/sysdata"
          dir_prep "$logs_folder/citra" "$XDG_DATA_HOME/citra-emu/log"
          dir_prep "$mods_folder/Citra" "$XDG_DATA_HOME/citra-emu/load/mods"
          dir_prep "$texture_packs_folder/Citra" "$XDG_DATA_HOME/citra-emu/load/textures"

          # Reset default preset settings
          set_setting_value "$rd_conf" "citra" "$(get_setting_value "$rd_defaults" "citra" "retrodeck" "abxy_button_swap")" "retrodeck" "abxy_button_swap"
          set_setting_value "$rd_conf" "citra" "$(get_setting_value "$rd_defaults" "citra" "retrodeck" "ask_to_exit")" "retrodeck" "ask_to_exit"
        fi
        if [[ "$action" == "postmove" ]]; then # Run only post-move commands
          dir_prep "$bios_folder/citra/sysdata" "$XDG_DATA_HOME/citra-emu/sysdata"
          dir_prep "$rdhome/logs/citra" "$XDG_DATA_HOME/citra-emu/log"
          dir_prep "$mods_folder/Citra" "$XDG_DATA_HOME/citra-emu/load/mods"
          dir_prep "$texture_packs_folder/Citra" "$XDG_DATA_HOME/citra-emu/load/textures"
          set_setting_value "$citraconf" "nand_directory" "$saves_folder/n3ds/citra/nand/" "citra" "Data%20Storage"
          set_setting_value "$citraconf" "sdmc_directory" "$saves_folder/n3ds/citra/sdmc/" "citra" "Data%20Storage"
          set_setting_value "$citraconf" "Paths\gamedirs\3\path" "$roms_folder/n3ds" "citra" "UI"
          set_setting_value "$citraconf" "Paths\screenshotPath" "$screenshots_folder" "citra" "UI"
        fi
      fi
    fi

    if [[ "$component" =~ ^(cemu|all)$ ]]; then
    component_found="true"
      if [[ "$action" == "reset" ]]; then # Run reset-only commands
        log i "----------------------"
        log i "Prepearing CEMU"
        log i "----------------------"
        if [[ $multi_user_mode == "true" ]]; then # Multi-user actions
          create_dir -d "$multi_user_data_folder/$SteamAppUser/config/Cemu"
          cp -fr "$config/cemu/"* "$multi_user_data_folder/$SteamAppUser/config/Cemu/"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/Cemu/settings.ini" "mlc_path" "$bios_folder/cemu" "cemu"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/Cemu/settings.ini" "Entry" "$roms_folder/wiiu" "cemu" "GamePaths"
          dir_prep "$multi_user_data_folder/$SteamAppUser/config/Cemu" "$XDG_CONFIG_HOME/Cemu"
        else
          create_dir -d "$XDG_CONFIG_HOME/Cemu/"
          cp -fr "$config/cemu/"* "$XDG_CONFIG_HOME/Cemu/"
          set_setting_value "$cemuconf" "mlc_path" "$bios_folder/cemu" "cemu"
          set_setting_value "$cemuconf" "Entry" "$roms_folder/wiiu" "cemu" "GamePaths"
          if [[ -e "$bios_folder/cemu/keys.txt" ]]; then
            rm -rf "$XDG_DATA_HOME/Cemu/keys.txt" && ln -s "$bios_folder/cemu/keys.txt" "$XDG_DATA_HOME/Cemu/keys.txt" && log d "Linked $bios_folder/cemu/keys.txt to $XDG_DATA_HOME/Cemu/keys.txt"
          fi
        fi
        # Shared actions
        dir_prep "$saves_folder/wiiu/cemu" "$bios_folder/cemu/usr/save"
      fi
      if [[ "$action" == "postmove" ]]; then # Run commands that apply to both resets and moves
        set_setting_value "$cemuconf" "mlc_path" "$bios_folder/cemu" "cemu"
        set_setting_value "$cemuconf" "Entry" "$roms_folder/wiiu" "cemu" "GamePaths"
        dir_prep "$saves_folder/wiiu/cemu" "$bios_folder/cemu/usr/save"
      fi
    fi

    if [[ "$component" =~ ^(dolphin|dolphin-emu|all)$ ]]; then
    component_found="true"
      if [[ "$action" == "reset" ]]; then # Run reset-only commands
        log i "----------------------"
        log i "Prepearing DOLPHIN"
        log i "----------------------"
        if [[ $multi_user_mode == "true" ]]; then # Multi-user actions
          create_dir -d "$multi_user_data_folder/$SteamAppUser/config/dolphin-emu"
          cp -fvr "$config/dolphin/"* "$multi_user_data_folder/$SteamAppUser/config/dolphin-emu/"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/dolphin-emu/Dolphin.ini" "BIOS" "$bios_folder" "dolphin" "GBA"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/dolphin-emu/Dolphin.ini" "SavesPath" "$saves_folder/gba" "dolphin" "GBA"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/dolphin-emu/Dolphin.ini" "ISOPath0" "$roms_folder/wii" "dolphin" "General"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/dolphin-emu/Dolphin.ini" "ISOPath1" "$roms_folder/gc" "dolphin" "General"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/dolphin-emu/Dolphin.ini" "WiiSDCardPath" "$saves_folder/wii/dolphin/sd.raw" "dolphin" "General"
          dir_prep "$multi_user_data_folder/$SteamAppUser/config/dolphin-emu" "$XDG_CONFIG_HOME/dolphin-emu"
        else # Single-user actions
          create_dir -d "$XDG_CONFIG_HOME/dolphin-emu/"
          cp -fvr "$config/dolphin/"* "$XDG_CONFIG_HOME/dolphin-emu/"
          set_setting_value "$dolphinconf" "BIOS" "$bios_folder" "dolphin" "GBA"
          set_setting_value "$dolphinconf" "SavesPath" "$saves_folder/gba" "dolphin" "GBA"
          set_setting_value "$dolphinconf" "ISOPath0" "$roms_folder/wii" "dolphin" "General"
          set_setting_value "$dolphinconf" "ISOPath1" "$roms_folder/gc" "dolphin" "General"
          set_setting_value "$dolphinconf" "WiiSDCardPath" "$saves_folder/wii/dolphin/sd.raw" "dolphin" "General"
        fi
        # Shared actions
        dir_prep "$saves_folder/gc/dolphin/EU" "$XDG_DATA_HOME/dolphin-emu/GC/EUR" # TODO: Multi-user one-off
        dir_prep "$saves_folder/gc/dolphin/US" "$XDG_DATA_HOME/dolphin-emu/GC/USA" # TODO: Multi-user one-off
        dir_prep "$saves_folder/gc/dolphin/JP" "$XDG_DATA_HOME/dolphin-emu/GC/JAP" # TODO: Multi-user one-off
        dir_prep "$screenshots_folder" "$XDG_DATA_HOME/dolphin-emu/ScreenShots"
        dir_prep "$states_folder/dolphin" "$XDG_DATA_HOME/dolphin-emu/StateSaves"
        dir_prep "$saves_folder/wii/dolphin" "$XDG_DATA_HOME/dolphin-emu/Wii"
        dir_prep "$mods_folder/Dolphin" "$XDG_DATA_HOME/dolphin-emu/Load/GraphicMods"
        dir_prep "$texture_packs_folder/Dolphin" "$XDG_DATA_HOME/dolphin-emu/Load/Textures"

        # Reset default preset settings
        set_setting_value "$rd_conf" "dolphin" "$(get_setting_value "$rd_defaults" "dolphin" "retrodeck" "ask_to_exit")" "retrodeck" "ask_to_exit"
      fi
      if [[ "$action" == "postmove" ]]; then # Run only post-move commands
        dir_prep "$saves_folder/gc/dolphin/EU" "$XDG_DATA_HOME/dolphin-emu/GC/EUR"
        dir_prep "$saves_folder/gc/dolphin/US" "$XDG_DATA_HOME/dolphin-emu/GC/USA"
        dir_prep "$saves_folder/gc/dolphin/JP" "$XDG_DATA_HOME/dolphin-emu/GC/JAP"
        dir_prep "$screenshots_folder" "$XDG_DATA_HOME/dolphin-emu/ScreenShots"
        dir_prep "$states_folder/dolphin" "$XDG_DATA_HOME/dolphin-emu/StateSaves"
        dir_prep "$saves_folder/wii/dolphin" "$XDG_DATA_HOME/dolphin-emu/Wii"
        dir_prep "$mods_folder/Dolphin" "$XDG_DATA_HOME/dolphin-emu/Load/GraphicMods"
        dir_prep "$texture_packs_folder/Dolphin" "$XDG_DATA_HOME/dolphin-emu/Load/Textures"
        set_setting_value "$dolphinconf" "BIOS" "$bios_folder" "dolphin" "GBA"
        set_setting_value "$dolphinconf" "SavesPath" "$saves_folder/gba" "dolphin" "GBA"
        set_setting_value "$dolphinconf" "ISOPath0" "$roms_folder/wii" "dolphin" "General"
        set_setting_value "$dolphinconf" "ISOPath1" "$roms_folder/gc" "dolphin" "General"
        set_setting_value "$dolphinconf" "WiiSDCardPath" "$saves_folder/wii/dolphin/sd.raw" "dolphin" "General"
      fi
    fi

    if [[ "$component" =~ ^(duckstation|all)$ ]]; then
    component_found="true"
      if [[ "$action" == "reset" ]]; then # Run reset-only commands
        log i "------------------------"
        log i "Prepearing DUCKSTATION"
        log i "------------------------"
        if [[ $multi_user_mode == "true" ]]; then # Multi-user actions
          create_dir -d "$multi_user_data_folder/$SteamAppUser/data/duckstation/"
          cp -fv "$config/duckstation/"* "$multi_user_data_folder/$SteamAppUser/data/duckstation"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/data/duckstation/settings.ini" "SearchDirectory" "$bios_folder" "duckstation" "BIOS"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/data/duckstation/settings.ini" "Card1Path" "$saves_folder/psx/duckstation/memcards/shared_card_1.mcd" "duckstation" "MemoryCards"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/data/duckstation/settings.ini" "Card2Path" "$saves_folder/psx/duckstation/memcards/shared_card_2.mcd" "duckstation" "MemoryCards"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/data/duckstation/settings.ini" "Directory" "$saves_folder/psx/duckstation/memcards" "duckstation" "MemoryCards"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/data/duckstation/settings.ini" "RecursivePaths" "$roms_folder/psx" "duckstation" "GameList"
          dir_prep "$multi_user_data_folder/$SteamAppUser/config/duckstation" "$XDG_CONFIG_HOME/duckstation"
        else # Single-user actions
          create_dir -d "$XDG_CONFIG_HOME/duckstation/"
          create_dir "$saves_folder/psx/duckstation/memcards"
          cp -fv "$config/duckstation/"* "$XDG_CONFIG_HOME/duckstation"
          set_setting_value "$duckstationconf" "SearchDirectory" "$bios_folder" "duckstation" "BIOS"
          set_setting_value "$duckstationconf" "Card1Path" "$saves_folder/psx/duckstation/memcards/shared_card_1.mcd" "duckstation" "MemoryCards"
          set_setting_value "$duckstationconf" "Card2Path" "$saves_folder/psx/duckstation/memcards/shared_card_2.mcd" "duckstation" "MemoryCards"
          set_setting_value "$duckstationconf" "Directory" "$saves_folder/psx/duckstation/memcards" "duckstation" "MemoryCards"
          set_setting_value "$duckstationconf" "RecursivePaths" "$roms_folder/psx" "duckstation" "GameList"
        fi
        # Shared actions
        dir_prep "$states_folder/psx/duckstation" "$XDG_CONFIG_HOME/duckstation/savestates" # This is hard-coded in Duckstation, always needed
        dir_prep "$texture_packs_folder/Duckstation" "$XDG_CONFIG_HOME/duckstation/textures"

        # Reset default preset settings
        set_setting_value "$rd_conf" "duckstation" "$(get_setting_value "$rd_defaults" "duckstation" "retrodeck" "cheevos")" "retrodeck" "cheevos"
        set_setting_value "$rd_conf" "duckstation" "$(get_setting_value "$rd_defaults" "duckstation" "retrodeck" "cheevos_hardcore")" "retrodeck" "cheevos_hardcore"
        set_setting_value "$rd_conf" "duckstation" "$(get_setting_value "$rd_defaults" "duckstation" "retrodeck" "savestate_auto_save")" "retrodeck" "savestate_auto_save"
        set_setting_value "$rd_conf" "duckstation" "$(get_setting_value "$rd_defaults" "duckstation" "retrodeck" "ask_to_exit")" "retrodeck" "ask_to_exit"
      fi
      if [[ "$action" == "postmove" ]]; then # Run only post-move commands
        set_setting_value "$duckstationconf" "SearchDirectory" "$bios_folder" "duckstation" "BIOS"
        set_setting_value "$duckstationconf" "Card1Path" "$saves_folder/psx/duckstation/memcards/shared_card_1.mcd" "duckstation" "MemoryCards"
        set_setting_value "$duckstationconf" "Card2Path" "$saves_folder/psx/duckstation/memcards/shared_card_2.mcd" "duckstation" "MemoryCards"
        set_setting_value "$duckstationconf" "Directory" "$saves_folder/psx/duckstation/memcards" "duckstation" "MemoryCards"
        set_setting_value "$duckstationconf" "RecursivePaths" "$roms_folder/psx" "duckstation" "GameList"
        dir_prep "$states_folder/psx/duckstation" "$XDG_CONFIG_HOME/duckstation/savestates" # This is hard-coded in Duckstation, always needed
        dir_prep "$texture_packs_folder/Duckstation" "$XDG_CONFIG_HOME/duckstation/textures"
      fi
    fi

    if [[ "$component" =~ ^(melonds|all)$ ]]; then
    component_found="true"
      if [[ "$action" == "reset" ]]; then # Run reset-only commands
        log i "----------------------"
        log i "Prepearing MELONDS"
        log i "----------------------"
        if [[ $multi_user_mode == "true" ]]; then # Multi-user actions
          create_dir -d "$multi_user_data_folder/$SteamAppUser/config/melonDS/"
          cp -fvr "$config/melonds/melonDS.ini" "$multi_user_data_folder/$SteamAppUser/config/melonDS/"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/melonDS/melonDS.ini" "BIOS9Path" "$bios_folder/bios9.bin" "melonds"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/melonDS/melonDS.ini" "BIOS7Path" "$bios_folder/bios7.bin" "melonds"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/melonDS/melonDS.ini" "FirmwarePath" "$bios_folder/firmware.bin" "melonds"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/melonDS/melonDS.ini" "SaveFilePath" "$saves_folder/nds/melonds" "melonds"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/melonDS/melonDS.ini" "SavestatePath" "$states_folder/nds/melonds" "melonds"
          dir_prep "$multi_user_data_folder/$SteamAppUser/config/melonDS" "$XDG_CONFIG_HOME/melonDS"
        else # Single-user actions
          create_dir -d "$XDG_CONFIG_HOME/melonDS/"
          cp -fvr "$config/melonds/melonDS.ini" "$XDG_CONFIG_HOME/melonDS/"
          set_setting_value "$melondsconf" "BIOS9Path" "$bios_folder/bios9.bin" "melonds"
          set_setting_value "$melondsconf" "BIOS7Path" "$bios_folder/bios7.bin" "melonds"
          set_setting_value "$melondsconf" "FirmwarePath" "$bios_folder/firmware.bin" "melonds"
          set_setting_value "$melondsconf" "SaveFilePath" "$saves_folder/nds/melonds" "melonds"
          set_setting_value "$melondsconf" "SavestatePath" "$states_folder/nds/melonds" "melonds"
        fi
        # Shared actions
        create_dir "$saves_folder/nds/melonds"
        create_dir "$states_folder/nds/melonds"
        dir_prep "$bios_folder" "$XDG_CONFIG_HOME/melonDS/bios"
      fi
      if [[ "$action" == "postmove" ]]; then # Run only post-move commands
        dir_prep "$bios_folder" "$XDG_CONFIG_HOME/melonDS/bios"
        set_setting_value "$melondsconf" "BIOS9Path" "$bios_folder/bios9.bin" "melonds"
        set_setting_value "$melondsconf" "BIOS7Path" "$bios_folder/bios7.bin" "melonds"
        set_setting_value "$melondsconf" "FirmwarePath" "$bios_folder/firmware.bin" "melonds"
        set_setting_value "$melondsconf" "SaveFilePath" "$saves_folder/nds/melonds" "melonds"
        set_setting_value "$melondsconf" "SavestatePath" "$states_folder/nds/melonds" "melonds"
      fi
    fi

    if [[ "$component" =~ ^(pcsx2|all)$ ]]; then
    component_found="true"
      if [[ "$action" == "reset" ]]; then # Run reset-only commands
        log i "----------------------"
        log i "Prepearing PCSX2"
        log i "----------------------"
        if [[ $multi_user_mode == "true" ]]; then # Multi-user actions
          create_dir -d "$multi_user_data_folder/$SteamAppUser/config/PCSX2/inis"
          cp -fvr "$config/PCSX2/"* "$multi_user_data_folder/$SteamAppUser/config/PCSX2/inis/"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/PCSX2/inis/PCSX2.ini" "Bios" "$bios_folder" "pcsx2" "Folders"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/PCSX2/inis/PCSX2.ini" "Snapshots" "$screenshots_folder" "pcsx2" "Folders"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/PCSX2/inis/PCSX2.ini" "SaveStates" "$states_folder/ps2/pcsx2" "pcsx2" "Folders"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/PCSX2/inis/PCSX2.ini" "MemoryCards" "$saves_folder/ps2/pcsx2/memcards" "pcsx2" "Folders"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/PCSX2/inis/PCSX2.ini" "RecursivePaths" "$roms_folder/ps2" "pcsx2" "GameList"
          dir_prep "$multi_user_data_folder/$SteamAppUser/config/PCSX2" "$XDG_CONFIG_HOME/PCSX2"
        else # Single-user actions
          create_dir -d "$XDG_CONFIG_HOME/PCSX2/inis"
          cp -fvr "$config/PCSX2/"* "$XDG_CONFIG_HOME/PCSX2/inis/"
          set_setting_value "$pcsx2conf" "Bios" "$bios_folder" "pcsx2" "Folders"
          set_setting_value "$pcsx2conf" "Snapshots" "$screenshots_folder" "pcsx2" "Folders"
          set_setting_value "$pcsx2conf" "SaveStates" "$states_folder/ps2/pcsx2" "pcsx2" "Folders"
          set_setting_value "$pcsx2conf" "MemoryCards" "$saves_folder/ps2/pcsx2/memcards" "pcsx2" "Folders"
          set_setting_value "$pcsx2conf" "RecursivePaths" "$roms_folder/ps2" "pcsx2" "GameList"
          set_setting_value "$pcsx2conf" "Cheats" "$cheats_folder/pcsx2" "Folders"
          if [[ -d "$cheats_folder/pcsx2" && "$(ls -A "$cheats_folder/pcsx2")" ]]; then
            backup_file="$backups_folder/cheats/pcsx2-$(date +%y%m%d).tar.gz"
            create_dir "$(dirname "$backup_file")"
            tar -czf "$backup_file" -C "$cheats_folder" pcsx2
            log i "PCSX2 cheats backed up to $backup_file"
          fi
          create_dir -d "$cheats_folder/pcsx2"
          tar --strip-components=1 -xzf "/app/retrodeck/cheats/pcsx2.tar.gz" -C "$cheats_folder/pcsx2" --overwrite
        fi
        # Shared actions
        create_dir "$saves_folder/ps2/pcsx2/memcards"
        create_dir "$states_folder/ps2/pcsx2"
        dir_prep "$texture_packs_folder/PCSX2" "$XDG_CONFIG_HOME/PCSX2/textures"

        # Reset default preset settings
        set_setting_value "$rd_conf" "pcsx2" "$(get_setting_value "$rd_defaults" "pcsx2" "retrodeck" "cheevos")" "retrodeck" "cheevos"
        set_setting_value "$rd_conf" "pcsx2" "$(get_setting_value "$rd_defaults" "pcsx2" "retrodeck" "cheevos_hardcore")" "retrodeck" "cheevos_hardcore"
        set_setting_value "$rd_conf" "pcsx2" "$(get_setting_value "$rd_defaults" "pcsx2" "retrodeck" "savestate_auto_save")" "retrodeck" "savestate_auto_save"
        set_setting_value "$rd_conf" "pcsx2" "$(get_setting_value "$rd_defaults" "pcsx2" "retrodeck" "ask_to_exit")" "retrodeck" "ask_to_exit"
      fi
      if [[ "$action" == "postmove" ]]; then # Run only post-move commands
        set_setting_value "$pcsx2conf" "Bios" "$bios_folder" "pcsx2" "Folders"
        set_setting_value "$pcsx2conf" "Snapshots" "$screenshots_folder" "pcsx2" "Folders"
        set_setting_value "$pcsx2conf" "SaveStates" "$states_folder/ps2/pcsx2" "pcsx2" "Folders"
        set_setting_value "$pcsx2conf" "MemoryCards" "$saves_folder/ps2/pcsx2/memcards" "pcsx2" "Folders"
        set_setting_value "$pcsx2conf" "RecursivePaths" "$roms_folder/ps2" "pcsx2" "GameList"
        set_setting_value "$pcsx2conf" "Cheats" "$cheats_folder/pcsx2" "Folders"
        dir_prep "$texture_packs_folder/PCSX2" "$XDG_CONFIG_HOME/PCSX2/textures"
      fi
    fi

    if [[ "$component" =~ ^(pico8|pico-8|all)$ ]]; then
    component_found="true"
      if [[ ("$action" == "reset") || ("$action" == "postmove") ]]; then
        if [[ -d "$roms_folder/pico8" ]]; then
          dir_prep "$roms_folder/pico8" "$bios_folder/pico-8/carts" # Symlink default game location to RD roms for cleanliness (this location is overridden anyway by the --root_path launch argument anyway)
        fi
        dir_prep "$bios_folder/pico-8" "$HOME/.lexaloffle/pico-8" # Store binary and config files together. The .lexaloffle directory is a hard-coded location for the PICO-8 config file, cannot be changed
        dir_prep "$saves_folder/pico-8" "$bios_folder/pico-8/cdata"  # PICO-8 saves folder
        cp -fv "$config/pico-8/config.txt" "$bios_folder/pico-8/config.txt"
        cp -fv "$config/pico-8/sdl_controllers.txt" "$bios_folder/pico-8/sdl_controllers.txt"
      fi
    fi

    if [[ "$component" =~ ^(ppsspp|all)$ ]]; then
    component_found="true"
      if [[ "$action" == "reset" ]]; then # Run reset-only commands
        log i "------------------------"
        log i "Prepearing PPSSPPSDL"
        log i "------------------------"
        if [[ $multi_user_mode == "true" ]]; then # Multi-user actions
          create_dir -d "$multi_user_data_folder/$SteamAppUser/config/ppsspp/PSP/SYSTEM/"
          cp -fv "$config/ppssppsdl/"* "$multi_user_data_folder/$SteamAppUser/config/ppsspp/PSP/SYSTEM/"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/ppsspp/PSP/SYSTEM/ppsspp.ini" "CurrentDirectory" "$roms_folder/psp" "ppsspp" "General"
          dir_prep "$multi_user_data_folder/$SteamAppUser/config/ppsspp" "$XDG_CONFIG_HOME/ppsspp"
        else # Single-user actions
          create_dir -d "$XDG_CONFIG_HOME/ppsspp/PSP/SYSTEM/"
          cp -fv "$config/ppssppsdl/"* "$XDG_CONFIG_HOME/ppsspp/PSP/SYSTEM/"
          set_setting_value "$ppssppconf" "CurrentDirectory" "$roms_folder/psp" "ppsspp" "General"
        fi
        # Shared actions
        dir_prep "$saves_folder/PSP/PPSSPP-SA" "$XDG_CONFIG_HOME/ppsspp/PSP/SAVEDATA"
        dir_prep "$states_folder/PSP/PPSSPP-SA" "$XDG_CONFIG_HOME/ppsspp/PSP/PPSSPP_STATE"
        dir_prep "$texture_packs_folder/PPSSPP" "$XDG_CONFIG_HOME/ppsspp/PSP/TEXTURES"
        create_dir -d "$cheats_folder/PPSSPP"
        dir_prep "$cheats_folder/PPSSPP" "$XDG_CONFIG_HOME/ppsspp/PSP/Cheats"
        if [[ -d "$cheats_folder/PPSSPP" && "$(ls -A "$cheats_folder"/PPSSPP)" ]]; then
          backup_file="$backups_folder/cheats/PPSSPP-$(date +%y%m%d).tar.gz"
          create_dir "$(dirname "$backup_file")"
          tar -czf "$backup_file" -C "$cheats_folder" PPSSPP
          log i "PPSSPP cheats backed up to $backup_file"
        fi
        tar -xzf "/app/retrodeck/cheats/ppsspp.tar.gz" -C "$cheats_folder/PPSSPP" --overwrite
      fi
      if [[ "$action" == "postmove" ]]; then # Run only post-move commands
        set_setting_value "$ppssppconf" "CurrentDirectory" "$roms_folder/psp" "ppsspp" "General"
        dir_prep "$saves_folder/PSP/PPSSPP-SA" "$XDG_CONFIG_HOME/ppsspp/PSP/SAVEDATA"
        dir_prep "$states_folder/PSP/PPSSPP-SA" "$XDG_CONFIG_HOME/ppsspp/PSP/PPSSPP_STATE"
        dir_prep "$texture_packs_folder/PPSSPP" "$XDG_CONFIG_HOME/ppsspp/PSP/TEXTURES"
        dir_prep "$cheats_folder/PPSSPP" "$XDG_CONFIG_HOME/ppsspp/PSP/Cheats"
      fi
    fi

    if [[ "$component" =~ ^(primehack|all)$ ]]; then
    component_found="true"
      if [[ "$action" == "reset" ]]; then # Run reset-only commands
        log i "----------------------"
        log i "Prepearing Primehack"
        log i "----------------------"
        if [[ $multi_user_mode == "true" ]]; then # Multi-user actions
          create_dir -d "$multi_user_data_folder/$SteamAppUser/config/primehack"
          cp -fvr "$config/primehack/config/"* "$multi_user_data_folder/$SteamAppUser/config/primehack/"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/primehack/Dolphin.ini" "ISOPath0" "$roms_folder/wii" "primehack" "General"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/primehack/Dolphin.ini" "ISOPath1" "$roms_folder/gc" "primehack" "General"
          dir_prep "$multi_user_data_folder/$SteamAppUser/config/primehack" "$XDG_CONFIG_HOME/primehack"
        else # Single-user actions
          create_dir -d "$XDG_CONFIG_HOME/primehack/"
          cp -fvr "$config/primehack/config/"* "$XDG_CONFIG_HOME/primehack/"
          set_setting_value "$primehackconf" "ISOPath0" "$roms_folder/wii" "primehack" "General"
          set_setting_value "$primehackconf" "ISOPath1" "$roms_folder/gc" "primehack" "General"
        fi
        # Shared actions
        dir_prep "$saves_folder/gc/primehack/EU" "$XDG_DATA_HOME/primehack/GC/EUR"
        dir_prep "$saves_folder/gc/primehack/US" "$XDG_DATA_HOME/primehack/GC/USA"
        dir_prep "$saves_folder/gc/primehack/JP" "$XDG_DATA_HOME/primehack/GC/JAP"
        dir_prep "$screenshots_folder" "$XDG_DATA_HOME/primehack/ScreenShots"
        dir_prep "$states_folder/primehack" "$XDG_DATA_HOME/primehack/StateSaves"
        create_dir "$XDG_DATA_HOME/primehack/Wii/"
        dir_prep "$saves_folder/wii/primehack" "$XDG_DATA_HOME/primehack/Wii"
        dir_prep "$mods_folder/Primehack" "$XDG_DATA_HOME/primehack/Load/GraphicMods"
        dir_prep "$texture_packs_folder/Primehack" "$XDG_DATA_HOME/primehack/Load/Textures"
        if [[ $multi_user_mode == "true" ]]; then # Multi-user actions
          cp -fvr "$config/primehack/data/"* "$multi_user_data_folder/$SteamAppUser/data/primehack/" # this must be done after the dirs are prepared as it copying some "mods"
        fi

        # Reset default preset settings
        set_setting_value "$rd_conf" "primehack" "$(get_setting_value "$rd_defaults" "primehack" "retrodeck" "ask_to_exit")" "retrodeck" "ask_to_exit"
      fi
      if [[ "$action" == "postmove" ]]; then # Run only post-move commands
        dir_prep "$saves_folder/gc/primehack/EU" "$XDG_DATA_HOME/primehack/GC/EUR"
        dir_prep "$saves_folder/gc/primehack/US" "$XDG_DATA_HOME/primehack/GC/USA"
        dir_prep "$saves_folder/gc/primehack/JP" "$XDG_DATA_HOME/primehack/GC/JAP"
        dir_prep "$screenshots_folder" "$XDG_DATA_HOME/primehack/ScreenShots"
        dir_prep "$states_folder/primehack" "$XDG_DATA_HOME/primehack/StateSaves"
        dir_prep "$saves_folder/wii/primehack" "$XDG_DATA_HOME/primehack/Wii/"
        dir_prep "$mods_folder/Primehack" "$XDG_DATA_HOME/primehack/Load/GraphicMods"
        dir_prep "$texture_packs_folder/Primehack" "$XDG_DATA_HOME/primehack/Load/Textures"
        set_setting_value "$primehackconf" "ISOPath0" "$roms_folder/gc" "primehack" "General"
      fi
    fi

    if [[ "$component" =~ ^(rpcs3|all)$ ]]; then
    component_found="true"
      if [[ "$action" == "reset" ]]; then # Run reset-only commands
        log i "------------------------"
        log i "Prepearing RPCS3"
        log i "------------------------"
        if [[ $multi_user_mode == "true" ]]; then # Multi-user actions
          create_dir -d "$multi_user_data_folder/$SteamAppUser/config/rpcs3/"
          cp -fr "$config/rpcs3/"* "$multi_user_data_folder/$SteamAppUser/config/rpcs3/"
          # This is an unfortunate one-off because set_setting_value does not currently support settings with $ in the name.
          sed -i 's^\^$(EmulatorDir): .*^$(EmulatorDir): '"$bios_folder/rpcs3/"'^' "$multi_user_data_folder/$SteamAppUser/config/rpcs3/vfs.yml"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/rpcs3/vfs.yml" "/games/" "$roms_folder/ps3/" "rpcs3"
          dir_prep "$multi_user_data_folder/$SteamAppUser/config/rpcs3" "$XDG_CONFIG_HOME/rpcs3"
        else # Single-user actions
          create_dir -d "$XDG_CONFIG_HOME/rpcs3/"
          cp -fr "$config/rpcs3/"* "$XDG_CONFIG_HOME/rpcs3/"
          # This is an unfortunate one-off because set_setting_value does not currently support settings with $ in the name.
          sed -i 's^\^$(EmulatorDir): .*^$(EmulatorDir): '"$bios_folder/rpcs3/"'^' "$rpcs3vfsconf"
          set_setting_value "$rpcs3vfsconf" "/games/" "$roms_folder/ps3/" "rpcs3"
          dir_prep "$saves_folder/ps3/rpcs3" "$bios_folder/rpcs3/dev_hdd0/home/00000001/savedata"
          dir_prep "$states_folder/ps3/rpcs3" "$XDG_CONFIG_HOME/rpcs3/savestates"
        fi
        # Shared actions
        create_dir "$bios_folder/rpcs3/dev_hdd0"
        create_dir "$bios_folder/rpcs3/dev_hdd1"
        create_dir "$bios_folder/rpcs3/dev_flash"
        create_dir "$bios_folder/rpcs3/dev_flash2"
        create_dir "$bios_folder/rpcs3/dev_flash3"
        create_dir "$bios_folder/rpcs3/dev_bdvd"
        create_dir "$bios_folder/rpcs3/dev_usb000"
      fi
      if [[ "$action" == "postmove" ]]; then # Run only post-move commands
        # This is an unfortunate one-off because set_setting_value does not currently support settings with $ in the name.
        sed -i 's^\^$(EmulatorDir): .*^$(EmulatorDir): '"$bios_folder/rpcs3"'^' "$rpcs3vfsconf"
        set_setting_value "$rpcs3vfsconf" "/games/" "$roms_folder/ps3" "rpcs3"
      fi
    fi

    if [[ "$component" =~ ^(ryujinx|all)$ ]]; then
    component_found="true"
      # NOTE: for techincal reasons the system folder of Ryujinx IS NOT a sumlink of the bios/switch/keys as not only the keys are located there
      # When RetroDECK starts there is a "manage_ryujinx_keys" function that symlinks the keys only in Rryujinx/system.
      if [[ "$action" == "reset" ]]; then # Run reset-only commands
        log i "------------------------"
        log i "Prepearing RYUJINX"
        log i "------------------------"
        if [[ $multi_user_mode == "true" ]]; then
          rm -rf "$multi_user_data_folder/$SteamAppUser/config/Ryujinx"
          #create_dir "$multi_user_data_folder/$SteamAppUser/config/Ryujinx/system"
          cp -fv "$config/ryujinx/"* "$multi_user_data_folder/$SteamAppUser/config/Ryujinx"
          sed -i 's#RETRODECKHOMEDIR#'"$rdhome"'#g' "$multi_user_data_folder/$SteamAppUser/config/Ryujinx/Config.json"
          dir_prep "$multi_user_data_folder/$SteamAppUser/config/Ryujinx" "$XDG_CONFIG_HOME/Ryujinx"
        else
          # removing config directory to wipe legacy files
          log d "Removing \"$XDG_CONFIG_HOME/Ryujinx\""
          rm -rf "$XDG_CONFIG_HOME/Ryujinx"
          create_dir "$XDG_CONFIG_HOME/Ryujinx/system"
          cp -fv "$config/ryujinx/Config.json" "$ryujinxconf"
          cp -fvr "$config/ryujinx/profiles" "$XDG_CONFIG_HOME/Ryujinx/"
          log d "Replacing placeholders in \"$ryujinxconf\""
          sed -i 's#RETRODECKHOMEDIR#'"$rdhome"'#g' "$ryujinxconf"
          create_dir "$logs_folder/ryujinx"
          create_dir "$mods_folder/ryujinx"
          create_dir "$screenshots_folder/ryujinx"
        fi
      fi
      # if [[ "$action" == "reset" ]] || [[ "$action" == "postmove" ]]; then # Run commands that apply to both resets and moves
      #   dir_prep "$bios_folder/switch/keys" "$XDG_CONFIG_HOME/Ryujinx/system"
      # fi
      if [[ "$action" == "postmove" ]]; then # Run only post-move commands
        log d "Replacing placeholders in \"$ryujinxconf\""
        sed -i 's#RETRODECKHOMEDIR#'"$rdhome"'#g' "$ryujinxconf" # This is an unfortunate one-off because set_setting_value does not currently support JSON
      fi
    fi

    if [[ $(get_setting_value "$rd_conf" "kiroi_ponzu" "retrodeck" "options") == "true" ]]; then
      if [[ "$component" =~ ^(yuzu|all)$ ]]; then
      component_found="true"
        if [[ "$action" == "reset" ]]; then # Run reset-only commands
          log i "----------------------"
          log i "Prepearing YUZU"
          log i "----------------------"
          if [[ $multi_user_mode == "true" ]]; then # Multi-user actions
            create_dir -d "$multi_user_data_folder/$SteamAppUser/config/yuzu"
            cp -fvr "$config/yuzu/"* "$multi_user_data_folder/$SteamAppUser/config/yuzu/"
            set_setting_value "$multi_user_data_folder/$SteamAppUser/config/yuzu/qt-config.ini" "nand_directory" "$saves_folder/switch/yuzu/nand" "yuzu" "Data%20Storage"
            set_setting_value "$multi_user_data_folder/$SteamAppUser/config/yuzu/qt-config.ini" "sdmc_directory" "$saves_folder/switch/yuzu/sdmc" "yuzu" "Data%20Storage"
            set_setting_value "$multi_user_data_folder/$SteamAppUser/config/yuzu/qt-config.ini" "Paths\gamedirs\4\path" "$roms_folder/switch" "yuzu" "UI"
            set_setting_value "$multi_user_data_folder/$SteamAppUser/config/yuzu/qt-config.ini" "Screenshots\screenshot_path" "$screenshots_folder" "yuzu" "UI"
            dir_prep "$multi_user_data_folder/$SteamAppUser/config/yuzu" "$XDG_CONFIG_HOME/yuzu"
          else # Single-user actions
            create_dir -d "$XDG_CONFIG_HOME/yuzu/"
            cp -fvr "$config/yuzu/"* "$XDG_CONFIG_HOME/yuzu/"
            set_setting_value "$yuzuconf" "nand_directory" "$saves_folder/switch/yuzu/nand" "yuzu" "Data%20Storage"
            set_setting_value "$yuzuconf" "sdmc_directory" "$saves_folder/switch/yuzu/sdmc" "yuzu" "Data%20Storage"
            set_setting_value "$yuzuconf" "Paths\gamedirs\4\path" "$roms_folder/switch" "yuzu" "UI"
            set_setting_value "$yuzuconf" "Screenshots\screenshot_path" "$screenshots_folder" "yuzu" "UI"
          fi
          # Shared actions
          dir_prep "$saves_folder/switch/yuzu/nand" "$XDG_DATA_HOME/yuzu/nand"
          dir_prep "$saves_folder/switch/yuzu/sdmc" "$XDG_DATA_HOME/yuzu/sdmc"
          dir_prep "$bios_folder/switch/keys" "$XDG_DATA_HOME/yuzu/keys"
          dir_prep "$bios_folder/switch/firmware" "$XDG_DATA_HOME/yuzu/nand/system/Contents/registered"
          dir_prep "$logs_folder/yuzu" "$XDG_DATA_HOME/yuzu/log"
          dir_prep "$screenshots_folder" "$XDG_DATA_HOME/yuzu/screenshots"
          dir_prep "$mods_folder/Yuzu" "$XDG_DATA_HOME/yuzu/load"
          # removing dead symlinks as they were present in a past version
          if [ -d "$bios_folder/switch" ]; then
            find "$bios_folder/switch" -xtype l -exec rm {} \;
          fi

          # Reset default preset settings
          set_setting_value "$rd_conf" "yuzu" "$(get_setting_value "$rd_defaults" "yuzu" "retrodeck" "abxy_button_swap")" "retrodeck" "abxy_button_swap"
          set_setting_value "$rd_conf" "yuzu" "$(get_setting_value "$rd_defaults" "yuzu" "retrodeck" "ask_to_exit")" "retrodeck" "ask_to_exit"
        fi
        if [[ "$action" == "postmove" ]]; then # Run only post-move commands
          dir_prep "$bios_folder/switch/keys" "$XDG_DATA_HOME/yuzu/keys"
          dir_prep "$bios_folder/switch/firmware" "$XDG_DATA_HOME/yuzu/nand/system/Contents/registered"
          dir_prep "$saves_folder/switch/yuzu/nand" "$XDG_DATA_HOME/yuzu/nand"
          dir_prep "$saves_folder/switch/yuzu/sdmc" "$XDG_DATA_HOME/yuzu/sdmc"
          dir_prep "$logs_folder/yuzu" "$XDG_DATA_HOME/yuzu/log"
          dir_prep "$screenshots_folder" "$XDG_DATA_HOME/yuzu/screenshots"
          dir_prep "$mods_folder/Yuzu" "$XDG_DATA_HOME/yuzu/load"
          set_setting_value "$yuzuconf" "nand_directory" "$saves_folder/switch/yuzu/nand" "yuzu" "Data%20Storage"
          set_setting_value "$yuzuconf" "sdmc_directory" "$saves_folder/switch/yuzu/sdmc" "yuzu" "Data%20Storage"
          set_setting_value "$yuzuconf" "Paths\gamedirs\4\path" "$roms_folder/switch" "yuzu" "UI"
          set_setting_value "$yuzuconf" "Screenshots\screenshot_path" "$screenshots_folder" "yuzu" "UI"
        fi
      fi
    fi

    if [[ "$component" =~ ^(xemu|all)$ ]]; then
    component_found="true"
      if [[ "$action" == "reset" ]]; then # Run reset-only commands
        log i "------------------------"
        log i "Prepearing XEMU"
        log i "------------------------"
        if [[ $multi_user_mode == "true" ]]; then # Multi-user actions
          rm -rf "$XDG_CONFIG_HOME/xemu"
          rm -rf "$XDG_DATA_HOME/xemu"
          create_dir -d "$multi_user_data_folder/$SteamAppUser/config/xemu/"
          cp -fv "$config/xemu/xemu.toml" "$multi_user_data_folder/$SteamAppUser/config/xemu/xemu.toml"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/xemu/xemu.toml" "screenshot_dir" "'$screenshots_folder'" "xemu" "General"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/xemu/xemu.toml" "bootrom_path" "'$bios_folder/mcpx_1.0.bin'" "xemu" "sys.files"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/xemu/xemu.toml" "flashrom_path" "'$bios_folder/Complex.bin'" "xemu" "sys.files"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/xemu/xemu.toml" "eeprom_path" "'$saves_folder/xbox/xemu/xbox-eeprom.bin'" "xemu" "sys.files"
          set_setting_value "$multi_user_data_folder/$SteamAppUser/config/xemu/xemu.toml" "hdd_path" "'$bios_folder/xbox_hdd.qcow2'" "xemu" "sys.files"
          dir_prep "$multi_user_data_folder/$SteamAppUser/config/xemu" "$XDG_CONFIG_HOME/xemu" # Creating config folder in $XDG_CONFIG_HOME for consistentcy and linking back to original location where component will look
          dir_prep "$multi_user_data_folder/$SteamAppUser/config/xemu" "$XDG_DATA_HOME/xemu/xemu"
        else # Single-user actions
          rm -rf "$XDG_CONFIG_HOME/xemu"
          rm -rf "$XDG_DATA_HOME/xemu"
          dir_prep "$XDG_CONFIG_HOME/xemu" "$XDG_DATA_HOME/xemu/xemu" # Creating config folder in $XDG_CONFIG_HOME for consistentcy and linking back to original location where component will look
          cp -fv "$config/xemu/xemu.toml" "$xemuconf"
          set_setting_value "$xemuconf" "screenshot_dir" "'$screenshots_folder'" "xemu" "General"
          set_setting_value "$xemuconf" "bootrom_path" "'$bios_folder/mcpx_1.0.bin'" "xemu" "sys.files"
          set_setting_value "$xemuconf" "flashrom_path" "'$bios_folder/Complex.bin'" "xemu" "sys.files"
          set_setting_value "$xemuconf" "eeprom_path" "'$saves_folder/xbox/xemu/xbox-eeprom.bin'" "xemu" "sys.files"
          set_setting_value "$xemuconf" "hdd_path" "'$bios_folder/xbox_hdd.qcow2'" "xemu" "sys.files"
        fi # Shared actions
        create_dir "$saves_folder/xbox/xemu/"
        # Preparing HD dummy Image if the image is not found
        if [ ! -f "$bios_folder/xbox_hdd.qcow2" ]
        then
          cp -f "/app/retrodeck/extras/XEMU/xbox_hdd.qcow2" "$bios_folder/xbox_hdd.qcow2"
        fi
      fi
      if [[ "$action" == "postmove" ]]; then # Run only post-move commands
        set_setting_value "$xemuconf" "screenshot_dir" "'$screenshots_folder'" "xemu" "General"
        set_setting_value "$xemuconf" "bootrom_path" "'$bios_folder/mcpx_1.0.bin'" "xemu" "sys.files"
        set_setting_value "$xemuconf" "flashrom_path" "'$bios_folder/Complex.bin'" "xemu" "sys.files"
        set_setting_value "$xemuconf" "eeprom_path" "'$saves_folder/xbox/xemu/xbox-eeprom.bin'" "xemu" "sys.files"
        set_setting_value "$xemuconf" "hdd_path" "'$bios_folder/xbox_hdd.qcow2'" "xemu" "sys.files"
      fi
    fi

    if [[ "$component" =~ ^(vita3k|all)$ ]]; then
    component_found="true"
      if [[ "$action" == "reset" ]]; then # Run reset-only commands
        log i "----------------------"
        log i "Prepearing Vita3K"
        log i "----------------------"
        if [[ $multi_user_mode == "true" ]]; then # Multi-user actions
          log d "Figure out what Vita3k needs for multi-user"
        else # Single-user actions
          # NOTE: the component is writing in "." so it must be placed in the rw filesystem. A symlink of the binary is already placed in /app/bin/Vita3K
          rm -rf "$XDG_CONFIG_HOME/Vita3K"
          create_dir "$XDG_CONFIG_HOME/Vita3K"
          cp -fvr "$config/vita3k/config.yml" "$vita3kconf" # component config
          cp -fvr "$config/vita3k/ux0" "$bios_folder/Vita3K/" # User config
          set_setting_value "$vita3kconf" "pref-path" "$bios_folder/Vita3K/" "vita3k"
        fi
        # Shared actions
        dir_prep "$saves_folder/psvita/vita3k" "$bios_folder/Vita3K/ux0/user/00/savedata" # Multi-user safe?
      fi
      if [[ "$action" == "postmove" ]]; then # Run only post-move commands
        dir_prep "$saves_folder/psvita/vita3k" "$bios_folder/Vita3K/ux0/user/00/savedata" # Multi-user safe?
        set_setting_value "$vita3kconf" "pref-path" "$bios_folder/Vita3K/" "vita3k"
      fi
    fi

    if [[ "$component" =~ ^(mame|all)$ ]]; then
    component_found="true"
      # TODO: do a proper script
      # This is just a placeholder script to test the emulator's flow
      log i "----------------------"
      log i "Prepearing MAME"
      log i "----------------------"

      # TODO: probably some of these needs to be put elsewhere
      create_dir "$saves_folder/mame-sa"
      create_dir "$saves_folder/mame-sa/nvram"
      create_dir "$states_folder/mame-sa"
      create_dir "$rdhome/screenshots/mame-sa"
      create_dir "$saves_folder/mame-sa/diff"

      create_dir "$XDG_CONFIG_HOME/ctrlr"
      create_dir "$XDG_CONFIG_HOME/mame/ini"
      create_dir "$XDG_CONFIG_HOME/mame/cfg"
      create_dir "$XDG_CONFIG_HOME/mame/inp"

      create_dir "$XDG_DATA_HOME/mame/plugin-data"
      create_dir "$XDG_DATA_HOME/mame/hash"
      create_dir "$bios_folder/mame-sa/samples"
      create_dir "$XDG_DATA_HOME/mame/assets/artwork"
      create_dir "$XDG_DATA_HOME/mame/assets/fonts"
      create_dir "$XDG_DATA_HOME/mame/assets/crosshair"
      create_dir "$XDG_DATA_HOME/mame/plugins"
      create_dir "$XDG_DATA_HOME/mame/assets/language"
      create_dir "$XDG_DATA_HOME/mame/assets/software"
      create_dir "$XDG_DATA_HOME/mame/assets/comments"
      create_dir "$XDG_DATA_HOME/mame/assets/share"
      create_dir "$XDG_DATA_HOME/mame/dats"
      create_dir "$XDG_DATA_HOME/mame/folders"
      create_dir "$XDG_DATA_HOME/mame/assets/cabinets"
      create_dir "$XDG_DATA_HOME/mame/assets/cpanel"
      create_dir "$XDG_DATA_HOME/mame/assets/pcb"
      create_dir "$XDG_DATA_HOME/mame/assets/flyers"
      create_dir "$XDG_DATA_HOME/mame/assets/titles"
      create_dir "$XDG_DATA_HOME/mame/assets/ends"
      create_dir "$XDG_DATA_HOME/mame/assets/marquees"
      create_dir "$XDG_DATA_HOME/mame/assets/artwork-preview"
      create_dir "$XDG_DATA_HOME/mame/assets/bosses"
      create_dir "$XDG_DATA_HOME/mame/assets/logo"
      create_dir "$XDG_DATA_HOME/mame/assets/scores"
      create_dir "$XDG_DATA_HOME/mame/assets/versus"
      create_dir "$XDG_DATA_HOME/mame/assets/gameover"
      create_dir "$XDG_DATA_HOME/mame/assets/howto"
      create_dir "$XDG_DATA_HOME/mame/assets/select"
      create_dir "$XDG_DATA_HOME/mame/assets/icons"
      create_dir "$XDG_DATA_HOME/mame/assets/covers"
      create_dir "$XDG_DATA_HOME/mame/assets/ui"
      create_dir "$shaders_folder/mame/bgfx/"

      dir_prep "$saves_folder/mame-sa/hiscore" "$XDG_CONFIG_HOME/mame/hiscore"
      cp -fvr "$config/mame/mame.ini" "$mameconf"
      cp -fvr "$config/mame/ui.ini" "$mameuiconf"
      cp -fvr "$config/mame/default.cfg" "$mamedefconf"
      cp -fvr "/app/share/mame/bgfx/"* "$shaders_folder/mame/bgfx"

      sed -i 's#RETRODECKROMSDIR#'"$roms_folder"'#g' "$mameconf" # one-off as roms folders are a lot
      set_setting_value "$mameconf" "nvram_directory" "$saves_folder/mame-sa/nvram" "mame"
      set_setting_value "$mameconf" "state_directory" "$states_folder/mame-sa" "mame"
      set_setting_value "$mameconf" "snapshot_directory" "$screenshots_folder/mame-sa" "mame"
      set_setting_value "$mameconf" "diff_directory" "$saves_folder/mame-sa/diff" "mame"
      set_setting_value "$mameconf" "samplepath" "$bios_folder/mame-sa/samples" "mame"
      set_setting_value "$mameconf" "cheatpath" "$cheats_folder/mame" "mame"
      set_setting_value "$mameconf" "bgfx_path" "$shaders_folder/mame/bgfx/" "mame"

      log i "Placing cheats in \"$cheats_folder/mame\""
      unzip -j -o "$config/mame/cheat0264.zip" 'cheat.7z' -d "$cheats_folder/mame"

    fi

    if [[ "$component" =~ ^(gzdoom|all)$ ]]; then
    component_found="true"
      # TODO: do a proper script
      # This is just a placeholder script to test the emulator's flow
      log i "----------------------"
      log i "Prepearing GZDOOM"
      log i "----------------------"

      create_dir "$XDG_CONFIG_HOME/gzdoom"
      create_dir "$XDG_DATA_HOME/gzdoom/audio/midi"
      create_dir "$XDG_DATA_HOME/gzdoom/audio/fm_banks"
      create_dir "$XDG_DATA_HOME/gzdoom/audio/soundfonts"
      create_dir "$bios_folder/gzdoom"

      cp -fvr "$config/gzdoom/gzdoom.ini" "$XDG_CONFIG_HOME/gzdoom"

      sed -i 's#RETRODECKHOMEDIR#'"$rdhome"'#g' "$XDG_CONFIG_HOME/gzdoom/gzdoom.ini" # This is an unfortunate one-off because set_setting_value does not currently support JSON
      sed -i 's#RETRODECKROMSDIR#'"$roms_folder"'#g' "$XDG_CONFIG_HOME/gzdoom/gzdoom.ini" # This is an unfortunate one-off because set_setting_value does not currently support JSON
      sed -i 's#RETRODECKSAVESDIR#'"$saves_folder"'#g' "$XDG_CONFIG_HOME/gzdoom/gzdoom.ini" # This is an unfortunate one-off because set_setting_value does not currently support JSON
    fi

    if [[ "$component" =~ ^(portmaster|all)$ ]]; then
    component_found="true"
      # TODO: MultiUser
      log i "----------------------"
      log i "Prepearing PortMaster"
      log i "----------------------"

      rm -rf "$XDG_DATA_HOME/PortMaster"
      unzip "/app/retrodeck/PortMaster.zip" -d "$XDG_DATA_HOME/"
      cp -f "$XDG_DATA_HOME/PortMaster/retrodeck/PortMaster.txt" "$XDG_DATA_HOME/PortMaster/PortMaster.sh"
      chmod +x "$XDG_DATA_HOME/PortMaster/PortMaster.sh"
      rm -f "$roms_folder/portmaster/PortMaster.sh"
      install -Dm755 "$XDG_DATA_HOME/PortMaster/PortMaster.sh" "$roms_folder/portmaster/PortMaster.sh"
      create_dir "$XDG_DATA_HOME/PortMaster/config/"
      cp "$config/portmaster/config.json" "$XDG_DATA_HOME/PortMaster/config/config.json"

    fi

    if [[ "$component" =~ ^(ruffle|all)$ ]]; then
    component_found="true"
      log i "----------------------"
      log i "Prepearing Ruffle"
      log i "----------------------"

      rm -rf "$XDG_CONFIG_HOME/ruffle"

      # Ruffle creates a directory with the full rom paths in it, so this is necessary
      # TODO: be aware of this when multi user support will be integrated for this component
      dir_prep "$saves_folder/flash" "$XDG_DATA_HOME/ruffle/SharedObjects/localhost/$roms_folder/flash"

      if [[ "$action" == "postmove" ]]; then # Run only post-move commands
        dir_prep "$saves_folder/flash" "$XDG_DATA_HOME/ruffle/SharedObjects/localhost/$roms_folder/flash"
      fi
      
    fi

    if [[ $component_found == "false" ]]; then
      log e "Supplied component $component not found, not resetting"
    fi
  done

  # Update presets for all components after any reset or move
  if [[ ! "$component" == "retrodeck" ]]; then
    build_retrodeck_current_presets
  fi
}
