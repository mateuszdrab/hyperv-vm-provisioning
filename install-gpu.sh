#!/bin/bash
set -ex

echo "Moving files and setting permissions..."
rm -rf /usr/lib/wsl
mv ~/wsl /usr/lib/wsl
chmod -R 555 /usr/lib/wsl/drivers/
chmod -R 755 /usr/lib/wsl/lib/
chown -R root:root /usr/lib/wsl
sed -i '/^PATH=/ {/usr\/lib\/wsl\/lib/! s|"$|:/usr/lib/wsl/lib"|}' /etc/environment
ln -s /usr/lib/wsl/lib/libd3d12core.so /usr/lib/wsl/lib/libD3D12Core.so
ln -s /usr/lib/wsl/lib/libnvoptix.so.1 /usr/lib/wsl/lib/libnvoptix_loader.so.1

echo "Updating ldconfig..."
sh -c 'echo "/usr/lib/wsl/lib" > /etc/ld.so.conf.d/ld.wsl.conf'
ldconfig

echo "Generating MOK key..."
update-secureboot-policy --new-key

echo "Compiling dxgkrnl-dkms..."
curl -fsSL https://content.staralt.dev/dxgkrnl-dkms/main/install.sh | sudo bash -esx

echo "Enrolling MOK key... password is 'ubuntugpu'"
echo "ubuntugpu" | update-secureboot-policy --enroll-key

# if --install-docker flag is set, then install Docker and NVIDIA Container Toolkit
if [ "$1" == "--install-docker" ]; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh

    echo "Installing NVIDIA Container Toolkit..."
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg &&
        curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' |
            tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    apt-get update
    apt-get install -y nvidia-container-toolkit

    echo "Configuring Docker for NVIDIA Container Toolkit..."
    nvidia-ctk runtime configure --runtime=docker
fi

echo "Rebooting in 10 seconds..."
sleep 10 && reboot
