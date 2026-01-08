#!/bin/bash
# ---------------------------------------------------------------------------
# nginxcompile-boringssl.sh - By VincentdeCristo.
#
# Solves the C++/C linkage error by adding -lstdc++.
# ---------------------------------------------------------------------------

PROGNAME=${0##*/}
VERSION="7.0.0-LINKER-FIXED"
NGINXBUILDPATH="/usr/src"

clean_up() { # Perform pre-exit housekeeping
  return
}

error_exit() {
  echo -e "\n${PROGNAME}: ERROR: ${1:-"Unknown Error"}" >&2
  clean_up
  exit 1
}

graceful_exit() {
  clean_up
  exit
}

signal_exit() { # Handle trapped signals
  case $1 in
    INT)
      error_exit "Program interrupted by user" ;;
    TERM)
      echo -e "\n$PROGNAME: Program terminated" >&2
      graceful_exit ;;
    *)
      error_exit "$PROGNAME: Terminating on unknown signal" ;;
  esac
}

# Trap signals
trap "signal_exit TERM" TERM HUP
trap "signal_exit INT"  INT

# --- Script Start ---

# Check for root UID
if [[ $(id -u) != 0 ]]; then
  error_exit "You must be the superuser to run this script."
fi

# Check dependencies
echo "--- Step 1: Checking dependencies..."
if ! command -v go &>/dev/null || ! command -v git &>/dev/null || ! command -v ninja &>/dev/null || ! command -v cmake &>/dev/null; then
    error_exit "Please install dependencies: go, git, ninja-build and cmake"
fi

# Check for build-essential
if ! dpkg -l | grep -qw build-essential; then
    error_exit "Please install 'build-essential' package."
fi

# Check for PCRE libraries
if ! dpkg -l | grep -qw libpcre3 || ! dpkg -l | grep -qw libpcre3-dev; then
    error_exit "Please install 'libpcre3' and 'libpcre3-dev' packages."
fi

# Check for zlib
if ! dpkg -l | grep -qw zlib1g || ! dpkg -l | grep -qw zlib1g-dev; then
    error_exit "Please install 'zlib1g' and 'zlib1g-dev' packages."
fi
echo "Dependencies are OK."

# Clean up previous build
echo -e "\n--- Step 2: Cleaning up previous build environment..."
if [ ! -d "$NGINXBUILDPATH" ]; then
    mkdir -p "$NGINXBUILDPATH" || error_exit "Failed to create directory $NGINXBUILDPATH."
fi
MODULES_TO_CLEAN=(nginx boringssl ngx_brotli headers-more-nginx-module ngx_devel_kit set-misc-nginx-module)
for module in "${MODULES_TO_CLEAN[@]}"; do
    if [ -d "$NGINXBUILDPATH/$module" ]; then
        rm -rf "$NGINXBUILDPATH/$module" >/dev/null 2>&1
    fi
done
echo "Cleanup complete."

# Clone latest source code
echo -e "\n--- Step 3: Cloning latest source code..."
git clone https://github.com/nginx/nginx.git "$NGINXBUILDPATH/nginx" --depth=1 || error_exit "Failed to clone nginx."
git clone https://boringssl.googlesource.com/boringssl "$NGINXBUILDPATH/boringssl" || error_exit "Failed to clone boringssl."
git clone https://github.com/google/ngx_brotli "$NGINXBUILDPATH/ngx_brotli" --recurse-submodules --depth=1 || error_exit "Failed to clone brotli."
git clone https://github.com/openresty/headers-more-nginx-module.git "$NGINXBUILDPATH/headers-more-nginx-module" --depth=1 || error_exit "Failed to clone headers-more-nginx-module."
git clone https://github.com/vision5/ngx_devel_kit.git "$NGINXBUILDPATH/ngx_devel_kit" --depth=1 || error_exit "Failed to clone ngx_devel_kit."
git clone https://github.com/openresty/set-misc-nginx-module.git "$NGINXBUILDPATH/set-misc-nginx-module" --depth=1 || error_exit "Failed to clone set-misc-nginx-module."
echo "Cloning complete."

# Build Brotli dependencies
echo -e "\n--- Step 4: Building Brotli libraries..."
cd "$NGINXBUILDPATH/ngx_brotli/deps/brotli" || error_exit "Failed to cd into brotli deps."
mkdir -p out
cd out
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=./installed .. || error_exit "Failed to cmake ngx_brotli."
make -j "$(nproc)" || error_exit "Failed to build ngx_brotli modules."
echo "Brotli libraries built successfully."


# Build BoringSSL
echo -e "\n--- Step 5: Building BoringSSL..."
mkdir -p "$NGINXBUILDPATH/boringssl/build"
cd "$NGINXBUILDPATH/boringssl/build"
cmake -GNinja -DCMAKE_BUILD_TYPE=Release .. || error_exit "Failed to cmake boringssl."
ninja || error_exit "Failed to compile boringssl."
echo "BoringSSL built successfully."

# Configure Nginx
echo -e "\n--- Step 6: Configuring Nginx..."
cd "$NGINXBUILDPATH/nginx"
# Create necessary cache directories for nginx
mkdir -p /var/cache/nginx/client_temp
# THIS IS THE **FINAL** CONFIGURE COMMAND WITH THE LINKER FIX
./auto/configure \
    --prefix=/opt/nginx \
    --sbin-path=/opt/nginx/sbin/nginx \
    --conf-path=/opt/nginx/etc/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --user=www-data \
    --group=www-data \
    --with-openssl="$NGINXBUILDPATH/boringssl" \
    --with-cc-opt="-g -O2 -flto=auto -ffat-lto-objects -fstack-protector-strong -Wformat -Werror=format-security -fPIC -I$NGINXBUILDPATH/boringssl/include" \
    --with-ld-opt="-Wl,-Bsymbolic-functions -flto=auto -ffat-lto-objects -Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie -L$NGINXBUILDPATH/boringssl/build -L$NGINXBUILDPATH/ngx_brotli/deps/brotli/out -lstdc++" \
    --with-http_v3_module \
    --with-http_v2_module \
    --with-http_ssl_module \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-threads \
    --add-module="$NGINXBUILDPATH/ngx_brotli" \
    --add-module="$NGINXBUILDPATH/ngx_devel_kit" \
    --add-module="$NGINXBUILDPATH/set-misc-nginx-module" \
    --add-module="$NGINXBUILDPATH/headers-more-nginx-module" \
    || error_exit "Nginx configuration failed."
echo "Nginx configured successfully."


# --- WORKAROUND FOR NGINX MAKEFILE DEPENDENCY ---
echo -e "\n--- Step 7: Applying workaround for Nginx Makefile dependencies..."
FAKE_INSTALL_DIR="$NGINXBUILDPATH/boringssl/.openssl"
mkdir -p "$FAKE_INSTALL_DIR/lib"
mkdir -p "$FAKE_INSTALL_DIR/include"
cp -r "$NGINXBUILDPATH/boringssl/include/openssl" "$FAKE_INSTALL_DIR/include/" || error_exit "Failed to copy BoringSSL headers."
cp "$NGINXBUILDPATH/boringssl/build/libssl.a" "$FAKE_INSTALL_DIR/lib/" || error_exit "Failed to copy libssl.a."
cp "$NGINXBUILDPATH/boringssl/build/libcrypto.a" "$FAKE_INSTALL_DIR/lib/" || error_exit "Failed to copy libcrypto.a."
echo "Workaround applied successfully."
# --- END WORKAROUND ---


# Make and install Nginx
echo -e "\n--- Step 8: Compiling and installing Nginx..."
cd "$NGINXBUILDPATH/nginx"
make -j "$(nproc)" || error_exit "Error compiling nginx."
make install || error_exit "Error installing nginx."
echo "Nginx installed successfully to /opt/nginx."

# Create systemd service file
echo -e "\n--- Step 9: Creating systemd service file..."
cat > /etc/systemd/system/nginx.service << EOL
[Unit]
Description=A high performance web server and a reverse proxy server
Documentation=man:nginx(8)
After=network.target

[Service]
Type=forking
PIDFile=/var/run/nginx.pid
RuntimeDirectory=nginx
ExecStartPre=/opt/nginx/sbin/nginx -t -q -g 'daemon on; master_process on;'
ExecStart=/opt/nginx/sbin/nginx -g 'daemon on; master_process on;'
ExecReload=/opt/nginx/sbin/nginx -g 'daemon on; master_process on;' -s reload
ExecStop=-/sbin/start-stop-daemon --quiet --stop --retry QUIT/5 --pidfile /var/run/nginx.pid
TimeoutStopSec=5
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOL
echo "Systemd service file created at /etc/systemd/system/nginx.service"

# Configure PATH environment variable
echo -e "\n--- Step 10: Configuring PATH environment variable..."
# Check if PATH is already configured
if ! grep -q "/opt/nginx/sbin" /etc/profile; then
    echo "PATH=/opt/nginx/sbin:\$PATH" >> /etc/profile || error_exit "Failed to update /etc/profile"
    echo "PATH environment variable added to /etc/profile"
else
    echo "PATH already configured in /etc/profile"
fi

# Apply the PATH changes
export PATH="/opt/nginx/sbin:$PATH"
source /etc/profile
echo "PATH environment variable updated for current session"

# Final instructions
echo -e "\n--- ALL DONE! CONGRATULATIONS! ---"
echo "Next steps:"
echo "1. Reload systemd to recognize the new service: sudo systemctl daemon-reload"
echo "2. Enable Nginx to start on boot: sudo systemctl enable nginx"
echo "3. Start the Nginx service now: sudo systemctl start nginx"
echo "4. Check its status: sudo systemctl status nginx"
echo "5. You can now use 'nginx' command directly (PATH has been configured)"
echo ""
echo "Configuration file is at: /opt/nginx/etc/nginx.conf"
echo "To enable Post-Quantum crypto, use: ssl_ecdh_curve X25519Kyber768:X25519;"
echo "To set a custom server header, use: more_set_headers \"Server: your_name\";"

# Clean up build source files
echo -e "\n--- Step 11: Cleaning up build source files..."
for module in "${MODULES_TO_CLEAN[@]}"; do
    if [ -d "$NGINXBUILDPATH/$module" ]; then
        rm -rf "$NGINXBUILDPATH/$module" >/dev/null 2>&1
    fi
done
echo "Build source files cleaned up."

graceful_exit
