#!/bin/bash

# Configura il tuo cheevos_username e la tua API key di RetroAchievements (sostituisci con i tuoi dati reali)
cheevos_username="Xargon"
API_KEY=""

# Funzione per ottenere i retroachievements
get_achievements() {
    curl -s "https://retroachievements.org/API/API_GetUserSummary.php?z=$cheevos_username&u=$cheevos_username&y=$API_KEY&g=10&a=2"
}

# Ottieni i dati degli achievements
response=$(get_achievements)

# Verifica che la risposta non sia vuota o null
if [ -z "$response" ] || [ "$response" == "null" ]; then
    echo "Error: empty reply from the API."
    exit 1
fi

game_titles=$(echo "$response" | jq -r '.RecentAchievements[][].GameTitle')
cheevos_badges=$(echo "$response" | jq -r '.RecentAchievements[][].BadgeName')
#cheevos_badges="https://retroachievements.org/Badge/"$(echo "$response" | jq -r '.RecentAchievements[][].BadgeName')".png"
cheevos_titles=$(echo "$response" | jq -r '.RecentAchievements[][].Title')
cheevos_descs=$(echo "$response" | jq -r '.RecentAchievements[][].Description')

IFS=$'\n' read -r -d '' -a game_title_array < <(printf '%s\0' "$game_titles")
IFS=$'\n' read -r -d '' -a cheevos_badge_array < <(printf '%s\0' "$cheevos_badges")
IFS=$'\n' read -r -d '' -a cheevos_title_array < <(printf '%s\0' "$cheevos_titles")
IFS=$'\n' read -r -d '' -a cheevos_desc_array < <(printf '%s\0' "$cheevos_descs")

# Costruisci l'elenco degli achievement
achievement_list=()
for i in "${!game_title_array[@]}"; do
    achievement_list+=("\""https://retroachievements.org/Badge/"${cheevos_badge_array[i]}".png"\"")
    achievement_list+=("\"${game_title_array[i]}\"")
    achievement_list+=("\"${cheevos_title_array[i]}\"")
    achievement_list+=("\"${cheevos_desc_array[i]}\"")
done

# Mostra la lista in una finestra di dialogo Zenity
zenity --list \
    --title="$USERNAME's RetroAchievements" \
    --text="Here are your latest RetroAchievements:" \
    --column="" --column="Game" --column="Achievement" --column="Description" \
    --width=1280 --height=800 \
    "${achievement_list[@]}"