#!/bin/bash

# Function to stop the FTP server
stop_server() {
    if [ -n "$SERVER_PID" ]; then
        kill $SERVER_PID
        pkill -f ftp_server.py
    fi
}

# Start the FTP server
ftp_id="RetroDECK"
ftp_pass="RetroDECK"
ftp_port=6346
rdhome="/home/jay/retrodeck" #DEBUG
python3 /home/jay/gits/RetroDECK/functions/ftp_server.py "$rdhome" "$ftp_port" "$ftp_id" "$ftp_pass" &
SERVER_PID=$(pgrep -f "python3 /home/jay/gits/RetroDECK/functions/ftp_server.py")

# Main menu with only "Stop" button
zenity --info --text="FTP server started, log in with:\n\nID: $ftp_id\nPassword: $ftp_pass\nPort: $ftp_port.\n\nPress 'Stop' when done" --ok-label="Stop"
stop_server