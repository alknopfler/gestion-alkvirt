#!/bin/bash

# script para automatizar algunas tareas de creación de vm en libvirt
# autor: Alknopfler
#
##########################################################

##########################
### Variables Globales ###
##########################

BASEDIR=/home/alknopfler/alkvirt
CONFDIR=$BASEDIR/config
METADIR=$BASEDIR/metadata
TEMPDIR=$BASEDIR/templates
IMAGDIR=$BASEDIR/alkvirt-images

##########################
###### Funciones #########
##########################


function resize(){

# Funcion para hacer un resize de una instancia existente
	qemu-img resize $IMAGDIR/$1.img +$2
}


function create-iso(){

# Funcion para generar el archivo ISO 
# con los valores metadata y userdata de cloud-init
# La forma de hacerlo es añadiendo un cdrom en la 
# creación de la imagen
	# vamos a generar el hostname con el nombre de la maquina
        echo "local-hostname: $1" > $METADIR/meta-data
	
	genisoimage -output $METADIR/$1.iso -volid cidata -joliet -rock $METADIR/$2/user-data $METADIR/meta-data
	chmod 777 $METADIR/$1.iso
}




function remove-iso(){

# Funcion que elimina el archivo ISO generado
# con los valores de metadata y userdate de 
# cloud init

        # vamos a generar el hostname con el nombre de la maquina
        rm $METADIR/meta-data

        rm $METADIR/$1.iso 

}
function update-vol(){
	virsh pool-refresh virtimages
        virsh pool-refresh templates
        virsh pool-refresh metadata
	
}
function clone-img(){
# Funcion para clonar una imagen y convertirla en maquina virtual
                ssoo=$1
                tipo=$2
                nombre="$1-vm"
                imagen=`cat $CONFDIR/ssoo.ini | grep $ssoo | awk -F"|" '{print $3}' -`
                memoria=`cat $CONFDIR/config.ini | grep $tipo | awk -F"|" '{print $2}' -`
                cpu=`cat $CONFDIR/config.ini | grep $tipo | awk -F"|" '{print $3}' -`
                ifce=`cat $CONFDIR/config.ini | grep $tipo | awk -F"|" '{print $4}' -`

                if [ ! `grep $ssoo $CONFDIR/ssoo.ini` ]; then
                        echo "No existe el sistema operativo que ha proporcionado" 
                        exit
                fi
                if [ ! `grep $tipo $CONFDIR/config.ini` ]; then
                        echo "No existe el tipo de maquina que ha proporcionado"
                        exit
                fi

                        virsh vol-clone --pool templates $imagen $nombre.img
			if [ -f $TEMPDIR/$nombre.img ]; then
                                # una vez clonado, movemos al directorio de imagenes y actualizamos
                                mv $TEMPDIR/$nombre.img $IMAGDIR/$nombre.img
                                virsh pool-refresh virtimages
                                virsh pool-refresh templates

				virt-install -r $memoria -n $nombre --vcpus=$cpu --autostart --force  --network network=$ifce --boot hd --disk vol=virtimages/$nombre.img,format=qcow2,bus=virtio  &
                        else
                                echo "Error...No se ha clonado el template. Saliendo!"
                                exit 1
                        fi



}


function create-vm(){

# Funcion para generar una nueva maquina virtual
# en libvirt desde cero con metadata  y con la posibilidad de modificar:
		ssoo=$1
        	tipo=$2
		resize=$3
		nombre=`shuf -n 1 $CONFDIR/servernames.ini`
		imagen=`cat $CONFDIR/ssoo.ini | grep $ssoo | awk -F"|" '{print $3}' -`
		memoria=`cat $CONFDIR/config.ini | grep $tipo | awk -F"|" '{print $2}' -`
		cpu=`cat $CONFDIR/config.ini | grep $tipo | awk -F"|" '{print $3}' -`
		ifce=`cat $CONFDIR/config.ini | grep $tipo | awk -F"|" '{print $4}' -`
	
		if [ ! `grep $ssoo $CONFDIR/ssoo.ini` ]; then
			echo "No existe el sistema operativo que ha proporcionado" 
			exit
		fi	
		if [ ! `grep $tipo $CONFDIR/config.ini` ]; then
			echo "No existe el tipo de maquina que ha proporcionado"
			exit
		fi	
		
                        virsh vol-clone --pool templates $imagen $nombre.img  
		
			if [ -f $TEMPDIR/$nombre.img ]; then
				# una vez clonado, movemos al directorio de imagenes y actualizamos
				mv $TEMPDIR/$nombre.img $IMAGDIR/$nombre.img

				if [ ! -z $3 ];then
        	                        resize $nombre $3
	                        fi


				virsh pool-refresh virtimages
				virsh pool-refresh templates
		
				# ahora instanciamos la vm con el volumen creado y el fichero de metadata cloud init pasado como cdrom
				create-iso $nombre $ssoo 
				virsh pool-refresh metadata

				virt-install -r $memoria -n $nombre --vcpus=$cpu --autostart --force  --network bridge=$ifce --boot hd --disk vol=virtimages/$nombre.img,format=qcow2,bus=virtio --disk vol=metadata/$nombre.iso,bus=virtio &			
			else
				echo "Error...No se ha clonado el template. Saliendo!"
				exit 1
			fi

}

function remove-vm (){
	if [ -z $1 ]; then
		echo "Error...No se puede borrar si no se especifica el nombre de vm"
		exit 1
	else
		#parando la instancia
		virsh destroy $1
		#borrando la instancia
		virsh undefine $1
		# borrando el volumen
		virsh vol-delete --pool virtimages $1.img
		rm $IMAGDIR/$1.img
	
		remove-iso $1	
		# mostramos el resultado again
		virsh list
	fi
}

function parar-vm(){
        if [ -z $1 ]; then
                echo "Error...No se puede parar si no se especifica el nombre de vm"
                exit 1
        else
		virsh destroy $1
	fi
}

function arrancar-vm(){
        if [ -z $1 ]; then
                echo "Error...No se puede arrancar si no se especifica el nombre de vm"
                exit 1
        else
                virsh start $1
        fi
}

#############################
##### Main program   ########
#############################

if [ $EUID -ne 0 ];then
	echo "El script debe ser ejecutado por Root"
	exit 1
else 
  case $1 in
	create|-c)
		# create vm param: SSOO TIPO-VM
		create-vm $2 $3 $4 ;;
	destroy|-d)
		# remove vm param: nombre
		remove-vm $2 ;;
	list|-l)
		virsh list 
		echo "Listado de IPs: "
		nmap -sP 192.168.2.0/24 | grep "Nmap" | grep -v "Starting" | grep -v "done"  | grep -v "192.168.2.70" | grep -v "192.168.2.67" | awk '{ print "  - " $5 }' - 
		echo ;;
	clone)
		# # create vm param: SSOO TIPO-VM
		clone-img $2 $3 ;; 
	update|-u)
		# update param: none
		update-vol ;; 
	metadata|-m)
		# create metadata param: nombre SSOO
		create-iso $2 $3 ;;
	resize|-r)
		# resize param: nombre Gigas
		resize $2 $3;;
	on)
		# arrancar una instancia
		arrancar-vm $2;;
	off)
                # arrancar una instancia
                parar-vm $2;;

	help|-h)
		echo "USO: gestion-alkvirt.sh OPCIONES PARAMETROS"
		echo "     OPCIONES:"
		echo "        - create|-c:  crear nueva instancia"
		echo "                    PARAMETROS:"
		echo "                        - SSOO {ubuntu|centos|fedora|cirros}"
		echo "                        - TIPO {small|medium|high}"
		echo "                        - SIZE {opcional ej. 20G }"
		echo "        - destroy|-d: borrar una instancia existente"
		echo "                    PARAMETROS:"
		echo "                        - NOMBRE"
		echo "        - list|-l:    listar las instancias"
		echo "                    PARAMETROS:"
		echo "                        None"
		echo "        - update|-u:  actualizar los directory pool"
		echo "                    PARAMETROS:"
		echo "                        None"
		echo "        - metadata|-m: crear un archivo metadata para una instancia"
		echo "                    PARAMETROS:"
		echo "                        - NOMBRE"
		echo "                        - SSOO" 
		echo "        - resize|-r: Aumentar en X Gigas el disco de una instancia"
		echo "                    PARAMETROS:"
		echo "                        - NOMBRE"
		echo "                        - Gigas ( XG hayque añadir la G)"
		echo "        - on: Arrancar una instancia"
		echo "                    PARAMETROS:"
		echo "                        - NOMBRE"
		echo "        - off: Parar una instancia"
                echo "                    PARAMETROS:"
                echo "                        - NOMBRE"
		;;
	*) echo "Error...Opcion no contemplada. USO: gestion-alkvirt.sh help|-h para ver opciones " ;;

  esac
fi
