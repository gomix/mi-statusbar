#!/usr/bin/ruby 
# encoding: UTF-8
# Incluir fecha/hora, estado de la batería y temperatura en statusbar dwm Fedora 18
# Requerimientos externos
#             acpi
#             osd_cat (xosd)
#             dunst (* en realidad debe funcionar con cualquier servidor de notificadiones)
#             pidfile (gem)
#             feh
#
#
# Guillermo Gómez Savino. (Gomix) 2013
# Script para mi DWM, "Barra de estado"
#  1. Reloj (fecha/hora)
#  2. Temperatura
#  3. Bateria  
#  4. Red
#  5. Fondo del escritorio (wallpaper)

# TODO: Nuevas funcionalidades
# 1. Cambiar notificaciones a dunst, iniciar servidor de notificaciones de ser necesario.
#  ** Ya código arreglado, falta probar.
# 2. Establecer el mapa de teclado
# 3. Crear archivo pid, para evitar múltiples instancias
# 4. Incorporar hilos Ruby
# 5. Conexion de red, monitor
# 6. Establecer fondo de escritorio
## La idea de tener los tres hilos (en realidad uno por ahora), es no detener
## la salida del programa, por ejemplo, esperando que se conecte
## el cargador AC para evitar que hiberne o suspenda la maquina

######################### Configuracion
HIBERNAR='hibrido'          # [hibernar, suspender, hibrido]
UMBRAL_CARGA=10             # Umbral de comparación para suspender/hibernar
UMBRAL_TEMPERATURA=58       # Umbral de comparación para suspender/hibernar
T_MUESTREO=10               # Tiempo de muestreo para el lazo principal del  programa en segundos
PIDDIR="/home/gomix/tmp"
PIDFILE="mi-statusbar2.pid"

######################## Dependencias
# gems
require 'daemons'
require 'pidfile'

begin
  ##PidFile.new(:piddir => PIDDIR, :pidfile => PIDFILE)
rescue PidFile::DuplicateProcessError
  # Muestras excepción
  #  PidFile::DuplicateProcessError: Process (irb - 7793) is already running.
  ##`notify-send "mi-statusbar ya está en ejecución"`
  ##exit
  # Una opción es recargar el programa pero no es la forma adecuada
  # Prefiero que se señalice al programa para que este se reinicie
end

# Colores ANSI
redfg = '\x1b[38;5;196m' #hex
redbg = '\033[48;5;196m' #octal
blackbg = '\x1b[48;5;16m' #hexadecimal
reset = '\x1b[0m'

################################## Energía Batería/Energía
def hibernar
  # Tengo problemas al ejecutar
  #`dbus-send --print-reply --system --dest=org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower.Hibernate`
  `systemctl hibernate`
end

def suspender
  # Tengo problemas al ejecutar
  #`dbus-send --print-reply --system --dest=org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower.Suspend`
  `systemctl suspend`
end

def suspender_hibrido
  `systemctl hybrid-sleep`
end

def hibernar_o_suspender
  # Mientras se mantenga la carga por debajo del umbral
  if battery_charge.to_i.abs < UMBRAL_CARGA
    to = 0
    while discharging?
      # Lazo de espera por puesta a cargar por 30 segundos
      notificar_bateria_baja
      sleep 1
      to += 1
      break if to == 30
    end
  end

  if battery_charge.to_i.abs < UMBRAL_CARGA and discharging?
    case HIBERNAR
    when 'hibernar'
      notificar_hibernando_o_suspendiendo("Hibernando")
      hibernar
    when 'suspender'
      notificar_hibernando_o_suspendiendo("Suspendiendo")
      suspender
    when 'hibrido'
      notificar_hibernando_o_suspendiendo("Suspendiendo (híbrido)")
      suspender_hibrido
    else
      puts "error"
    end
  end
end

def notificar_hibernando_o_suspendiendo(msg)
  `notify-send "#{msg}"`
  #`echo "#{msg}" |osd_cat -p middle -A center --text="HELLO" -s 2 -f -adobe-helvetica-bold-*-*-*-34-*-*-*-*-*-*-*`

  # La espera es para que de hecho haya cierta pausa y se vea la notificación
  sleep 2
end
  
def notificar_bateria_baja
  if battery_charge.to_i.abs < UMBRAL_CARGA
    `notify-send "Batería baja, #{battery_charge.to_i.abs}, conecta tu cargador"`
    #`echo "Batería baja, #{battery_charge.to_i.abs}% conecta tu cargador" |osd_cat -p middle -A center -s 1 -f -adobe-helvetica-bold-*-*-*-34-*-*-*-*-*-*-*`
  end
end

def discharging?
  true if `acpi -b`.match(/discharging/i)
end

def charging?
  !discharging?
end

def battery_charge
  # Returns String +|-integer% wherre integer [0,100], sample +33%
  charge = `acpi -b`                            # Captura de datos del sistema
  sign = '+'                                    # Asumo conectado a AC
  sign = '-' if discharging?                    # Cambio a - si se está descargando la batería
  sign + charge.match(/\d{1,3}%/).to_s          # Calculo del string a presentar
end

def colored_battery_charge
  # coloreado ansi para dwm
  battery_charge
end

def bateria
  notificar_bateria_baja if discharging?        # Notificar si la batería está baja
  hibernar_o_suspender if discharging?          # Poner a dormir si hace falta
  colored_battery_charge
end

################################## Temperatura
def notificar_alta_temperatura
  t = `acpi -t`.split(',').last.split.first.to_i      # Captura de y ajuste de datos del sistema

  if t > 75
    `notify-send "Alta temperatura: #{t}, guarda tu trabajo"`
    #`echo "Alta temperatura: #{t}, guarda tu trabajo" |osd_cat -p middle -A center -s 1 -f -adobe-helvetica-bold-*-*-*-34-*-*-*-*-*-*-*`
  end
end

def temperatura
  #temperatura = `acpi -t`                                                  # Captura de datos del sistema
  #temperatura = temperatura.split(',').last.split.first + 'º'              # Calculo del string a presentar temperatura
  notificar_alta_temperatura                    # Vigilar temperatura
  `acpi -t`.split(',').last.split.first + 'º'   # Calculo del string a presentar temperatura
end

################################## Red
def red_activa?
  # ¿Está el servicio de red activo? (¿Base NetworkManager?)
  # Hay que determinar el API a consultar o interfase kernel
  # Idealmente debería ser a nivel kernel
  # "Red Activada"
  # Como por ahora sigo con NM, me baso en él
  # Básicamente entonces lo que necesito es saber si NM está en ejecución
  # systemctl status NetworkManager.service
  `systemctl status NetworkManager.service`
  $?.exitstatus.eql?(0) ? true:false
end

def red_interfase_activa
  `nmcli -t -f name con show --active`.chomp
end

def conectividad_ip?
  # ¿Tengo IP?
  # ¿Tengo interfase de red configurada y activa?
  # ¿Estoy conectado a una red pública o privada?
  #nm-online
  #nmcli con show active (determinar nombre/uuid de la interfase activa)
  #nmcli con show active <uuid> me ofrece detalles
end

def ping_internet?
  # ¿Hago ping a una dirección prestablecida?
end

def resuelvo_nombres?
  # ¿Resuelvo nombres DNS?
end

def acceso_web?
  # ¿ping http a sitio altamente disponible?
  # Definir un arreglo, basta que uno responda
end

def reconectarse_a_la_red
  # Intentar reconectar la última interfase conocida que funcionó o que esté disponible
  # ¿Red cablead, enlace?
  # ¿Red inalámbrica, AP disponible?
end

def red
  red_activa? ? "+net(#{red_interfase_activa})" : "-net(#{red_interfase_activa})"                                    # Calculo del string a presenta para red 
end

################################## Fondo del escritorio
def poner_el_fondo_de_escritorio
  fondo_de_escritorio if es_hora_de_poner_el_fondo_de_escritorio
end

def es_hora_de_poner_el_fondo_de_escritorio
  # Por ahora cada 5 minutos es la intención, no funciona bien 
  # aún porque evaluar los minutos cada 10 segundos, da lo mismo 
  # que pintar cada 10 segundos durante ese "minuto" (hasta 6 cambios por minutos)
  [0,5,10,14,15,16,20,25,30,35,40,45,50,55].include?(Time.now.min)
end

def fondo_de_escritorio
  # Para poder cambiar, o lo hago aleatoriamente, o debo poder recordar .. por ahora aleatorio
  `feh --bg-fill #{seleccionar_fondo_de_escritorio}`
end

def seleccionar_fondo_de_escritorio
  fondo_de_escritorio_aleatorio
end

def fondo_de_escritorio_aleatorio
  Dir.chdir("/home/gomix/Imágenes/WallPapers/statusbar")
  imgs = Dir.glob("*.*").map(&File.method(:realpath))
  imgs[rand(imgs.size)]
end

################################## Fecha hora
def fecha_hora
  Time.now.strftime("%I:%M%P %a %e %b")                         # Calculo del string a presentar fecha/hora
end

################################## Barra de estado
def mostrar_barra_de_estado
  `xsetroot -name "#{fecha_hora} #{bateria} #{temperatura} #{red} #{dwm_version}"`        # Mostrar en la barra de estado
end

def dormir
  sleep T_MUESTREO
end

def dwm_version
  `dwm -v 2>&1`.split(',').first
end

################################## Demonio
# Opciones de configuración para el demonio
# TODO: 
#  * Ajustar :dir para que expanda a partir del HOME del entorno
#   * El proceso sigue corriendo fuera del entorno gráfico, debe salir
options = {
  :app_name => "statusbar",
  :dir_mode => :normal,
  :dir => "/home/gomix/tmp/pids/",
  :log_output => true,
  :ontop => false 
 }

# Poner el fondo de escritorio no debe esperar su hora al inicio del programa
  fondo_de_escritorio

# Definición del lazo principal de la aplicación
main = Proc.new {
loop do
  poner_el_fondo_de_escritorio
  mostrar_barra_de_estado
  dormir
end
}

# Arranque del demonio (incluye desconexión del terminal de control)
Daemons.call(options, &main)
