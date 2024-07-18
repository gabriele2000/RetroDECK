#!/bin/bash

# Configura il tuo cheevos_username e la tua API key di RetroAchievements (sostituisci con i tuoi dati reali)
cheevos_username="Xargon"
API_KEY=""

# Funzione per ottenere i retroachievements
get_achievements() {
    curl -s "https://retroachievements.org/API/API_GetUserSummary.php?z=$cheevos_username&u=$cheevos_username&y=$API_KEY&g=1&a=2"
}

# Ottieni i dati degli achievements
response=$(get_achievements)
game_title=$(echo "$response" | jq -r '.RecentAchievements[][].GameTitle')
cheevos_badge="https://retroachievements.org/Badge/"$(echo "$response" | jq -r '.RecentAchievements[][].BadgeName')".png"
cheevos_title=$(echo "$response" | jq -r '.RecentAchievements[][].Title')
cheevos_desc=$(echo "$response" | jq -r '.RecentAchievements[][].Description')


# Verifica che la risposta non sia vuota o null
if [ -z "$response" ] || [ "$response" == "null" ]; then
    echo "Error: empty reply from the API."
    exit 1
fi

# Estrai e formatta i dati per Zenity
achievement_list=("<img src=$cheevos_badge>" "$game_title" "$cheevos_title" "$cheevos_desc")



# Mostra la lista in una finestra di dialogo Zenity
zenity --list \
    --title="$USERNAME's RetroAchievements" \
    --text="Here are your latest RetroAchievements:" \
    --column="" --column="Game" --column="Achievement" --column="Description" \
    --width=1280 --height=800 \
    "${achievement_list[@]}"