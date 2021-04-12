#!/bin/bash +x
# Unnatended Archlinux Installer - by Sebastian Sanchez Baldoncini

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
COM=$(echo $0 | sed 's/install_my_arch.sh/com-packages.cfg/')
AUR=$(echo $0 | sed 's/install_my_arch.sh/aur-packages.cfg/')

# trap and delete temp files
trap "rm $OUTPUT; rm $PARTS; rm $LAYOUTS; rm $INPUT; rm $SYSSEL; rm SYSERR; exit" SIGHUP SIGINT SIGTERM

# Main packages packages
BASE="base base-devel linux linux-firmware lvm2 man man-pages"
XORG="xorg-server xorg-xinit xorg-server-common"
# Drivers by installation profile
DVRVMWARE="xf86-video-vmware xf86-input-vmmouse open-vm-tools"
DVRNATIVE="xf86-video-intel nvidia nvidia-utils bumblebee bluedevil powerdevil pulseaudio plasma-pa"
# My Enviroment packages
ENV="plasma-desktop sddm sddm-kcm plasma-nm kscreen konsole dolphin dolphin-plugins ark"


function display()
{
  case $1 in
    error) dialog --colors --title "\Z1[ ERROR ]" \
           --ok-label RETRY --msgbox "\n\Zb\Z1[!] $2" 7 45;;
    pass) dialog --colors --title "\Z7[ $2 ]\Zn" \
          --ok-label NEXT --no-cancel --insecure \
          --passwordbox "\n$3" 0 0 3>&1 1>&2 2>&3 3>&-;;
    check) if [ -z $2 ] || [ -z $3 ]; then
             display error "Password cant be empty"
           elif [ $2 != $3 ]; then
             display error "Passwords dont match"
           else
             [[ $4 = 0 ]] && PASSFLAG="Established"; i=1
             [[ $4 = 1 ]] && PASS1FLAG="Established"; i=1
           fi;;
    input) dialog --colors --clear \
           --title "\Z7[ $2 ]\Zn" \
           --ok-label OK \
           --nocancel \
           --inputbox "$4\nDefault:" 0 0 "$3" \
           3>&1 1>&2 2>&3 3>&- \
           ;;
    radio) dialog --colors --clear \
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
    dev) lsblk |grep -iw $2;;
    devs) lsblk -lo NAME,SIZE,TYPE |sed "s/$usb.*//" |grep -iw disk;;
    parts) lsblk -lo NAME,SIZE,TYPE |sed "s/$usb.*//" |grep -iw part;;
    layout) lsblk -o NAME,SIZE,FSTYPE,TYPE |sed "s/$usb.*//" |grep 'disk\|part';;
    layoutparts) fdisk -lo Device,Size,Type |grep $PDISP;;
    size_show) lsblk -l |grep -iw $2 |awk '{print $4}' |tr "," ".";;
    size_calc) lsblk |grep -iw $2 |awk '{print $4}' |tr -d G |tr -d M |tr "," ".";;
    efi) EDISP=$(fdisk -l |grep -v $usb |grep EFI |awk '{print $1}' |sed 's/\/dev\///');;
    pv) PV=$(pvs |awk 'NR>1{print $1}' |sed -r 's/.{5}//');;
    cleanpv) PV=$(fdisk -l |grep LVM |awk '{print $1}' |sed 's/\/dev\///');;
    vgn) VGN=$(pvs |awk 'NR>1{print $2}');;
    vols) lsblk -lo NAME,SIZE,TYPE |grep lvm;;
    usb) usb=$(lsblk -lo NAME,FSTYPE |grep -iw iso9660 |awk '{print $1}' |sed 's/.$//');;
    lvm) lsblk -o NAME,SIZE,TYPE,FSTYPE |grep -i lvm;;
    mountvols) if cat /proc/mounts | grep -w "$2" &>/dev/null; then
                 text y "[*] $4\e[0m: Ya esta montado"
               elif mount /dev/mapper/$2 $3 &>/dev/null; then
                 text g "[+] $4\e[0m: Montado correctamente"
               else
                 text r "[!] $4\e[0m: Error al montar"
                 read; exit 1
               fi
               ;;
    mountothers) if cat /proc/mounts | grep -w "$2" > /dev/null; then
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
autodetect mountothers "$BDISP" "$BPOINT" "Boot"
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
    *) echo "Wrong Argument";;
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

# Collect System Info
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
RPOINT="/mnt"
BPOINT="$RPOINT/boot"
EPOINT="$RPOINT/boot/efi"
HOST="Archlinux"
USR1="cbass"
HPOINT="$RPOINT/home"
MPOINT="/run/ssd"
EFIFLAG="No"
IMPFLAG="No"

# System Settings Pool
declare -i g=0
while [[ $g = 0 ]]; do
  dialog --clear --colors --backtitle "UNNATENDED ARCHLINUX INSTALLER - STEP 2/5" \
  --separate-widget $"\n" \
  --title "\Z7[ SYSTEM OPTIONS ]\Zn" \
  --cancel-label RESTART \
  --menu "$(<$LAYOUTS)" 0 0 0 \
  " [*] Flag" "Install Profile:\Z4$TYPEFLAG\Zn | Format EFI:\Z4$EFIFLAG\Zn" \
  " [*] Conf" "Import Home:\Z4$IMPFLAG\Zn" \
  " [*] Boot" "Partition:\Z4$BDISP\Zn | Mount:\Z4$BPOINT\Zn" \
  " [*] Efi" "Partition:\Z4$EDISP\Zn | Mount:\Z4$EPOINT\Zn" \
  " [*] Lvm" "Partition:\Z4$PV\Zn | Group:\Z4$VGN\Zn | Size:\Z4$PVSIZE\Zn" \
  " [*] Root" "Root Volume:\Z4$LVROOT\Zn | Size:\Z4$RSIZE\Zn | Mount:\Z4$RPOINT\Zn" \
  " [*] Pass" "Root User Password:\Z4$PASSFLAG\Zn" \
  " [ ] User" "Username:\Z4$USR1\Zn | Password:\Z4$PASS1FLAG\Zn" \
  " [ ] Home" "Home Volume:\Z4$LVHOME\Zn | Size:\Z4$HSIZE\Zn | Mount:\Z4$HPOINT\Zn" \
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
    " [*] Conf")
    IMPFLAG=$(dialog --colors --clear --title "\Z7[ SELECT DIR HOME TO IMPORT ]\Zn" \
    --dselect "$(dirname $0)" 0 0 \
    3>&1 1>&2 2>&3 3>&- \
    )
    clear; echo "$IMPFLAG"; read
    # [[ $? = 0 ]] && IMPFLAG="Yes"
    # [[ $? = 1 ]] && IMPFLAG="No"
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
    PV=$(display radio "SELECT LVM DEVICE")
    PVSIZE=$(autodetect size_show $PV)
    VGN=$(display input "ENTER VOLUME GROUP NAME" "$VGN")
    ;;
    " [*] Root")
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
      PASS1FLAG=""; LVHOME=""; HSIZE=""; HPOINT=""
    fi
    ;;
    " [ ] Home")
    if [[ -n $USR1 ]]; then
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

clockfor="[*] Comienza LVM y Format en... "
reverse_clock

# Create volume group if necesary
[[ ! $(autodetect dev $VGN) ]] && vgcreate $VGN /dev/$PV && text g "\n[+] Se creo grupo lvm $VGN\n"
# Create root volume if necesary
[[ ! $(autodetect dev "$VGN-$LVROOT") ]] && lvcreate -L $RSIZE $VGN -n $LVROOT && text g "\n[+] Se creo volumen $LVROOT\n"

# Umount root if necesary
if cat /proc/mounts | grep -w "$VGN-$LVROOT" &>/dev/null; then
  umount -R $RPOINT
fi

#Format root
mkfs.ext4 -F /dev/mapper/$VGN-$LVROOT
text g "\n[+] $VGN-$LVROOT: Formato completo\n"
#Format boot
mkfs.ext4 -F /dev/$BDISP
text g "\n[+] Boot: Formato completo\n"
#Format efi flag
[[ $EFIFLAG = "Yes" ]] && mkfs.vfat -F 32 /dev/$EDISP && text g "\n[+] EFI: Formato completo\n"
[[ $EFIFLAG = "No" ]] && text y "\n[+] EFI: NO se formateo\n"
# Create home volume if user account has being set
if [[ -n $USR1 ]]; then
  if [[ ! $(autodetect dev $VGN-$LVHOME) ]]; then
    lvcreate -L $HSIZE $VGN -n $LVHOME
    text g "[+] Se creo volumen $LVHOME\n"
    mkfs.ext4 -F /dev/mapper/$VGN-$LVHOME
    text g "\n[+] Se formateo nuevo vol $LVHOME\n"
  else
    mkfs.ext4 -F /dev/mapper/$VGN-$LVHOME
    text g "\n[+] Se formateo vol existente $LVHOME\n"
  fi
fi
text g "\n[+] Lvm y Format finalizado\n"
read

#------------------[ CHECK AND MOUNT ]---------------------

# Crear dir Root de ser necesario
autodetect makedirs "$RPOINT" "Root"

# Montar root de ser necesario
autodetect mountvols "$VGN-$LVROOT" "$RPOINT" "Root"

# Crear dir boot de ser necesario
autodetect makedirs "$BPOINT" "Boot"
  
# Montar boot de ser necesario
autodetect mountothers "$BDISP" "$BPOINT" "Boot"

# Crear dir efi de ser necesario
autodetect makedirs "$EPOINT" "Efi"

# Montar efi de ser necesario
autodetect mountothers "$EDISP" "$EPOINT" "Efi"

# Verifica si se configuro usuario y procede
if [[ -n $USR1 ]]; then
  #Crear dir home de ser necesario
  autodetect makedirs "$HPOINT" "home"
  autodetect mountvols "$VGN-$LVHOME" "$HPOINT" "home"
fi

read
#------------------[ PACSTRAP AND FSTAB ]---------------------

clockfor="[*] Comienza Pacstrap en... "
reverse_clock
  
# Instalacion base kernel
pacstrap $RPOINT $BASE
text g "\n [+] Pacstrap: instalacion finalizada\n"

# Generar FSTAB
genfstab -U $RPOINT >> $RPOINT/etc/fstab
# Insert ntfs Data Partition if set
[[ -n $MDISP ]] && echo "UUID=$(lsblk -lo NAME,UUID |grep -w $MDISP |awk '{print $2}') $MPOINT ntfs-3g rw,users,umask=0022,uid=1000,gid=100 0 0" >> $RPOINT/etc/fstab
text g "\n [+] FSTAB Actualizado\n"

#------------------[ CHROOT DEFAULT ]---------------------

clockfor="[*] Comienza Arch-chroot en... "
reverse_clock

# Agregar zona
$CHR "ln -sf /usr/share/zoneinfo/America/Argentina/Buenos_Aires /etc/localtime"
text g "\n[+] Se configuro zona horaria\n"

# Generar /etc/adjtime
$CHR "hwclock --systohc"
text g "\n[+] Se configuro hwclock\n"

# Descomentando lineas es_AR en locale.gen..."
$CHR "sed -i '/es_AR/s/^#//g' /etc/locale.gen"
text g "\n[+] locale.gen editado - AR habilitado\n"

# Generando locale
$CHR "locale-gen"
text g "\n[+] Locale generado correctamente\n"

# Crear locale.conf y agregar "es_AR"
$CHR "echo LANG=es_AR.UTF-8 > /etc/locale.conf"
text g "\n[+] Se creo y configuro locale.conf\n"

# la-latin1 permanente (lo lee systemd en booteo)"
$CHR "echo KEYMAP=la-latin1 >> /etc/vconsole.conf"
text g "\n[+] Se configuro distribucion de teclado\n"

# Hostname
if [[ -n $HOST ]]; then
  $CHR "echo $HOST > /etc/hostname"
  text g "\n[+] Se configuro hostname como $HOST\n"
fi

# Load lvm to mkinicpio.conf and generate image
$CHR "sed -i 's/modconf block filesystems/modconf block lvm2 filesystems/g' /etc/mkinitcpio.conf"
text g "\n[+] Se agrego modulo lvm a mkinitcpio.conf\n"
$CHR "mkinitcpio -p linux"

$CHR "$INSTALL zsh zsh-completions"

# Root user
$CHR "chsh -s /bin/zsh"
$CHR "echo root:$PASS | chpasswd"
text g "\n[+] Se establecio password para root\n"

# Enable multilib repo
$CHR "sed -i '92,93 s/# *//' /etc/pacman.conf"
text g "\n[+] Pacman multilib habilitado\n"

# Upadte repos
$CHR "pacman -Sy"
text g "\n[+] Pacman: Bases de repo actualizadas\n"

# Install Xorg packages
$CHR "$INSTALL $XORG"
text g "\n[+] Paquetes Xorg instalados\n"

# Install Drivers packages
if [ $TYPEFLAG = "Vmware" ]; then
  clockfor="[!] Instalar drivers para maquina virtual en... "
  reverse_clock
  $CHR "$INSTALL $DVRVMWARE"
  text g "\n[+] Drivers para VM instalados\n"
  $CHR "systemctl enable vmtoolsd.service"
  text g "\n[+] Servicio VmTools habilitado\n"
fi

if [ $TYPEFLAG = "Native" ]; then
  clockfor="[!] Instalar drivers para Notebook en... "
  reverse_clock
  $CHR "$INSTALL $DVRNATIVE"
  text g "\n[+] Drivers para Notebook ACER instalados\n"
  $CHR "systemctl enable bluetooth"
  text g "\n[+] Servicio Bluetooth habilitado\n"
fi

# Install Enviroment packages
$CHR "$INSTALL $ENV"
text g "\n[+] Paquetes de Entorno instalados\n"

# Enable SDDM
$CHR "systemctl enable sddm"
text g "\n[+] SDDM habilitado en inicio\n"

# Enable Networking
$CHR "systemctl enable NetworkManager"
text g "\n[+] Servidio NetworkManager habilitado\n"

# Services timeout
$CHR "sed -i '42,43 s/# *//' /etc/systemd/system.conf"
$CHR "sed -i 's/90s/9s/g' /etc/systemd/system.conf"
text g "\n[+] Se acelero timeout de servicios\n"

# Iptables Basic Security
$CHR "cp /etc/iptables/simple_firewall.rules /etc/iptables/iptables.rules"
$CHR "systemctl enable iptables"
text g "\n[+] IPTABLES habilitado con seguridad basica\n"

# Install stock bootloader
$CHR "$INSTALL refind"
$CHR "refind-install"
# Fix root device on 'refind.conf'
_BPOINT=$(echo "$BPOINT" | sed 's/[/]mnt//g')  
$CHR "sed -i 's/archisobasedir=arch/ro root=\/dev\/mapper\/$VGN-$LVROOT/g' $_BPOINT/refind_linux.conf"
text g "\n[+] Instalacion del bootloader finalizada\n"

# Install PAC1 Packages
$CHR "$INSTALL $PAC1"
text g "\n[+] Paquetes PAC1 instalados\n"

# User account
if [[ -n $USR1 ]]; then
  $CHR "useradd -m -g users -G wheel,power,storage -s /bin/bash $USR1"; sleep 2
  text g "\n[+] Se creo usuario $USR1 y se agrego a los grupos wheel, power y storage\n"
  $CHR "echo $USR1:$PASS1 | chpasswd"
  text g "\n[+] Se establecio password para $USR1\n"
  $CHR "chsh -s /bin/zsh $USR1"
  text g "\n[+] Se establecio ZSH para root y usuario\n"
  # Sudo Basic config
  $CHR "sed -i '82 s/# *//' /etc/sudoers"
  text g "\n[+] Acceso basico a sudo configurado\n"
  # Install YAY
  $CHR "git clone https://aur.archlinux.org/yay.git"
  $CHR "chown $USR1:users /yay;cd /yay;sudo -u $USR1 makepkg --noconfirm -sci"
  $CHR "rm -rf /yay;yay -Sy"
  text g "\n[+] AUR helper YAY instalado\n"
  # Install YAY1 Packages
  YAYINSTALL="sudo -u $USR1 yay --noconfirm --color always -S"
  $CHR "yay -Sy"
  $CHR "$YAYINSTALL $YAY1"
  text g "\n[+] Paquetes de YAY1 instalados\n"
  text c "\n[+] Arch-chroot: instalacion finalizada\n"; read; exit
fi

#------------------[ CHROOT CUSTOM ]---------------------

  clockfor="[*] Comienza capa de personalizacion en... "
  reverse_clock

  #Copiar home de usuario
  rsync -Paq /install/custom/cbass/ $RPOINT/home/$USR1
  text g "\n[+] Se copiaron archivos de configuracion para el usuario $USR1\n"
  sleep 1

  #Correjir permisos de los archivos soncronizados
  $CHR "chown -R $USR1:users /home/$USR1"
  text g "\n[+] Permisos de $USR1 corregidos\n"
  sleep 1

  #Sincro usr/share
  rsync -Paq /install/custom/usr/share/ $RPOINT/usr/share
  text g "\n[+] Se copiaron archivos de configuracion carpeta SHARE\n"
  $CHR "chown -R root:root /usr/share"
  text g "\n[+] Permisos de /usr/share corregidos\n"
  sleep 1

  #Sincro etc
  rsync -Paq /install/custom/etc/ $RPOINT/etc
  text g "\n[+] Se copiaron archivos de configuracion carpeta ETC\n"
  $CHR "chown -R root:root /etc"
  text g "\n[+] Permisos de etc corregidos\n"
  sleep 1

  #Configurar y activar dnsCrypt
  $CHR "echo 'nameserver 127.0.0.1' > /etc/resolv.conf"
  $CHR "chattr +i /etc/resolv.conf"
  $CHR "sytemctl enable dnscrypt-proxy"
  text g "\n[+] DNSCRYPT configurado y activado\n"

  #Copiar oh-my-zsh a root
  rsync -Paq /install/custom/cbass/.oh-my-zsh $RPOINT/root/
  text g "\n[+] Se copiaron temas de zsh para root\n"
  $CHR "chown -R root:root /root/.oh-my-zsh"
  text g "\n[+] Permisos de oh-my-zsh corregidos\n"
  sleep 1
 
  #Compartir zshrc con root
  $CHR "ln -sf /home/$USR1/.zshrc /root"
  text g "\n[+] ZSHRC de usuario linkeado a root\n"
  sleep 1
  
  #Compartir configuracion de nano con root
  $CHR "ln -sf /home/$USR1/.nanorc /root"
  text g "\n[+] Se configuro nano para root\n"
  sleep 1

  #Copiar la config de neofetch de usr a root
  cp -f $RPOINT/home/$USR1/.config/Neofetch/config.conf $RPOINT/root/.config/Neofetch/config.conf
  text g "\n[+] Config de Neofetch para root\n"
  sleep 1

  text g "\n[+] Capa de personalizacion: instalacion finalizada\n"

#------------------[ UMOUNT AND REBOOT ]---------------------

  clockfor="[!] Desmontar y reiniciar en... "
  reverse_clock
  umount -R $RPOINT
  reboot


# If temp files found, delete em
[ -f $SYSSEL ] && rm $SYSSEL
[ -f $OUTPUT ] && rm $OUTPUT
[ -f $INPUT ] && rm $INPUT
