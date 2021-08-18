#!/bin/bash +x
# Unnatended Archlinux Installer - by Sebastian Sanchez Baldoncini
#
# Store system options and errors
SYSSEL=/tmp/systemsettings.sh.$$
SYSERR=/tmp/systemerrors.sh.$$

# Store menu options selected by the user
INPUT=/tmp/menu.sh.$$

# Storage file for displaying command outputs
OUTPUT=/tmp/output.sh.$$
PARTS=/tmp/parts.sh.$$
LAYOUTS=/tmp/layouts.sh.$$

# Get absolute paths for config files
COM=$(echo $0 | sed 's/install-my-arch_v1.sh/com-packages.cfg/')
AUR=$(echo $0 | sed 's/install-my-arch_v1.sh/aur-packages.cfg/')

# trap and delete temp files
trap "rm $OUTPUT; rm $PARTS; rm $LAYOUTS; rm $INPUT; rm $SYSSEL; rm SYSERR; exit" SIGHUP SIGINT SIGTERM

# Main packages packages
BASE="base base-devel linux linux-firmware lvm2 man man-pages git"
XORG="xorg-server xorg-xinit xorg-server-common"
# Drivers by installation profile
DVRVMWARE="xf86-video-vmware xf86-input-vmmouse open-vm-tools"
DVRNATIVE="xf86-video-intel nvidia nvidia-utils bumblebee bluedevil powerdevil pulseaudio plasma-pa"
# My Enviroment packages
ENV="plasma-desktop sddm sddm-kcm plasma-nm kscreen konsole dolphin dolphin-plugins ark"


function display()
{
  case $1 in
    error)  dialog --colors --title "\Z1[ ERROR ]" \
            --ok-label RETRY --msgbox "\n\Zb\Z1[!] $2" 7 45
            ;;
    pass) dialog --colors --title "\Z7[ $2 ]\Zn" \
          --ok-label NEXT --no-cancel --insecure \
          --passwordbox "\n$3" 0 0 3>&1 1>&2 2>&3 3>&-
          ;;
    check)  if [ -z $2 ] || [ -z $3 ]; then
              display error "Password cant be empty"
            elif [ $2 != $3 ]; then
              display error "Passwords dont match"
            else
              [[ $4 = 0 ]] && PASSFLAG="Established"; i=1
              [[ $4 = 1 ]] && PASS1FLAG="Established"; i=1
            fi
            ;;
    input)  dialog --colors --clear \
            --title "\Z7[ $2 ]\Zn" \
            --ok-label OK \
            --nocancel \
            --inputbox "$4\nDefault:" 0 0 "$3" \
            3>&1 1>&2 2>&3 3>&- \
            ;;
    radio)  dialog --colors --clear \
            --title "\Z7[ $2 ]\Zn" \
            --radiolist "\nUse [SPACEBAR] for Select:" 0 0 0 \
            $(while read line; do echo $line; done <$PARTS) \
            3>&1 1>&2 2>&3 3>&- \
            ;;
  esac
}

function autodetect()
{
	case $1 in
    dev)  lsblk |grep -iw $2;;
    devs) lsblk -lo NAME,SIZE,TYPE |sed "s/$usb.*//" |grep -iw disk;;
    parts)  lsblk -lo NAME,SIZE,TYPE |sed "s/$usb.*//" |grep -iw part;;
    layout) lsblk -o NAME,SIZE,FSTYPE,TYPE |sed "s/$usb.*//" |grep 'disk\|part';;
    layoutparts)  fdisk -lo Device,Size,Type |grep $PDISP;;
    size_show)  lsblk -l |grep -iw $2 |awk '{print $4}' |tr "," ".";;
    size_calc)  lsblk |grep -iw $2 |awk '{print $4}' |tr -d G |tr -d M |tr "," ".";;
    efi)  EDISP=$(fdisk -l |grep -v $usb |grep EFI |awk '{print $1}' |sed 's/\/dev\///');;
    pv) PV=$(pvs |awk 'NR>1{print $1}' |sed -r 's/.{5}//');;
    cleanpv)  PV=$(fdisk -l |grep LVM |awk '{print $1}' |sed 's/\/dev\///');;
    vgn)  VGN=$(pvs |awk 'NR>1{print $2}');;
    vols) lsblk -lo NAME,SIZE,TYPE |grep lvm;;
    usb)  usb=$(lsblk -lo NAME,FSTYPE |grep -iw iso9660 |awk '{print $1}' |sed 's/.$//');;
    lvm)  lsblk -o NAME,SIZE,TYPE,FSTYPE |grep -i lvm;;
    mountvols)  if cat /proc/mounts | grep -w "$2" &>/dev/null; then
                  text y "[*] $4\e[0m: Ya esta montado"
                elif mount /dev/mapper/$2 $3 &>/dev/null; then
                  text g "[+] $4\e[0m: Montado correctamente"
                else
                  text r "[!] $4\e[0m: Error al montar"
                  read; exit 1
                fi
                ;;
    mountothers)  if cat /proc/mounts | grep -w "$2" > /dev/null; then
                    text y "[*] $4\e[0m: Ya esta montado"
                  elif mount /dev/$2 $3 &>/dev/null; then
                    text g "[+] $4\e[0m: Montado correctamente"
                  else
                    text r "[!] $4\e[0m: Error montar"
                    read; exit 1
                  fi
                  ;;
    makedirs) if [[ ! -d $2 ]]; then
                if mkdir -p $2 &>/dev/null; then
                  text g "[+] $3\e[0m: Se creo el directorio"
                else
                  text r "[!] $3\e[0m: Error al crear directorio"
                  read; exit 1
                fi
              else
                text y "[*] $3\e[0m: El directorio ya existe" 
              fi
              ;;
  esac
}

function restart()
{
  [[ $? -eq 1 ]] && sh $0
}

function text()
{
  case $1 in
    # Bold Red
    r) echo -e "\e[91;1m$2\e[0m";;
    # Bold Green
    g) echo -e "\e[92;1m$2\e[0m";;
    # Bold Yellow
    y) echo -e "\e[93;1m$2\e[0m";;
    # Error
    *) echo "text:Wrong Argument";;
  esac
}

function reverse_clock()
{
  echo -ne "\e[94;1m"
  sleep 1
  x=5
  while [[ "$x" -ge 0 ]]; do
    echo -ne "$clockfor $x\r"
    x=$(( $x - 1 ))
    sleep 1
  done
  echo -ne "\n\e[0m"
}

#------------------[ START PROGRAM ]---------------------

clear; text y "\n[*] Check Internet Connection\n"
ping -c4 1.1.1.1
# Download dialog if necesary
if [[ $? = 0 ]]; then
  if [[ ! $(pacman -Qs dialog shell scripts) ]]; then
    text y "\n[*] Updating Repositories\n"
    pacman -Sy --noconfirm
    text y "\n[*] Install Dialog\n"
    pacman -S dialog --noconfirm
  fi
else
  text r "\n[!] No Internet Connection\n"; exit 1
fi

autodetect usb
autodetect devs >$OUTPUT
while [[ -z $PDISP ]]; do
  # Device to partition
  PDISP=$(dialog --colors --clear --backtitle "UNNATENDED ARCHLINUX INSTALLER - STEP 1/5" \
  --title "\Z7[ SELECT STORAGE DEVICE ]\Zn" \
  --ok-label OK \
  --nocancel \
  --radiolist "\nUse [SPACEBAR] for Select:" 0 0 0 $(while read line; do echo $line; done <$OUTPUT) \
  3>&1 1>&2 2>&3 3>&- \
  )

  # Format selected device
  if [[ -n $PDISP ]]; then
    clear; cfdisk /dev/$PDISP
  fi
done


#------------------[ SYSTEM SETTINGS MENU ]---------------------

# Collect Storage Info
echo -e "\nLAYOUT:" >$LAYOUTS
autodetect layout >>$LAYOUTS
echo -e "\nSELECTED:" >>$LAYOUTS
autodetect layoutparts >>$LAYOUTS
echo -e "\nLVM DETECTED:" >>$LAYOUTS
if [[ $(autodetect vols) ]]; then
  autodetect lvm >>$LAYOUTS
  autodetect pv
  PVSIZE=$(autodetect size_show $PV)
  autodetect vgn
else
  autodetect cleanpv
  PVSIZE=$(autodetect size_show $PV)
  VGN="ARCH"
  LVROOT="root"
  LVHOME="home"
  echo -e "None" >>$LAYOUTS
fi
echo -e "\n[*] Requiered\n[ ] Optional\n\nDEFAULTS:" >>$LAYOUTS

# Search for efi part without format
autodetect efi
ESIZE=$(autodetect size_show $EDISP)

# My Default Settings
RDISP=""
HDISP=""
RPOINT="/mnt"
BPOINT="$RPOINT/boot"
EPOINT="$RPOINT/boot/efi"
HOST="Archlinux"
USR1="cbass"
HPOINT="$RPOINT/home"
MPOINT="/run/ssd"
EFIFLAG="No"
IMPFLAG="No"
USELVM="No"

# System Settings Pool
declare -i g=0
while [[ $g = 0 ]]; do
  dialog --clear --colors --backtitle "UNNATENDED ARCHLINUX INSTALLER - STEP 2/5" \
  --separate-widget $"\n" \
  --title "\Z7[ SYSTEM OPTIONS ]\Zn" \
  --cancel-label RESTART \
  --menu "$(<$LAYOUTS)" 0 0 0 \
  " [*] Flag" "Install Profile:\Z4$TYPEFLAG\Zn | Format EFI:\Z4$EFIFLAG\Zn" \
  " [*] Boot" "Partition:\Z4$BDISP\Zn | Mount:\Z4$BPOINT\Zn" \
  " [*] Efi" "Partition:\Z4$EDISP\Zn | Mount:\Z4$EPOINT\Zn" \
  " [*] Lvm" "Use LVM:\Z4$USELVM\Zn Partition:\Z4$PV\Zn | Group:\Z4$VGN\Zn | Size:\Z4$PVSIZE\Zn" \
  " [*] Root" "Part:\Z4$RDISP\Zn Volume:\Z4$LVROOT\Zn | Size:\Z4$RSIZE\Zn | Mount:\Z4$RPOINT\Zn" \
  " [*] Pass" "Root User Password:\Z4$PASSFLAG\Zn" \
  " [ ] User" "Username:\Z4$USR1\Zn | Password:\Z4$PASS1FLAG\Zn" \
  " [ ] Home" "Part:\Z4$HDISP\Zn Volume:\Z4$LVHOME\Zn | Size:\Z4$HSIZE\Zn | Mount:\Z4$HPOINT\Zn" \
  " [ ] Host" "Hostname:\Z4$HOST\Zn" \
  " [ ] Ntfs" "Data Partition:\Z4$MDISP\Zn | Size:\Z4$MSIZE\Zn | Mount:\Z4$MPOINT\Zn" \
  " [!] DONE" "\Zb\Z6NEXT STEP\Zn" \
  2>"${INPUT}"
  restart
  menuitem=$(<"${INPUT}")

  # Option selected
  case $menuitem in
    " [*] Flag")
    TYPEFLAG=$(dialog --colors --clear --title "\Z7[ INSTALL PROFILE ]\Zn" \
    --yes-button "VMWARE" \
    --no-button "NATIVE" \
    --yesno "\n This will install drivers and services consequently." 7 65 \
    3>&1 1>&2 2>&3 3>&- \
    )
    [[ $? = 0 ]] && TYPEFLAG="Vmware"
    [[ $? = 1 ]] && TYPEFLAG="Native"
    EFIFLAG=$(dialog --colors --clear --backtitle "" \
    --title "\Z7[ EFI FORMAT ]\Zn" \
    --yesno "\n If efi partition is shared with other/s OS chose No" 7 65 \
    3>&1 1>&2 2>&3 3>&- \
    )
    [[ $? = 0 ]] && EFIFLAG="Yes"
    [[ $? = 1 ]] && EFIFLAG="No"
    ;;
    " [*] Boot")
    autodetect parts >$PARTS
    BDISP=$(display radio "SELECT BOOT DEVICE")
    BPOINT=$(display input "BOOT MOUNT POINT" "$BPOINT")
    BSIZE=$(autodetect size_show $BDISP)
    ;;
    " [*] Efi")
    autodetect parts >$PARTS
    EDISP=$(display radio "SELECT EFI DEVICE")
    ESIZE=$(autodetect size_show $EDISP)
    EPOINT=$(display input "EFI MOUNT POINT" "$EPOINT")
    ;;
    " [*] Lvm")
    autodetect parts >$PARTS
    USELVM=$(dialog --colors --clear --backtitle "" \
    --title "\Z7[ LOGICAL VOLUMES ]\Zn" \
    --yesno "\n Gonna use LVM?" 7 65 \
    3>&1 1>&2 2>&3 3>&- \
    )
    [[ $? = 0 ]] && USELVM="Yes"
    [[ $? = 1 ]] && USELVM="No"
    if [ $USELVM = "Yes" ]; then
    PV=$(display radio "SELECT LVM DEVICE")
    PVSIZE=$(autodetect size_show $PV)
    VGN=$(display input "ENTER VOLUME GROUP NAME" "$VGN")
    fi
    ;;
    " [*] Root")
    if [ $USELVM = "Yes" ]; then
      if [[ -n $VGN ]]; then
        if [[ $(lvs) ]]; then
          autodetect vols >$PARTS
          LVROOT=$(display radio "SELECT ROOT VOLUME")
          if [[ -n $LVROOT ]]; then
            VGN=$(echo $LVROOT |sed 's/-.*//')
            LVROOT=$(echo $LVROOT |sed 's/.*-//')
            RSIZE=$(autodetect size_show $LVROOT)
          else
            RSIZE=""
            LVROOT=$(display input "ROOT VOLUME NAME" "$LVROOT")
            [[ -n $LVROOT ]] && RSIZE=$(display input "ROOT VOLUME SIZE" "$RSIZE")
          fi
          [[ -n $LVROOT ]] && RPOINT=$(display input "ROOT MOUNT POINT" "$RPOINT")
        else
          LVROOT=$(display input "ROOT VOLUME NAME" "$LVROOT")
          [[ -n $LVROOT ]] && RSIZE=$(display input "ROOT VOLUME SIZE" "$RSIZE")
        fi
      else
        display error "MUST SET LVM GROUP FIRST!"
      fi
    else
      RDISP=$(display radio "SELECT ROOT PARTITION")
      RSIZE=$(autodetect size_show $RDISP)
    fi
    ;;
    " [*] Pass")
    declare -i i=0
    while [[ $i = 0 ]]; do
      PASS=$(display pass "ROOT USER PASSWORD" "Enter ROOT password:")  
      PASSCHK=$(display pass "ROOT USER PASSWORD" "Retype ROOT password:")
      display check $PASS $PASSCHK 0
    done
    ;;
    " [ ] User")
    USR1=$(display input "ENTER USER NAME" "$USR1" "\nEmpty for skip user account and home dir creation\n")
    if [[ -n $USR1 ]]; then
      declare -i i=0
      while [[ $i = 0 ]]; do
        PASS1=$(display pass "USER PASSWORD" "Enter $USR1 password:")  
        PASS1CHK=$(display pass "USER PASSWORD" "Retype $USR1 password:")
        display check $PASS1 $PASS1CHK 1
      done
      HPOINT="$RPOINT/home"
    else
      PASS1FLAG=""; HDISP=""; LVHOME=""; HSIZE=""; HPOINT=""
    fi
    ;;
    " [ ] Home")
    if [[ -n $USR1 ]]; then
     if [ $USELVM = "Yes" ]; then
      if [[ $(lvs) ]]; then
       autodetect vols >$PARTS && LVHOME=$(display radio "SELECT HOME VOLUME")
       if [[ -n $LVHOME ]]; then      
         VGN=$(echo $LVHOME |sed 's/-.*//')
         LVHOME=$(echo $LVHOME |sed 's/.*-//')
         HSIZE=$(autodetect size_show $LVHOME)
       else
         HSIZE=""
         LVHOME=$(display input "HOME VOLUME NAME" "$LVHOME")
         [[ -n $LVHOME ]] && HSIZE=$(display input "HOME VOLUME SIZE" "$HSIZE")
       fi
      else
       LVHOME=$(display input "HOME VOLUME NAME" "$LVHOME")
       [[ -n $LVHOME ]] && HSIZE=$(display input "HOME VOLUME SIZE" "$HSIZE")
      fi
       [[ -n $LVHOME ]] && HPOINT=$(display input "HOME MOUNT POINT" "$HPOINT")
     else
      HDISP=$(display radio "SELECT HOME PARTITION")
      HSIZE=$(autodetect size_show $HDISP)
     fi
    else
     display error "Please set user first"
    fi
    ;;
    " [ ] Host")
    HOST=$(display input "ENTER HOSTNAME" "$HOST")
    ;;
    " [ ] Ntfs")
    autodetect parts >$PARTS
    MDISP=$(display radio "SELECT DATA PARTITION")
    MPOINT=$(display input "DATA MOUNT POINT" "$MPOINT")
    MSIZE=$(autodetect size_show $MDISP)
    ;;
    " [!] DONE") g=1;;
  esac
done

# Select community packages
PAC1=$(dialog --colors --clear --backtitle "UNNATENDED ARCHLINUX INSTALLER - STEP 3/5" \
--no-items \
--title "\Z7[ COMMUNITY PACKAGES ]\Zn" \
--nocancel \
--checklist "\nSelect packages:" 0 0 0 $(while read line; do echo $line; done <$COM) \
3>&1 1>&2 2>&3 3>&- \
)

# Select aur packages
YAY1=$(dialog --colors --clear --backtitle "UNNATENDED ARCHLINUX INSTALLER - STEP 4/5" \
--no-items \
--title "\Z7[ AUR PACKAGES ]\Zn" \
--nocancel \
--checklist "\nSelect packages:" 0 0 0 $(while read line; do echo $line; done <$AUR) \
3>&1 1>&2 2>&3 3>&- \
)

# Settings Resume
dialog --colors --clear --backtitle "UNNATENDED ARCHLINUX INSTALLER - CONFIRM INSTALL" \
--title "\Z7[ SETTINGS RESUME ]\Zn" \
--yes-label "INSTALL" \
--no-label "RESTART" \
--yesno \
"\nREQUIRED:\n
Flag | Install Profile:\Z4$TYPEFLAG\Zn | Import Custom Config:\Z4$IMPFLAG\Zn\n
Boot | Partition:\Z4$BDISP\Zn | Size:\Z4$BSIZE\Zn | Mount:\Z4$BPOINT\Zn\n
 Efi | Partition:\Z4$EDISP\Zn | Size:\Z4$ESIZE\Zn | Mount:\Z4$EPOINT\Zn | Format:\Z4$EFIFLAG\Zn\n
 Lvm | Partition:\Z4$PV\Zn | Size:\Z4$PVSIZE\Zn | Group:\Z4$VGN\Zn\n
Root | Root Volume:\Z4$LVROOT\Zn | Size:\Z4$RSIZE\Zn | Root pass:\Z4$PASSFLAG\Zn\n
\nOPTIONAL:\n
Host | Hostname:\Z4$HOST\Zn\n
User | Username:\Z4$USR1\Zn | $USR1 pass:\Z4$PASS1FLAG\Zn\n
Home | Home Volume:\Z4$LVHOME\Zn | Size:\Z4$HSIZE\Zn | Mount:\Z4$HPOINT\Zn\n
Data | Data Partition:\Z4$MDISP\Zn | Size:\Z4$MSIZE\Zn | Mount:\Z4$MPOINT\Zn\n\n" 0 0

restart
#------------------[ START INSTALLATION ]---------------------

# Commands
CHR="arch-chroot $RPOINT sh -c"
INSTALL="pacman -S --color always --noconfirm"
SEARCH="pacman -Ss --color always"

clear

clockfor="[*] Start Format and LVM if necesary... "
reverse_clock
if [ $USELVM = "Yes" ]; then
 # Create volume group if necesary
 [[ ! $(autodetect dev $VGN) ]] && text g "\n[+] Creating Lvm Group: $VGN\n" && vgcreate $VGN /dev/$PV
 # Create root volume if necesary
 [[ ! $(autodetect dev "$VGN-$LVROOT") ]]  && text g "\n[+] Creating Lvm volume: $VGN-$LVROOT\n" && lvcreate -L $RSIZE $VGN -n $LVROOT
 # Check and umount before format
 if cat /proc/mounts | grep -w "$VGN-$LVROOT" &>/dev/null; then
   umount -R $RPOINT
 fi
 # Format Root Volume
 text g "\n[+] Formating $VGN-$LVROOT\n"
 mkfs.ext4 -F /dev/mapper/$VGN-$LVROOT
else
 # Format Root Partition
 text g "\n[+] Formating root partition $RDISP\n"
 mkfs.ext4 -F /dev/$RDISP
fi

# Format boot
mkfs.ext4 -F /dev/$BDISP
text g "\n[+] Formating Boot partition\n"
# Check Efi flag before format
[[ $EFIFLAG = "Yes" ]] && text g "\n[+] Formating Efi partition\n" && mkfs.vfat -F 32 /dev/$EDISP
[[ $EFIFLAG = "No" ]] && text y "\n[+] Skiping Efi partition format\n"
# Create home volume if user account has being set
if [[ -n $USR1 ]]; then
 if [ $USELVM = "Yes" ]; then
  if [[ ! $(autodetect dev $VGN-$LVHOME) ]]; then
    text g "[+] Creating Lvm volume $VGN-$LVHOME\n"
    lvcreate -L $HSIZE $VGN -n $LVHOME
    text g "\n[+] Formating Lvm volume $LVHOME\n"
    mkfs.ext4 -F /dev/mapper/$VGN-$LVHOME
  else
    text g "\n[+] Formating detected volume $VGN-$LVHOME\n"
    mkfs.ext4 -F /dev/mapper/$VGN-$LVHOME 
  fi
 else
  text g "\n[+] Formating home partition $HDISP\n"
  mkfs.ext4 -F /dev/$HDISP
 fi
fi

#------------------[ CHECK DIRS AND MOUNT ]---------------------

clockfor="[*] Start partitions mounting... "
reverse_clock

autodetect makedirs "$RPOINT" "Root"
if [ $USELVM = "Yes" ]; then
 autodetect mountvols "$VGN-$LVROOT" "$RPOINT" "Root"
else
 autodetect mountothers "$RDISP" "$RPOINT" "Root"
fi
autodetect makedirs "$BPOINT" "Boot"
autodetect mountothers "$BDISP" "$BPOINT" "Boot"
autodetect makedirs "$EPOINT" "Efi"
autodetect mountothers "$EDISP" "$EPOINT" "Efi"
# Check user and mount home
if [[ -n $USR1 ]]; then
 autodetect makedirs "$HPOINT" "home"
 if [ $USELVM = "Yes" ]; then
  autodetect mountvols "$VGN-$LVHOME" "$HPOINT" "home"
 else
  autodetect mountothers "$HDISP" "$HPOINT" "home"
 fi
fi

#------------------[ PACSTRAP AND FSTAB ]---------------------

clockfor="[*] Start Base Instalation... "
reverse_clock

pacstrap $RPOINT $BASE

text g "\n [+] Updating FSTAB\n"
genfstab -U $RPOINT >> $RPOINT/etc/fstab
# Insert ntfs Data Partition if set
[[ -n $MDISP ]] && echo "UUID=$(lsblk -lo NAME,UUID |grep -w $MDISP |awk '{print $2}') $MPOINT ntfs-3g rw,users,umask=0022,uid=1000,gid=100 0 0" >> $RPOINT/etc/fstab

#------------------[ CHROOT DEFAULT ]---------------------

clockfor="[*] Start Arch-chroot session... "
reverse_clock

text g "\n[+] Setting Time Zone\n"
$CHR "ln -sf /usr/share/zoneinfo/America/Argentina/Buenos_Aires /etc/localtime"

text g "\n[+] Generating /etc/adjtime\n"
$CHR "hwclock --systohc"

text g "\n[+] Uncomment es_AR in locale.gen\n"
$CHR "sed -i '/es_AR/s/^#//g' /etc/locale.gen"

text g "\n[+] Generating locale\n"
$CHR "locale-gen"
$CHR "echo LANG=es_AR.UTF-8 > /etc/locale.conf"

text g "\n[+] Setting Latam Keymap\n"
$CHR "echo KEYMAP=la-latin1 >> /etc/vconsole.conf"

if [[ -n $HOST ]]; then
  text g "\n[+] Setting hostname: $HOST\n"
  $CHR "echo $HOST > /etc/hostname"
fi

text g "\n[+] mkinitcpio: Loading lvm and generating image\n"
$CHR "sed -i 's/modconf block filesystems/modconf block lvm2 filesystems/g' /etc/mkinitcpio.conf"
$CHR "mkinitcpio -p linux"

text g "\n[+] Setting Root user password\n"
$CHR "echo root:$PASS | chpasswd"

text g "\n[+] Installing ZSH before shell setting\n"
$CHR "$INSTALL zsh zsh-completions"
$CHR "chsh -s /bin/zsh"

text g "\n[+] Enable multilib repo\n"
$CHR "sed -i '93,94 s/# *//' /etc/pacman.conf"

text g "\n[+] Updating Pacman bases\n"
$CHR "pacman -Sy"

text g "\n[+] Installing Xorg packages\n"
$CHR "$INSTALL $XORG"

# Drivers packages
if [ $TYPEFLAG = "Vmware" ]; then
  clockfor="[!] Installing drivers for Vmware profile... "
  reverse_clock
  $CHR "$INSTALL $DVRVMWARE"
  text g "\n[+] Enable vmtool service\n"
  $CHR "systemctl enable vmtoolsd.service"
fi

if [ $TYPEFLAG = "Native" ]; then
  clockfor="[!] Installing drivers for Native profile... "
  reverse_clock
  $CHR "$INSTALL $DVRNATIVE"
  text g "\n[+] Enable Bluetooth service\n"
  $CHR "systemctl enable bluetooth"
  $CHR "systemctl enable bumblebeed"
fi

text g "\n[+] Installing Enviroment packages\n"
$CHR "$INSTALL $ENV"

text g "\n[+] Enable SDDM service\n"
$CHR "systemctl enable sddm"

text g "\n[+] Enable NetworkManager service\n"
$CHR "systemctl enable NetworkManager"

text g "\n[+] Setting services timeout\n"
$CHR "sed -i '42,43 s/# *//' /etc/systemd/system.conf"
$CHR "sed -i 's/90s/9s/g' /etc/systemd/system.conf"

text g "\n[+] Enabñe IPTABLES with basic configuration \n"
$CHR "cp /etc/iptables/simple_firewall.rules /etc/iptables/iptables.rules"
$CHR "systemctl enable iptables"

text g "\n[+] Installing Bootloader with fixed path\n"
$CHR "$INSTALL refind"
$CHR "refind-install"
_BPOINT=$(echo "$BPOINT" | sed 's/[/]mnt//g')
if [ $USELVM = "Yes"]; then
 $CHR "sed -i 's/archisobasedir=arch/ro root=\/dev\/mapper\/$VGN-$LVROOT/g' $_BPOINT/refind_linux.conf"
else
 $CHR "sed -i 's/archisobasedir=arch/ro root=\/dev\/$RDISP/g' $_BPOINT/refind_linux.conf"
fi

clockfor="[!] Installing community packages selected... "
reverse_clock
$CHR "$INSTALL $PAC1"

# User account
if [[ -n $USR1 ]]; then
  text g "\n[+] Creating user $USR1 with common groups\n"
  $CHR "useradd -m -g users -G wheel,power,storage -s /bin/bash $USR1"; sleep 2
  text g "\n[+] Setting password for $USR1\n"
  $CHR "echo $USR1:$PASS1 | chpasswd"
  text g "\n[+] Setting zshell for $USR1\n"
  $CHR "chsh -s /bin/zsh $USR1"
  text g "\n[+] Setting basic config for Sudo\n"
  $CHR "sed -i '82 s/# *//' /etc/sudoers"
  text g "\n[+] Installing AUR helper YAY\n"
  $CHR "git clone https://aur.archlinux.org/yay.git"
  $CHR "chown $USR1:users /yay;cd /yay;sudo -u $USR1 makepkg --noconfirm -sci"
  $CHR "rm -rf /yay"
  clockfor="[!] Installing AUR packages selected... "
  reverse_clock
  YAYINSTALL="sudo -u $USR1 yay --noconfirm --color always -S"
  $CHR "yay -Sy"
  $CHR "$YAYINSTALL $YAY1"
fi

#------------------[ UMOUNT AND REBOOT ]---------------------

  clockfor="[!] Desmontar y reiniciar en... "
  reverse_clock
  umount -R $RPOINT
  reboot


# If temp files found, delete em
[ -f $SYSSEL ] && rm $SYSSEL
[ -f $OUTPUT ] && rm $OUTPUT
[ -f $INPUT ] && rm $INPUT
