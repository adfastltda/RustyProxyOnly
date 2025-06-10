# Use a supported Ubuntu version as a base image (e.g., Ubuntu 22.04)
FROM debian:11

# Set DEBIAN_FRONTEND to noninteractive to avoid prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Update package lists and install essential packages for the script's initial steps.
# - sudo: The install.sh script uses 'sudo bash' for speedtest installation.
# - git: The install.sh script uses git to clone a repository early on.
# - curl: The install.sh script uses curl to download Rust installer and other scripts.
# - ca-certificates: Often needed for HTTPS connections with curl/git.
# - procps: Provides 'nproc', used by 'cargo build --jobs "$(nproc)"' in the script
#           before the script's own 'apt install' for procps.
# The script itself will install many more packages.
RUN apt-get update && \
    apt-get install -y sudo git curl ca-certificates procps lsb-release && \
    rm -rf /var/lib/apt/lists/*

# Set the working directory in the container
WORKDIR /app

# Copy the entire project context (which includes install.sh and other project files)
# from the host to /app in the container.
COPY . /app/

# Make the install script executable
RUN chmod +x /app/install.sh

# Execute the installation script when the container starts.
# The script will run as root by default.
# Logs from the script will be sent to stdout/stderr and also to /var/log/rustyproxy_install.log inside the container.
# Note: The 'reboot' command at the end of install.sh will cause the container to stop.
CMD ["/bin/bash", "/app/install.sh"]