import os
import socket
import threading
import sys
import random

def handle_client(client_socket, root_folder, username, password):
    authenticated = False
    try:
        client_socket.send("220 Welcome to the FTP server\r\n".encode())

        while True:
            request = client_socket.recv(1024).decode().strip()
            if not request:
                break

            if request.startswith("USER"):
                if request.split()[1] == username:
                    client_socket.send("331 User name okay, need password.\r\n".encode())
                else:
                    client_socket.send("530 Invalid username.\r\n".encode())
                    break
            elif request.startswith("PASS"):
                if request.split()[1] == password and not authenticated:
                    client_socket.send("230 User logged in, proceed.\r\n".encode())
                    authenticated = True
                else:
                    client_socket.send("530 Authentication failed.\r\n".encode())
                    break
            elif authenticated:
                if request.startswith("PWD"):
                    client_socket.send(f"257 \"{root_folder}\" is the current directory.\r\n".encode())
                elif request.startswith("LIST"):
                    # This is a placeholder for proper LIST command handling with data connection
                    client_socket.send("150 Here comes the directory listing.\r\n".encode())
                    client_socket.send("This would be the file list\r\n".encode())
                    client_socket.send("226 Directory send OK.\r\n".encode())
                elif request.startswith("TYPE"):
                    type_code = request.split()[1]
                    if type_code.upper() == 'I':
                        client_socket.send("200 Switching to Binary mode.\r\n".encode())
                    elif type_code.upper() == 'A':
                        client_socket.send("200 Switching to ASCII mode.\r\n".encode())
                    else:
                        client_socket.send("504 Command not implemented for that parameter.\r\n".encode())
                elif request.startswith("PASV"):
                    # Dummy response for PASV command
                    client_socket.send("227 Entering Passive Mode (127,0,0,1,204,173).\r\n".encode())
                elif request.startswith("PORT"):
                    # Dummy response for PORT command
                    client_socket.send("200 PORT command successful.\r\n".encode())
                else:
                    client_socket.send("500 Syntax error, command unrecognized.\r\n".encode())
            else:
                client_socket.send("530 Please login with USER and PASS.\r\n".encode())

    except Exception as e:
        print(f"Error: {e}")

    finally:
        client_socket.close()

def start_ftp_server(root_folder, port, username, password):
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.bind(('localhost', port))
    server_socket.listen(5)
    print("FTP server started on port", port)

    try:
        while True:
            client_socket, client_address = server_socket.accept()
            print(f"Accepted connection from {client_address}")
            client_handler = threading.Thread(target=handle_client, args=(client_socket, root_folder, username, password))
            client_handler.start()

    except KeyboardInterrupt:
        print("Shutting down the server.")
        server_socket.close()

if __name__ == "__main__":
    if len(sys.argv) != 5:
        print("Usage: python3 ftp_server.py root_path port username password")
        sys.exit(1)

    root_folder = os.path.expanduser(sys.argv[1])
    port_number = int(sys.argv[2])
    username = sys.argv[3]
    password = sys.argv[4]

    start_ftp_server(root_folder, port_number, username, password)
