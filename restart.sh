#!/bin/bash
# update
sudo apt update && sudo apt upgrade -y

# add spotify-client repository
curl -sS https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.asc | sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
echo "deb https://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list

# uv
curl -LsSf https://astral.sh/uv/install.sh | sh

# proton vpn
wget https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb
sudo dpkg -i ./protonvpn-stable-release_1.0.8_all.deb && sudo apt update

# signal
wget -O- https://updates.signal.org/desktop/apt/keys.asc | gpg --dearmor > signal-desktop-keyring.gpg;
cat signal-desktop-keyring.gpg | sudo tee /usr/share/keyrings/signal-desktop-keyring.gpg > /dev/null
wget -O signal-desktop.sources https://updates.signal.org/static/desktop/apt/signal-desktop.sources;
cat signal-desktop.sources | sudo tee /etc/apt/sources.list.d/signal-desktop.sources > /dev/null

# apt
sudo apt install code git-all jekyll mpv proton-vpn-gnome-desktop qbittorrent ruby ruby-dev signal-desktop steam

# refind (for pop os dual booting)
#sudo apt-add-repository ppa:rodsmith/refind
#sudo apt-get install refind

# update aliases
echo "#update aliases" >> ~/.bashrc
echo "alias up='sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y && flatpak update -y && uv self update'" >> ~/.bashrc
echo "alias updown='up && sudo shutdown'" >> ~/.bashrc
echo "alias upstart='up && sudo reboot'" >> ~/.bashrc

# flatpaks
sudo flatpak install flathub com.discordapp.Discord md.obsidian.Obsidian org.kde.krita com.github.johnfactotum.Foliate com.getpostman.Postman org.gnome.World.PikaBackup -y

# mounting my drives
fixntfs() {
    sudo ntfsfix "/dev/$1" && \
    sudo mount -t ntfs "/dev/$1" /media/sam
}

# camera stuff for Dell XPS 9315
sudo apt install v4l-utils libcamera-tools libcamera0.2 gstreamer1.0-libcamera pipewire-libcamera cheese
