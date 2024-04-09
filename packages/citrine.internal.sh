#!/bin/bash

inf() {
    echo -e "\e[1m♠ $@\e[0m"
}

err() {
    echo -e "\e[1m\e[31m✗ $@\e[0m"
}

yn=""
yesno() {
    printf "\e[1m\e[33m$@ : \e[0m"
    read yn
}

# ---------------------------------
yn=""
yesno() {
    dialog --title Citrine --yesno "$@" 10 80
    yn=$?
}

dumptitle=""
dump() {
    dialog --title "${dumptitle}" --no-collapse --msgbox "$@" 0 0
}

msgdat=""
msgbox(){
    msgdat=$(dialog --title Citrine --inputbox "$@" --stdout 10 80)
}

pass=""
passbox(){
    pass=$(dialog --title Citrine --insecure --passwordbox "$@" --stdout 10 80)
}
# --------------------------

if [[ "$EUID" != "0" ]]; then
    err "Run as root"
    exit 1
fi

inf "Checking pacman keyrings"
pacman-key --init
pacman-key --populate archlinux
#pacman-key --populate crystal

yesno "Do you need a keyboard layout other than QWERTY US?"
KBD="$yn"
echo "KBD=$KBD"

if [[ "$KBD" == "0" ]]; then
    keymaps=$(localectl list-keymaps | tr '\n' ' ' | sed 's/ /" "" "/g')
    keymap=$(dialog --title "Citrine" --menu "Select your keyboard layout" 10 80 0 $keymaps "" --stdout)

fi

clear

yesno "Would you like to partition manually?"
echo "PMODE=$yn"
PMODE="$yn"

if [[ "$PMODE" == "0" ]]; then
    MANUAL="yes"
fi

DONE="no"

while [[ "$DONE" == "no" ]]; do
    dumptitle="System Disks"
    diskdat="$(fdisk -l | grep Disk | grep sectors --color=never | grep -v loop)"
    dump "$diskdat"

    MANUAL="no"
    DISK=""
    msgbox "Install target WILL BE FULLY WIPED"
    echo "DISK=$msgdat"
    DISK="$msgdat"
    if fdisk -l ${DISK}; then
        DONE="yes"
    else
        dumptitle="Error"
        dump "${DISK} doesn't seem to be a valid disk."
    fi
done



if [[ $DISK == *"nvme"* ]]; then
    inf "Seems like this is an NVME disk. Noting"
    NVME="yes"
else
    NVME="no"
fi
echo "NVME=$NVME"

if [[ -d /sys/firmware/efi/efivars ]]; then
    inf "Seems like this machine was booted with EFI. Noting"
    EFI="yes"
else
    EFI="no"
fi
echo "EFI=$EFI"

dumptitle="Please confirm"
if [[ "$EFI" == "yes" ]]; then
    dump "This PC seems to *have* booted with UEFI. Press enter to confirm, or Control+C to cancel"
else
    dump "This PC seems to *not* have booted with UEFI. Press enter to aknowledge, or press Control+C if this seems wrong."
fi

inf "Setting system clock via network"
timedatectl set-ntp true

if [[ "$MANUAL" == "no" ]]; then

    dumptitle="CAUTION!"
    dump "This is your last chance to avoid deleting critical data on $DISK. If you're not sure, press Control+C NOW!"

    echo "Partitioning disk"
    if [[ "$EFI" == "yes" ]]; then
        parted ${DISK} 'mklabel gpt' --script
        parted ${DISK} 'mkpart primary fat32 0 300' --script
        parted ${DISK} 'mkpart primary ext4 300 100%' --script
        inf "Partitioned ${DISK} as an EFI volume"
    else
        parted ${DISK} 'mklabel msdos' --script
        parted ${DISK} 'mkpart primary ext4 1 -1' --script
        inf "Partitioned ${DISK} as an MBR volume"
    fi

    if [[ "$NVME" == "yes" ]]; then
        if [[ "$EFI" == "yes" ]]; then
            inf "Initializing ${DISK} as NVME EFI"
            mkfs.vfat -F32 ${DISK}p1
            mkfs.ext4 ${DISK}p2
            mount ${DISK}p2 /mnt
            mkdir -p /mnt/boot/efi
            mount ${DISK}p1 /mnt/boot/efi
        else
            inf "Initializing ${DISK} as NVME MBR"
            mkfs.ext4 ${DISK}p1
            mount ${DISK}1 /mnt
        fi
    else
        if [[ "$EFI" == "yes" ]]; then
            inf "Initializing ${DISK} as EFI"
            mkfs.vfat -F32 ${DISK}1
            mkfs.ext4 ${DISK}2
            mount ${DISK}2 /mnt
            mkdir -p /mnt/boot/efi
            mount ${DISK}1 /mnt/boot/efi
        else
            inf "Initializing ${DISK} as MBR"
            mkfs.ext4 ${DISK}1
            mount ${DISK}1 /mnt
        fi
    fi
else
    clear

    dumptitle="Read carefully!"

    dump "You have chosen manual partitioning.\
    We're going to drop to a shell for you to partition, but first, PLEASE READ these notes.\
    Before you exit the shell, make sure to format and mount a partition for / at /mnt."

    if [[ "$EFI" == "yes" ]]; then
        mkdir -p /mnt/boot/efi

        dump "Additionally, since this machine was booted with UEFI, please make sure to make a 200MB or greater partition\
        of type VFAT and mount it at /mnt/boot/efi"
    else
        msgbox "Please give me the full path of the device you're planning to partition (needed for bootloader installation later)\
        .. Example: /dev/sda"
        DISK="${msgdat}"
    fi

    dumptitle="Suggestion"
    dump "You could also use the graphical 'Disks' application. This will take care of everything except mounting, which you will\
    still need to do within the shell."

    CONFDONE="NOPE"
    dumptitle="Citrine"

    while [[ "$CONFDONE" == "NOPE" ]]; do
        dump "Press enter to go to a shell. (ZSH)"
        zsh
        yesno "All set (and partitions mounted?)"
        echo "STAT=$yn"
        STAT="$yn"
        if [[ "$STAT" == "0" ]]; then

            if ! findmnt | grep /mnt; then
                err "Are you sure you've mounted the partitions?"
            else
                CONFDONE="YEP"
            fi
        fi
    done
fi

if ! findmnt | grep /mnt; then
    err "Seems like no partitions are mounted."
    exit 1
fi

inf "Verifying network connection"
ping -c 1 google.com

if [[ ! "$?" == "0" ]]; then
    dumptitle="Error!"
    dump "It seems like this system can't reach the internet. Failing here."
    umount -l /mnt
    exit 1
fi

inf "Setting up base Arch System"

pacstrap /mnt base base-devel linux-zen linux-firmware linux-zen-headers networkmanager man-db man-pages texinfo micro neovim vim nix flatpak sudo kitty curl archlinux-keyring neofetch which hyprland sddm
if [[ ! "$?" == "0" ]]; then
    inf "pacstrap had some error. Retrying."
    pacstrap /mnt base base-devel linux-zen linux-firmware linux-zen-headers networkmanager man-db man-pages texinfo micro neovim nix flatpak sudo curl archlinux-keyring neofetch which
fi

if [[ "$EFI" == "yes" ]]; then
    inf "Installing EFI support packages"
    pacstrap /mnt efibootmgr grub
else 
    inf "Installing Syslinux bootloader"
    pacstrap /mnt grub
fi

genfstab -U /mnt > /mnt/etc/fstab

clear

cd /
wget https://geoip.kde.org/v1/calamares
cat >> extract.py << EOF
import json
with open("calamares") as f:
    s = f.read()
foo = json.loads(s)
with open("out","w") as f:
    f.write(foo['time_zone'])
EOF
python extract.py
rm extract.py
rm calamares
DAT=$(cat out)
rm out
TZ="/usr/share/zoneinfo/${DAT}"

if [[ ! -f $TZ ]]; then
    cd /usr/share/zoneinfo/
    var=$(echo */ | sed 's/\///g' | sed 's/ /" "" "/g')
    var=$(echo \"$var\")
    loc1=$(dialog --title "Citrine" --menu "Please pick a time zone" 20 100 43 $var "" --stdout)
    loc1=$(echo $loc1 | sed 's/"//g')
    cd /usr/share/zoneinfo/$loc1
    var1=$(echo * | sed 's/\///g' | sed 's/ /" "" "/g')
    var1=$(echo \"$var1\")
    loc2=$(dialog --title "Citrine" --menu "Please pick a time zone" 20 100 43 $var1 "" --stdout)
    loc2=$(echo $loc1 | sed 's/"//g')
    TZ="/usr/share/zoneinfo/$loc1/$loc2"
    cd /

    arch-chroot /mnt ln -sf $TZ /etc/localtime
    inf "Set TZ to ${TZ}"
    inf "Syncing hardware offset"
    arch-chroot /mnt hwclock --systohc
else
    ln -sf $TZ /etc/localtime
    ntpd -g -q
    arch-chroot /mnt ln -sf $TZ /etc/localtime
    inf "Set TZ to ${TZ}"
    inf "Syncing hardware offset"
    arch-chroot /mnt hwclock --systohc
fi

echo "en_US.UTF-8 UTF-8" >> /mnt/etc/locale.gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

clear
yesno "Do you need more locales than just en_US?"
echo "More=$yn"
More="$yn"

if [[ "$MORE" == "0" ]]; then
    msgbox "Preferred editor"
    dumptitle="Read carefully."
    dump "When we open the file, please remove the leading # before any locales you need.\
    Then, save and exit."
    nano /mnt/etc/locale.gen
fi

inf "Generating selected locales."
arch-chroot /mnt locale-gen

echo
echo
dumptitle="locale"
dump "en_US was set as system primary.\nAfter install, you can edit /etc/locale.conf to change the primary if desired."

if [[ "$KBD" == "y" || "$KBD" == "Y" ]]; then
    echo "KEYMAP=${KMP}" > /mnt/etc/vconsole.conf
fi

clear
msgbox "Enter the system hostname"
HOSTNAME="$msgdat"
echo ${HOSTNAME} > /mnt/etc/hostname
echo "127.0.0.1     localhost" > /mnt/etc/hosts

yesno "Would you like IPV6?"
IPS="$yn"

if [[ "$IPS" == "0" ]]; then
    echo "::1       localhost" >> /mnt/etc/hosts
fi
echo "127.0.0.1     ${HOSTNAME}.localdomain ${HOSTNAME}" >> /mnt/etc/hosts

clear

arch-chroot /mnt systemctl enable NetworkManager
arch-chroot /mnt pacman-key --init
arch-chroot /mnt pacman-key --populate archlinux
#arch-chroot /mnt pacman-key --populate crystal

clear

mkdir -p /mnt/etc/
cp -v /etc/pacman.conf /mnt/etc/pacman.conf

arch-chroot /mnt pacman -Syyu hyprland sddm sddm-config-editor-git archlinux-tweak-tool-git fish --quiet --noconfirm

#while [[ "$DE" == "" ]]; do
#    if [[ ! -f /etc/fig ]]; then
#        menu=$(dialog --title "Citrine" --menu "Would you like to theme Hyprland?" 12 100 4 "Yes" "Our pre-themed desktop environments" "Third Party (supported)" "Third party Desktop Environments that are supported" "Third Party (unsupported)" "Third Party Desktop Environments that aren't supported" "None/DIY" "Install no de from this list" --stdout)
#        if [[ "$menu" == "Official" ]]; then
#            DE=$(dialog --title "Citrine" --menu "Please choose the DE you want to install" 12 100 1 "Onyx" "Our custom Desktop Environment based on Budgie" --stdout)
#        elif [[ "$menu" == "Third Party (supported)" ]]; then
#            DE=$(dialog --title "Citrine" --menu "Please choose the DE you want to install" 12 100 5 "Gnome" "The Gnome desktop environment" "KDE" "The KDE desktop environment" "Xfce" "The xfce desktop environment" "budgie" "The budgie desktop environment" "Mate" "The Mate desktop environment" --stdout)
#        elif [[ "$menu" == "Third Party (unsupported)" ]]; then
#            DE=$(dialog --title "Citrine" --menu "Please choose the DE you want to install" 12 100 1 "Enlightenment" "A very DIY desktop environment, refer to archwiki" --stdout)
#        elif [[ "$menu" == "None/DIY" ]]; then
#            yesno "Are you sure that you dont want to install any DE?"
#            if [[ "$yn" == "0" ]]; then
#                DE="none"
#                DM="none"
#            else
#                DE=""
#            fi
#        fi
#    else
#        DE="Fig"
#    fi
#    if [[ "$DE" == "Onyx" ]]; then
#        arch-chroot /mnt pacman -S --quiet --noconfirm onyx xorg-server budgie-desktop gnome
#
#        mkdir -p /mnt/etc/skel/
#        echo "gsettings set org.gnome.desktop.interface gtk-theme \"crystal-obsidian\"" >> /mnt/etc/skel/.xsession
#        echo "gsettings set org.gnome.desktop.interface icon-theme \"crystal-obsidian-icons\"" >> /mnt/etc/skel/.xsession
#
#        DM="lightdm"
#    elif [[ "$DE" == "Gnome" ]]; then
#        arch-chroot /mnt pacman -S --quiet --noconfirm gnome gnome-extra chrome-gnome-shell
#        DM="gdm"
#    elif [[ "$DE" == "KDE" || "$DE" == "Fig" ]]; then
#        arch-chroot /mnt pacman -S --quiet --noconfirm plasma kde-system kde-utilities sddm
#        DM="sddm"
#    elif [[ "$DE" == "budgie" ]]; then
#        arch-chroot /mnt pacman -S --quiet --noconfirm budgie-desktop gnome
#        DM="lightdm"
#    elif [[ "$DE" == "Mate" ]]; then
#        arch-chroot /mnt pacman -S --quiet --noconfirm mate mate-extra mate-applet-dock mate-applet-streamer
#        DM="gdm"
#    elif [[ "$DE" == "Enlightenment" ]]; then
#        arch-chroot /mnt pacman -S --quiet --noconfirm enlightenment terminology
#    elif [[ "$DE" == "Xfce" ]]; then
#        arch-chroot /mnt pacman -S --quiet --noconfirm xfce4 xfce4-goodies
#        DM="lightdm"
#    fi
#done
#
#if [[ "$DM" == "" ]]; then
#    inf "Your selected DE/WM doesn't have a standard display manager. Enter one of the below names, or leave blank for none"
#    inf "- gdm"
#    inf "- sddm"
#    inf "- lightdm (you'll need a greeter package. See Arch Wiki)"
#    inf "- (you can type another Arch package name if you have one in mind)"
#    inf "- [blank] for none"
#    yesno ""
#    ND="$yn"
#    echo "ND=$ND"
#    if [[ "$ND" == "blank" || "$ND" == "none" || "$ND" == "" ]]; then
#        inf "Ok, we will skip the DM install"
#        DM=""
#    else
#        inf "Ok, we'll install $ND"
#        DM="$ND"
#        arch-chroot /mnt pacman -S --quiet --noconfirm $DM
#    fi
#else
#    if [[ "$DM" != "none" ]]; then
#        arch-chroot /mnt pacman -S --quiet --noconfirm $DM
#    fi
#fi
#
#if [[ "$DM" != "" ]]; then
#    if [[ "$DM" == "lightdm" ]]; then
#        arch-chroot /mnt pacman -S --quiet --noconfirm lightdm-gtk-greeter
#    fi
#    if [[ "$DM" != "none" ]]; then
#        arch-chroot /mnt systemctl enable ${DM}
#    fi
#fi
#
#if [[ "$DE" != "none" ]]; then
#    yesno "Would you like to install Firefox to go with ${DE}?"
#    if [[ "$yn" == "0" ]]; then
#        arch-chroot /mnt pacman -S --quiet --noconfirm firefox
#    fi
#fi

yesno "Would you like to install flatpak?"
flatpak="$yn"
if [[ "$flatpak" == "0" ]]; then
    yesno "Would you like to use a gui flatpak store?"
    if [[ "$yn" == "0" ]]; then
        DE=$(dialog --title "Citrine" --menu "Please choose the Store you want to install" 12 100 2 "Gnome Software" "The software store made by gnome (recommended for GTK desktops)" "Discover" "The software store made by KDE (recommended for QT desktops)" --stdout)
        if [[ "$DE" == "Gnome Software" ]]; then
            arch-chroot /mnt pacman -S --quiet --noconfirm gnome-software gnome-software-packagekit-plugin
        elif [[ "$DE" == "Discover" ]]; then
            arch-chroot /mnt pacman -S --quiet --noconfirm discover
        fi
    fi
    arch-chroot /mnt pacman -S --quiet --noconfirm flatpak
    arch-chroot /mnt su - ${UN} -c "flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo"
    dumptitle="Note"
    dump "Adding the flathub remote likely failed. We're sorry we can't work around this. Ask in discord if you need help."
fi

#if [[ "$DE" != "Fig" ]]; then
#    arch-chroot /mnt pacman -S --quiet --noconfirm crystal-grub-theme
#    echo >> /mnt/etc/default/grub
#    echo "GRUB_THEME=\"/usr/share/grub/themes/crystal/theme.txt\"" >> /mnt/etc/default/grub
#else
#    arch-chroot /mnt pacman -S --quiet --noconfirm whitesur-grub-theme fig-configs
#    echo >> /mnt/etc/default/grub
#    echo "GRUB_THEME=\"/usr/share/grub/themes/bigsur/theme.txt\"" >> /mnt/etc/default/grub
#fi
#
if [[ "$EFI" == "yes" ]]; then
    arch-chroot /mnt bootctl install --esp-path=/efi
else 
    arch-chroot /mnt grub-install --target=i386-pc ${DISK}
    arch-chroot /mnt grubmkconfig -o /boot/grub/grub.cfg
fi
#arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

inf "Set a password for root"
done="nope"
while [[ "$done" == "nope" ]]; do
    passbox "Please enter root password"
    passInit="$pass"
    passbox "Please confirm root password"
    passConf="$pass"
    if [[ "$passInit" == "$passConf" ]]; then
        done="yep"
    else 
        dumptitle "Password error"
        dump "Passwords do not match. Please try again."
    fi
done
arch-chroot /mnt usermod --password $(echo ${pass} | openssl passwd -1 -stdin) ${UN}

msgbox "Your username"
UN="$msgdat"
arch-chroot /mnt useradd -m -G wheel -s /bin/bash ${UN}
inf "Set password for ${UN}"
done="nope"
while [[ "$done" == "nope" ]]; do
    passbox "Please enter password for ${UN}"
    passInit="$pass"
    passbox "Please confirm password for ${UN}"
    passConf="$pass"
    if [[ "$passInit" == "$passConf" ]]; then
        done="yep"
    else 
        dumptitle "Password error"
        dump "Passwords do not match. Please try again."
    fi
done
arch-chroot /mnt usermod --password $(echo ${pass} | openssl passwd -1 -stdin) ${UN}

echo >> /mnt/etc/sudoers
echo "# Enabled by Crystalinstall (citrine)" >> /mnt/etc/sudoers
echo "%wheel ALL=(ALL) ALL" >> /mnt/etc/sudoers
echo "Defaults pwfeedback" >> /mnt/etc/sudoers

inf "Installation should now be complete."

yesno "Would you like to chroot into the new install to configure manually? (y/N)"
CH="$yn"
if [[ "$CH" = "0" ]]; then
    inf "Use 'exit' when done."
    arch-chroot /mnt
fi
