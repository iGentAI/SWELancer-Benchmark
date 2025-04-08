#!/bin/bash

# SWELancer-Benchmark Setup Script for Fedora-based system
# Based on the original Dockerfile and run.sh

# Start the timer
START_TIME=$SECONDS

# Function to print usage information
function print_usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  -i, --issue-id <id>   Set the issue ID (default: 1)"
  echo "  -h, --help            Display this help message and exit"
  echo
  echo "Example:"
  echo "  $0 -i 42              Run setup with issue ID 42"
  echo "  $0 --issue-id 42      Same as above"
}

# Parse command-line arguments
ISSUE_ID="1"  # Default value

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--issue-id)
      ISSUE_ID="$2"
      shift 2
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      print_usage
      exit 1
      ;;
  esac
done

# Validate issue ID (should be a positive integer)
if ! [[ "$ISSUE_ID" =~ ^[0-9]+$ ]]; then
  echo "Error: Issue ID must be a positive integer"
  print_usage
  exit 1
fi

# Print issue ID being used
echo "Using Issue ID: $ISSUE_ID"

# Exit on errors
set -e

# Print status messages
function echo_status() {
  echo -e "\n\033[1;34m[+] $1\033[0m"
}

# Function to install packages with error handling
function install_packages() {
  echo_status "Installing packages: $*"
  local failed_pkgs=""

  for pkg in "$@"; do
    echo "Trying to install package: $pkg"
    if ! sudo dnf install -y "$pkg"; then
      echo -e "\033[1;33mWarning: Package $pkg installation failed, continuing...\033[0m"
      failed_pkgs="$failed_pkgs $pkg"
    fi
  done

  if [ -n "$failed_pkgs" ]; then
    echo -e "\033[1;33mThe following packages failed to install:$failed_pkgs\033[0m"
    echo -e "\033[1;33mThis might be okay depending on which packages failed.\033[0m"
  fi
}

# Set environment variables (same as in Dockerfile)
export DEBIAN_FRONTEND=noninteractive
export NVM_DIR=$HOME/.nvm
export PYTHONUNBUFFERED=1
export PYTHONPATH=/app/tests
export DISPLAY=:99
export LIBGL_ALWAYS_INDIRECT=1

# Required for Ansible playbooks
export ISSUE_ID="$ISSUE_ID"  # Use the issue ID from command line
export PUSHER_APP_ID=${PUSHER_APP_ID:-"1234567"}
export PUSHER_APP_KEY=${PUSHER_APP_KEY:-"abcdef12345678900000"}
export PUSHER_APP_SECRET=${PUSHER_APP_SECRET:-"fedcba09876543210000"}
export USE_WEB_PROXY=${USE_WEB_PROXY:-"false"}
export EXPENSIFY_URL=${EXPENSIFY_URL:-"https://www.expensify.com"}
export NEW_EXPENSIFY_URL=${NEW_EXPENSIFY_URL:-"https://dev.new.expensify.com"}

# Create necessary directories (similar to Dockerfile)
echo_status "Creating necessary directories"
sudo mkdir -p /app
sudo mkdir -p /app/tests
sudo mkdir -p /app/tests/logs
sudo mkdir -p /app/tests/logs/$ISSUE_ID
sudo mkdir -p /app/tests/attempts
sudo mkdir -p /app/tests/attempts/$ISSUE_ID
sudo mkdir -p /app/tests/issues
# Set appropriate permissions
sudo chown -R $USER:$USER /app

# Clone the SWELancer-Benchmark repository
if [ -d "SWELancer-Benchmark" ]; then
  echo_status "SWELancer-Benchmark repository already cloned, skipping clone"
else
  echo_status "Cloning SWELancer-Benchmark repository"
  git clone https://github.com/openai/SWELancer-Benchmark.git || {
    echo "ERROR: Failed to clone SWELancer-Benchmark. Cannot continue without the repository."
    exit 1
  }
fi

echo_status "Updating system packages"
sudo dnf update -y

# Detect OS type
echo_status "Detecting operating system"
OS_TYPE="unknown"
if [ -f /etc/fedora-release ]; then
  OS_TYPE="fedora"
  echo "Detected Fedora system"
elif [ -f /etc/amazon-release ]; then
  OS_TYPE="amazon_linux"
  echo "Detected Amazon Linux system"
else
  echo "Unknown OS type, defaulting to minimal compatibility mode"
fi

# Install basic utilities (map from apt-get to dnf)
echo_status "Installing basic utilities"
COMMON_PACKAGES="curl git wget tar gzip gnupg2 openssh-clients xz patch"

# Add OS-specific packages
if [ "$OS_TYPE" = "fedora" ]; then
  # Fedora-specific packages
  install_packages $COMMON_PACKAGES python3-libdnf5
elif [ "$OS_TYPE" = "amazon_linux" ]; then
  # Amazon Linux-specific packages
  # No equivalent for python3-libdnf5 on Amazon Linux, we'll rely on pip to handle dependencies
  install_packages $COMMON_PACKAGES
else
  # Default to common packages for unknown systems
  install_packages $COMMON_PACKAGES
fi

# Check for Python 3.12 and install it if needed
echo_status "Installing Python 3.12"

# Check if Python 3.12 is already installed
if ! command -v python3.12 &>/dev/null; then
  install_packages python3.12 python3.12-devel
fi

# Verify Python 3.12 installation
python3.12 --version

# Install pip for Python 3.12
echo_status "Installing pip for Python 3.12"
python3.12 -m ensurepip || install_packages python3-pip
python3.12 -m pip install --upgrade pip

# Create a virtual environment for Python 3.12
echo_status "Creating Python 3.12 virtual environment"
VENV_DIR="/app/venv"
python3.12 -m venv "$VENV_DIR" || {
  echo "ERROR: Failed to create virtual environment. Exiting."
  exit 1
}

# Activate the virtual environment
echo_status "Activating Python virtual environment"
source "$VENV_DIR/bin/activate"

# Ensure the venv is activated
if [[ "$VIRTUAL_ENV" != "$VENV_DIR" ]]; then
  echo "ERROR: Failed to activate virtual environment. Exiting."
  exit 1
}

# Verify we're using the correct Python from the venv
echo "Using Python from virtual environment: $(which python)"
python --version

# Upgrade pip in the virtual environment
python -m pip install --upgrade pip

# Install browser dependencies (matching Dockerfile's intent)
echo_status "Installing browser dependencies"
BROWSER_DEPS="chromium nss-tools at-spi2-atk libXcomposite libXrandr libXdamage libxkbcommon mesa-libgbm alsa-lib pango gtk3"
if [ "$OS_TYPE" = "fedora" ]; then
  # Additional Fedora-specific packages
  install_packages $BROWSER_DEPS google-noto-emoji-color-fonts
elif [ "$OS_TYPE" = "amazon_linux" ]; then
  # Amazon Linux may not have google-noto-emoji-color-fonts
  install_packages $BROWSER_DEPS
  # Try to install it anyway, but ignore failure
  sudo dnf install -y google-noto-emoji-color-fonts || echo "Package google-noto-emoji-color-fonts not available, continuing..."
else
  # Default case for unknown systems
  install_packages $BROWSER_DEPS
fi

# Install X11/VNC tools
echo_status "Installing X11/VNC tools"
X11_DEPS="xorg-x11-server-Xvfb tigervnc-server websockify"
if [ "$OS_TYPE" = "fedora" ]; then
  # Full set of packages for Fedora
  install_packages $X11_DEPS novnc
elif [ "$OS_TYPE" = "amazon_linux" ]; then
  # Amazon Linux may not have novnc package
  install_packages $X11_DEPS
  # Install novnc from pip if package is missing
    sudo dnf install -y novnc || {
      echo "novnc package not available via dnf, installing via pip..."
      python -m pip install novnc || echo "Failed to install novnc via pip, continuing..."
    }
else
  # Default case
  install_packages $X11_DEPS
fi

# Install window manager
echo_status "Installing window manager and supporting tools"
WM_DEPS="feh xterm"
if [ "$OS_TYPE" = "fedora" ]; then
  # Fedora has bspwm in standard repositories
  install_packages $WM_DEPS bspwm
elif [ "$OS_TYPE" = "amazon_linux" ]; then
  # Try standard installation first
  if sudo dnf install -y bspwm; then
    install_packages $WM_DEPS
  else
    # If bspwm isn't available, try to install a minimal alternative like i3
    echo "bspwm not found, trying alternative window manager (i3)..."
    sudo dnf install -y i3 || echo "No alternative window manager found. GUI functionality may be limited."
    install_packages $WM_DEPS
  fi
else
  # Default case
  install_packages $WM_DEPS
fi

# Install test dependencies
echo_status "Installing test dependencies"
TEST_DEPS="ffmpeg xclip"
if [ "$OS_TYPE" = "fedora" ]; then
  # Fedora-specific packages
  install_packages $TEST_DEPS python3-qt5
elif [ "$OS_TYPE" = "amazon_linux" ]; then
  # Amazon Linux may not have python3-qt5
    install_packages $TEST_DEPS
    sudo dnf install -y python3-qt5 || {
      echo "python3-qt5 not available via dnf, installing via pip..."
      python -m pip install PyQt5 || echo "Failed to install PyQt5 via pip, continuing..."
    }
else
  # Default case
  install_packages $TEST_DEPS
fi

# Install NGINX
echo_status "Installing NGINX"
install_packages nginx

# Configure nginx for Pusher
echo_status "Configuring NGINX for Pusher"
sudo mkdir -p /etc/nginx/ssl
sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/pusher.key \
  -out /etc/nginx/ssl/pusher.crt \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=ws-mt1.pusher.com" \
  -batch

# Install Ruby and pusher-fake
echo_status "Installing Ruby and pusher-fake"

# Install Ruby using DNF
install_packages ruby ruby-devel rubygem-bundler rubygems-devel gcc-c++ make

# Check Ruby version
ruby --version

# Install pusher gems with the correct version
echo_status "Installing pusher gems"
sudo gem install pusher:2.0.3 pusher-fake:6.0.0 || {
  echo "Error installing pusher gems, trying with alternative approach"

  # Alternative approach - create a Gemfile and use bundler
  cat > Gemfile <<EOF
source 'https://rubygems.org'
gem 'pusher', '2.0.3'
gem 'pusher-fake', '6.0.0'
EOF

  # Install gems using bundler
  bundle install
}

# Verify pusher-fake installation
echo_status "Verifying pusher-fake installation"
if ! command -v pusher-fake &>/dev/null; then
  echo "pusher-fake executable not found, checking gem installation"
  gem list | grep pusher
  echo "Note: You may need to run pusher-fake using 'bundle exec pusher-fake' instead"
fi

# Clone the Expensify App repository
echo_status "Cloning Expensify App repository"
if [ ! -d "/app/expensify" ]; then
  git clone https://github.com/Expensify/App.git /app/expensify --single-branch || echo "Failed to clone Expensify, continuing..."
else
  echo "Expensify repository already exists at /app/expensify"
fi

# Install NVM (as in Dockerfile)
echo_status "Installing NVM"
if [ ! -d "$NVM_DIR" ]; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
fi

# Install Python requirements (use Python 3.12 specifically)
echo_status "Installing Python requirements with Python 3.12"

# Use requirements.txt from the repo if available
if [ -f "SWELancer-Benchmark/requirements.txt" ]; then
  cp SWELancer-Benchmark/requirements.txt .
else
  cat > requirements.txt <<EOF
pytest>=7.0.0
playwright>=1.28.0
mitmproxy>=9.0.0
aiohttp>=3.8.0
asyncio>=3.4.3
ansible>=2.12.0
libcst>=1.0.0
EOF
fi

# Install requirements with Python from the virtual environment
python -m pip install --no-cache-dir -r requirements.txt

# Set up Playwright with Python from the virtual environment
echo_status "Setting up Playwright with Python 3.12 (venv)"
python -m playwright install || echo "Failed to install Playwright browsers, continuing..."
python -m playwright install-deps || echo "Failed to install Playwright dependencies, continuing..."

# Configure bspwm
echo_status "Configuring bspwm"
mkdir -p $HOME/.config/bspwm
cat > $HOME/.config/bspwm/bspwmrc <<EOF
#!/bin/bash
bspc monitor -d 1 2 3 4
bspc config automatic_scheme spiral
bspc config border_width 2
bspc config window_gap 8
EOF
chmod +x $HOME/.config/bspwm/bspwmrc

# Copy runtime scripts to the app directory, mirroring the COPY instructions in Dockerfile
echo_status "Copying scripts to the appropriate locations"

# Copy files from the SWELancer-Benchmark repo
if [ -d "SWELancer-Benchmark/issues" ]; then
  echo "Copying issues directory..."
  cp -r SWELancer-Benchmark/issues/ /app/tests/
fi

if [ -d "SWELancer-Benchmark/utils" ]; then
  echo "Copying utils directory..."
  cp -r SWELancer-Benchmark/utils/ /app/tests/
fi

if [ -d "SWELancer-Benchmark/runtime_scripts" ]; then
  echo "Copying runtime scripts..."
  # Copy runtime scripts exactly as in the Dockerfile
  cp SWELancer-Benchmark/runtime_scripts/setup_expensify.yml /app/tests/ 2>/dev/null || echo "setup_expensify.yml not found"
  cp SWELancer-Benchmark/runtime_scripts/setup_mitmproxy.yml /app/tests/ 2>/dev/null || echo "setup_mitmproxy.yml not found"
  cp SWELancer-Benchmark/runtime_scripts/run_test.yml /app/tests/ 2>/dev/null || echo "run_test.yml not found"
  cp SWELancer-Benchmark/runtime_scripts/run_fixed_state.yml /app/tests/ 2>/dev/null || echo "run_fixed_state.yml not found"
  cp SWELancer-Benchmark/runtime_scripts/run_user_tool.yml /app/tests/ 2>/dev/null || echo "run_user_tool.yml not found"
  cp SWELancer-Benchmark/runtime_scripts/run_broken_state.yml /app/tests/ 2>/dev/null || echo "run_broken_state.yml not found"
  cp SWELancer-Benchmark/runtime_scripts/setup_eval.yml /app/tests/ 2>/dev/null || echo "setup_eval.yml not found"
  cp SWELancer-Benchmark/runtime_scripts/run.sh /app/tests/ 2>/dev/null || echo "run.sh not found"
  cp SWELancer-Benchmark/runtime_scripts/replay.py /app/tests/ 2>/dev/null || echo "replay.py not found"
  cp SWELancer-Benchmark/runtime_scripts/rewrite_test.py /app/tests/ 2>/dev/null || echo "rewrite_test.py not found"

  # Match the npm_fix.py destination
  cp SWELancer-Benchmark/runtime_scripts/npm_fix.py /app/expensify/ 2>/dev/null || echo "npm_fix.py not found"

  # Apply npm_fix.py file to remove integrity checks
  echo_status "Applying npm_fix.py file to remove integrity checks"
  python /app/expensify/npm_fix.py 2>/dev/null || echo "Failed to apply npm_fix.py, continuing..."

  # Make run.sh executable, just like in Dockerfile
  chmod +x /app/tests/run.sh 2>/dev/null || echo "Could not make run.sh executable"
  chmod +x /app/tests/replay.py 2>/dev/null || echo "Could not make replay.py executable"
  chmod +x /app/tests/rewrite_test.py 2>/dev/null || echo "Could not make rewrite_test.py executable"
fi

# Copy nginx configuration if available
if [ -f "SWELancer-Benchmark/runtime_scripts/pusher_nginx.conf" ]; then
  sudo cp SWELancer-Benchmark/runtime_scripts/pusher_nginx.conf /etc/nginx/nginx.conf
fi

# Add host entries for Pusher/Expensify
echo_status "Configuring host entries"
if ! grep -q "ws-mt1.pusher.com" /etc/hosts; then
  echo "127.0.0.1 ws-mt1.pusher.com" | sudo tee -a /etc/hosts
fi

if ! grep -q "dev.new.expensify.com" /etc/hosts; then
  echo "127.0.0.1 dev.new.expensify.com" | sudo tee -a /etc/hosts
fi

# Fix bcrypt compatibility issues with passlib
echo_status "Setting up bcrypt compatibility fix for mitmproxy"
# Ensure bcrypt is installed
python -m pip install bcrypt

# Create bcrypt patch script that adds the missing __about__ attribute
cat > /tmp/bcrypt_patch.py <<'EOF'
import sys
try:
    import bcrypt
    if not hasattr(bcrypt, '__about__'):
        print("Adding '__about__' attribute to bcrypt for passlib compatibility")
        # Create a mock __about__ object
        bcrypt.__about__ = type('', (), {})()
        bcrypt.__about__.__version__ = bcrypt.__version__
        print(f"Patched bcrypt {bcrypt.__version__} for compatibility with passlib")
    else:
        print(f"bcrypt {bcrypt.__version__} already has '__about__' attribute")
except ImportError:
    print("bcrypt is not installed. Installing...")
    sys.exit(1)
EOF

# Run the patch to fix bcrypt
python /tmp/bcrypt_patch.py || {
  echo "Error running bcrypt patch, installing bcrypt and trying again"
  python -m pip install --upgrade bcrypt
  python /tmp/bcrypt_patch.py
}

# Create a patch for the virtual environment
# This patch will automatically fix the __about__ attribute whenever bcrypt is imported
SITE_PACKAGES_DIR=$(python -c "import site; print(site.getsitepackages()[0])")
mkdir -p "$SITE_PACKAGES_DIR"
cat > /tmp/bcrypt_patch.pth <<'EOF'
import sys
try:
    import bcrypt
    if not hasattr(bcrypt, '__about__'):
        bcrypt.__about__ = type('', (), {})()
        bcrypt.__about__.__version__ = bcrypt.__version__
except (ImportError, AttributeError):
    pass
EOF
cp /tmp/bcrypt_patch.pth "$SITE_PACKAGES_DIR/"

# Add Ansible tasks example for using NVM correctly with $HOME/.nvm
cat > /app/tests/nvm_tasks_example.yml <<'EOF'
---
- name: NVM Tasks Example
  hosts: localhost
  connection: local
  tasks:
    - name: Use nvm to install specific Node.js version (using '.nvmrc')
      shell: |
        source $HOME/.nvm/nvm.sh
        nvm install
      args:
        chdir: /app/expensify
        executable: /bin/bash

    - name: Use npm version to set git tag if it exists
      shell: |
        source $HOME/.nvm/nvm.sh
        npm version {{ git_tag.stdout }} --no-git-tag-version
      args:
        chdir: /app/expensify
        executable: /bin/bash
      when: git_tag.stdout != ''
EOF

# Set up mitmproxy certificates
echo_status "Setting up mitmproxy certificates"

# Install mitmproxy in the virtual environment
python -m pip install --upgrade mitmproxy

# Make sure the virtual environment's bin directory is in PATH
# No need for symlinks since we're using the virtual environment

# Verify mitmproxy is now accessible
if ! command -v mitmdump &>/dev/null; then
  echo "ERROR: mitmdump not found in PATH after installation"
  exit 1
fi

# Clean up existing mitmproxy certificates to avoid conflicts
echo_status "Cleaning up existing certificates to avoid conflicts"
rm -rf $HOME/.mitmproxy/* 2>/dev/null || true

# Create mitmproxy directory with correct permissions in user space
mkdir -p $HOME/.mitmproxy
chmod 700 $HOME/.mitmproxy

# Generate new mitmproxy certificates using explicit timeout approach
echo_status "Generating new mitmproxy certificates"
# Run mitmdump to generate certificates in user's home directory
timeout 15 mitmdump --set confdir=$HOME/.mitmproxy --no-http2 -p 8080 || echo "Timeout reached (expected)"

# Verify certificates were created
if [ ! -f "$HOME/.mitmproxy/mitmproxy-ca-cert.pem" ]; then
  echo "ERROR: Failed to generate mitmproxy certificates. The Ansible playbook will fail."
  exit 1
else
  echo "Successfully generated mitmproxy certificates"
  ls -la $HOME/.mitmproxy/  # Show the generated files
fi

# Set up NSS database for browser certificates in user space
echo_status "Setting up NSS database for browser certificates"
# Remove any existing NSS database to avoid conflicts
rm -rf $HOME/.pki/nssdb/ 2>/dev/null || true
mkdir -p $HOME/.pki/nssdb/
chmod 700 $HOME/.pki/nssdb/

# Initialize a fresh NSS database with non-interactive empty password
echo "Initializing fresh NSS database..."
certutil -N -d sql:$HOME/.pki/nssdb --empty-password

# Install certificate in system trust store and NSS database
echo_status "Installing mitmproxy certificates in system trust stores"

# System trust store for Fedora/RHEL systems (still needs sudo)
sudo mkdir -p /etc/pki/ca-trust/source/anchors/
sudo cp $HOME/.mitmproxy/mitmproxy-ca-cert.pem /etc/pki/ca-trust/source/anchors/mitmproxy-ca-cert.crt
sudo update-ca-trust extract

# Browser certificates using user's NSS database - non-interactive with empty password
echo "Adding certificate to user's NSS database..."
certutil -A -d sql:$HOME/.pki/nssdb -t "C,," -n "mitmproxy-ca-cert" -i $HOME/.mitmproxy/mitmproxy-ca-cert.pem -a

# Verify certificate was added correctly
certutil -L -d sql:$HOME/.pki/nssdb | grep "mitmproxy-ca-cert" || \
  echo "WARNING: Certificate may not have been added to NSS database correctly"

echo "Mitmproxy certificate setup complete"

# Set python3.12 as default python by creating an alias
echo_status "Setting Python 3.12 as default"
sudo alternatives --install /usr/bin/python python /usr/bin/python3.12 1 || echo "Failed to set Python 3.12 as default with alternatives"
sudo alternatives --set python /usr/bin/python3.12 || echo "Failed to set Python as python3.12"

# Create a symlink as a backup method if alternatives fails
if [ ! -L /usr/local/bin/python ]; then
  sudo ln -sf /usr/bin/python3.12 /usr/local/bin/python || echo "Failed to create Python symlink"
fi

# Ensure pip points to pip3.12
if [ ! -L /usr/local/bin/pip ]; then
  sudo ln -sf /usr/bin/pip3.12 /usr/local/bin/pip || echo "Failed to create pip symlink"
fi

# Create an Ansible configuration file to use the venv's Python interpreter
echo_status "Configuring Ansible to use the virtual environment's Python"
mkdir -p /app/tests/.ansible
cat > /app/tests/ansible.cfg <<EOF
[defaults]
interpreter_python = $VENV_DIR/bin/python
EOF

# Create the user-tool alias to match run.sh
echo_status "Creating user-tool alias"
if ! grep -q "alias user-tool" $HOME/.bashrc; then
  echo "alias user-tool='source $VENV_DIR/bin/activate && python -m ansible.cli.playbook -i \"localhost,\" --connection=local /app/tests/run_user_tool.yml'" >> $HOME/.bashrc
fi

echo_status "Setup completed successfully"
echo ""
echo "Directory structure has been set up at /app/"
echo "Python 3.12 virtual environment is set up at $VENV_DIR"
echo "Ruby and pusher-fake have been installed"
echo ""
echo "To run the environment (like in the Docker container), execute:"
echo ""
echo "# 1. Start Xvfb"
echo "Xvfb :99 -screen 0 2560x1600x24 > /dev/null 2>&1 &"
echo "export DISPLAY=:99"
echo ""
echo "# 2. Start bspwm window manager"
echo "bspwm > /dev/null 2>&1 &"
echo ""
echo "# 3. Start x11vnc"
echo "x11vnc -display :99 -forever -rfbport 5900 -noxdamage > /dev/null 2>&1 &"
echo ""
echo "# 4. Start NoVNC"
echo "websockify --web=/usr/share/novnc/ 5901 localhost:5900 > /dev/null 2>&1 &"
echo ""
echo "# 5. Start NGINX"
echo "sudo nginx -g \"daemon off;\" > /dev/null 2>&1 &"
echo ""
echo "# 6. Start pusher-fake"
echo "pusher-fake > /dev/null 2>&1 & || bundle exec pusher-fake > /dev/null 2>&1 &"
echo ""
echo "# 7. Activate the Python virtual environment"
echo "source $VENV_DIR/bin/activate"
echo ""
echo "# 8. Run the Ansible playbooks (with timing)"
echo "cd /app/tests"
echo "echo 'Running setup_expensify.yml...'; time python -m ansible.cli.playbook -i \"localhost,\" --connection=local setup_expensify.yml"
echo "echo 'Running setup_mitmproxy.yml...'; time python -m ansible.cli.playbook -i \"localhost,\" --connection=local setup_mitmproxy.yml"
echo ""
echo "# Example command to copy-paste and run both playbooks:"
echo "cd /app/tests && echo 'Running setup_expensify.yml...' && time python -m ansible.cli.playbook -i \"localhost,\" --connection=local setup_expensify.yml && echo 'Running setup_mitmproxy.yml...' && time python -m ansible.cli.playbook -i \"localhost,\" --connection=local setup_mitmproxy.yml"
echo ""
echo "Reminder: All Python commands use Python 3.12 from the virtual environment"
echo "Reminder: The Ansible playbooks should be run from /app/tests"

# Run the Ansible playbooks
echo_status "Running Ansible playbooks"
cd /app/tests

# Activate virtual environment
source "$VENV_DIR/bin/activate"

echo -e "\033[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "\033[1;33mRunning setup_expensify.yml\033[0m"
echo -e "\033[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
EXPENSIFY_START=$(date +%s)
python -m ansible.cli.playbook -i "localhost," --connection=local /app/tests/setup_expensify.yml || {
  echo -e "\033[1;31mError running setup_expensify.yml playbook\033[0m"
}
EXPENSIFY_END=$(date +%s)
EXPENSIFY_TIME=$((EXPENSIFY_END - EXPENSIFY_START))
echo -e "\033[1;32mCompleted setup_expensify.yml in ${EXPENSIFY_TIME} seconds\033[0m"

echo -e "\033[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "\033[1;33mRunning setup_mitmproxy.yml\033[0m"
echo -e "\033[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
MITMPROXY_START=$(date +%s)
python -m ansible.cli.playbook -i "localhost," --connection=local /app/tests/setup_mitmproxy.yml || {
  echo -e "\033[1;31mError running setup_mitmproxy.yml playbook\033[0m"
}
MITMPROXY_END=$(date +%s)
MITMPROXY_TIME=$((MITMPROXY_END - MITMPROXY_START))
echo -e "\033[1;32mCompleted setup_mitmproxy.yml in ${MITMPROXY_TIME} seconds\033[0m"

# Deactivate virtual environment
deactivate

cd - > /dev/null # Return to previous directory

echo ""
echo "Environment is now fully set up and configured with Python virtual environment."
echo "To run tests, activate the virtual environment and use Python directly:"
echo "source $VENV_DIR/bin/activate && cd /app/tests && python -m ansible.cli.playbook -i \"localhost,\" --connection=local run_user_tool.yml"
echo ""
echo "Alternatively, you can use the user-tool alias that was added to your .bashrc"
echo ""

# Calculate and display execution time
ELAPSED_TIME=$((SECONDS - START_TIME))
HOURS=$((ELAPSED_TIME / 3600))
MINUTES=$(((ELAPSED_TIME % 3600) / 60))
SECONDS=$((ELAPSED_TIME % 60))

echo ""
echo -e "\033[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "\033[1;33mTotal setup time: \033[1;36m${HOURS}h ${MINUTES}m ${SECONDS}s\033[0m"
echo -e "\033[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"

exit 0