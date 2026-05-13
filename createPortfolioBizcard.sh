#!/bin/bash

# 1. Gather Project Information
read -p "Enter project name (e.g., adib): " NAME
echo "Choose project type:"
echo "1) Business Card Only"
echo "2) Business Card + Website"
read -p "Selection [1-2]: " TYPE

# 2. Gather Ports and Network
read -p "Enter port for ${NAME}-biz: " BIZ_PORT
if [ "$TYPE" == "2" ]; then
    read -p "Enter port for ${NAME}-website: " WEB_PORT
fi
read -p "Enter network name (leave empty for none): " NET_NAME

# --- Create Folders ---
echo "Creating project directories..."
mkdir -p "${NAME}Biz"
if [ "$TYPE" == "2" ]; then
    mkdir -p "${NAME}Website"
fi

# 3. Create a temporary file for the new service block
TEMP_BLOCK=$(mktemp)

# Added a blank line at the top for better formatting
cat <<EOF > "$TEMP_BLOCK"

  ${NAME}-biz:
    image: nginx:alpine
    container_name: ${NAME}-biz
    restart: unless-stopped
    ports:
      - ${BIZ_PORT}:80
    volumes:
      - ./${NAME}Biz:/usr/share/nginx/html
EOF

if [ -n "$NET_NAME" ]; then
    echo "    networks:" >> "$TEMP_BLOCK"
    echo "      - $NET_NAME" >> "$TEMP_BLOCK"
fi

if [ "$TYPE" == "2" ]; then
    cat <<EOF >> "$TEMP_BLOCK"

  ${NAME}-website:
    image: nginx:alpine
    container_name: ${NAME}-website
    restart: unless-stopped
    ports:
      - ${WEB_PORT}:80
    volumes:
      - ./${NAME}Website:/usr/share/nginx/html
EOF
    if [ -n "$NET_NAME" ]; then
        echo "    networks:" >> "$TEMP_BLOCK"
        echo "      - $NET_NAME" >> "$TEMP_BLOCK"
    fi
fi

# 4. Create or Update docker-compose.yml
if [ ! -f "docker-compose.yml" ]; then
    echo "services:" > docker-compose.yml
fi

# Use sed to read the temp file into the compose file after 'services:'
sed -i "/services:/r $TEMP_BLOCK" docker-compose.yml

# Clean up temp file
rm "$TEMP_BLOCK"

# 5. Handle Global Network Section
if [ -n "$NET_NAME" ]; then
    if ! grep -q "^networks:" docker-compose.yml; then
        echo -e "\nnetworks:\n  $NET_NAME:\n    external: true" >> docker-compose.yml
    elif ! grep -q "  $NET_NAME:" docker-compose.yml; then
        echo "  $NET_NAME:" >> docker-compose.yml
        echo "    external: true" >> docker-compose.yml
    fi
fi

echo "Done! Folders ready and docker-compose.yml updated with better spacing."
echo "Run docker compose down && docker compose up -d"
sleep 1
nano docker-compose.yml
