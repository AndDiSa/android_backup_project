

# android-backup-project

El proyecto android-backup proporciona un conjunto de scripts y herramientas para hacer copias de seguridad y/o restaurar aplicaciones instaladas en dispositivos Android.

Esto **no** es `adb backup`, que no funcionaba para mis requisitos ya que
* no hace copias de seguridad de las aplicaciones si estas solicitan no ser respaldadas
* no soporta la restauración en dispositivos diferentes de manera adecuada
* Google advierte que podría ser descontinuado en futuras versiones de Android
 
 
## Motivación

Nunca estuve realmente satisfecho con las posibilidades de hacer copias de seguridad / restaurar dispositivos Android. Especialmente cuando desarrollas con (diferentes) dispositivos Android, deseas poder transferir "configuraciones" de un dispositivo a otro. O te gustaría revertir a una versión anterior de una aplicación o ...

Lo mismo ocurre cuando cambias tu dispositivo "principal". El mecanismo de Google para configurar un dispositivo nuevo a partir de otro o desde una copia de seguridad funciona bastante bien, pero tiene casi las mismas deficiencias que `adb backup`: no restaura todas tus aplicaciones y datos.

Tampoco TWRP u otras implementaciones de recuperación personalizada ayudan realmente a salir de esta situación. Funciona bien para crear una copia de seguridad y restaurarla más tarde en el mismo dispositivo, pero no hay soporte para cambiar de dispositivo. Además, Android cambia con frecuencia de arquitectura, por lo que el soporte de TWRP para un dispositivo específico no está garantizado y, a la fecha de escritura, ni siquiera hay soporte de TWRP para Android 10.

Existe otro proyecto muy interesante relacionado con copias de seguridad y migración en XDA (https://forum.xda-developers.com/android/apps-games/app-migrate-custom-rom-migration-tool-t3862763). Desafortunadamente, también depende de TWRP y aún tiene algunos problemas por resolver.

Por último, pero no menos importante, está Titanium Backup, que lleva disponible mucho tiempo. Funciona bastante bien, pero la versión gratuita es muy limitada en funcionalidades y solo proporciona la posibilidad de almacenar la copia de seguridad en el mismo dispositivo, lo cual es una especie de contradicción para una copia de seguridad.

Hace tiempo ya inicié un proyecto similar (https://github.com/AndDiSa/ART) para gestionar copias de seguridad y restauraciones de dispositivos Android de forma remota. Desafortunadamente, nunca se terminó y, debido a los cambios arquitectónicos de Android, necesitaría una reconstrucción completa, por lo que decidí empezar de cero :-)


## Requisitos previos

* `adb` instalado y en la ruta de ejecución
* Ubuntu Linux (otras deberían funcionar también)
* paquete ``pv`` instalado: ```sudo apt install -y pv```


## Uso
Estos scripts básicamente hacen lo que hace TiBackup, pero controlando el proceso de copia de seguridad y restauración de forma remota.

### backup_apps.sh

./backup_apps.sh [--system-apps] [--user <ID|Name>]

Este script crea una copia de seguridad de todas las aplicaciones de usuario (y del sistema) y sus datos. Los archivos de copia de seguridad se almacenarán en un directorio creado recientemente, nombrado con el dispositivo y la fecha actual.

Si se especifica `--user`, hará una copia de seguridad de las aplicaciones del perfil de usuario indicado (por ejemplo, un Perfil de Trabajo). Puedes encontrar los IDs y nombres de usuarios ejecutando `adb shell pm list users`. Los valores comunes son `0` (Usuario Principal) o `Island` (si usas la aplicación Island para perfiles de trabajo).


### restore_apps.sh

./restore_apps.sh [<directory_name>] [--user <ID|Name>] [apps...]

Este script restaura las aplicaciones y sus datos de una copia de seguridad previa creada por `backup_apps.sh`
El directorio se identifica automáticamente por el dispositivo conectado y la fecha actual, o puedes pasar el nombre del directorio como parámetro. En ese caso, **todas** las aplicaciones y datos encontrados en el directorio indicado se restaurarán.

La bandera `--user` permite restaurar en un perfil de usuario específico. Si no se proporciona, el script intentará usar el ID/nombre de usuario guardado en los metadatos de la copia de seguridad, utilizando por defecto el Usuario 0 si no se encuentran metadatos.

Si solo deseas restaurar una parte de ellos, cópialos en un directorio diferente y pasa ese directorio como parámetro al script.

**Importante**

Ten en cuenta que restaurar todas las aplicaciones puede causar problemas, ya que algunas tienen IDs únicos que terminan generando conflictos si usas el mismo ID único en diferentes dispositivos.

También podrías considerar restaurar solo las aplicaciones que no están disponibles en Google Play o aquellas que, por desgracia, deciden impedir las copias de seguridad de sus datos (es decir, los tuyos).


### restore_splitted_apps.sh

./restore_splitted_apps.sh [<directory_name>] [--user <ID|Name>] [apps...]

Este script funciona como `restore_apps.sh` pero utiliza un método de instalación diferente. La restauración con `pm install` / `pm install-multiple` a veces lleva a un proceso que se queda colgado (especialmente cuando se debe restaurar una aplicación multi-APK). En esos casos, toda la restauración queda bloqueada y solo puedes terminar el proceso, por lo que la restauración falla.

Este script utiliza un método de instalación basado en transacciones para la restauración. También soporta la bandera `--user` para la restauración en Perfiles de Trabajo.


### restore_one_splitted_app.sh

./restore_one_splitted_app.sh <directory_name> [--user <ID|Name>] <app-tar-gz>

Este script se utiliza para restaurar una sola aplicación usando el método de instalación basado en transacciones. Es útil cuando solo deseas restaurar una aplicación específica desde un directorio de copia de seguridad grande.

Ejemplo: `./restore_one_splitted_app.sh sargo_backup --user Island app_com.example.tar.gz`


### full-backup.sh

./full-backup.sh [--data-backup][--no-data-backup][--media-backup][--no-media-backup][--image-backup][--no-image-backup] [--graceful]

Este script realiza una copia de seguridad completa de (diferentes partes de) la partición `/data`. Hay varias opciones para controlar el comportamiento.

`--data-backup` hará una copia de seguridad de `/data` sin `/data/media` y `/data/mediadrm`

`--media-backup` hará una copia de seguridad de `/data/media` y `/data/mediadrm`

`--image-backup` hará una copia de seguridad de toda la partición montada como `/data` como una copia 1:1

`--graceful` no detendrá el framework de Android, sino que forzará la parada de todas las aplicaciones. Esto se recomienda para copias de seguridad a nivel de archivo (tar) para evitar problemas con las claves de cifrado que se pierden en algunos dispositivos.

Dado que no se puede garantizar que durante el proceso de copia de seguridad no haya ninguna modificación en la partición `/data`, es bastante común obtener un error de validación de suma de verificación una vez finalizada la copia.


### Nota importante sobre cifrado (FBE)

Los dispositivos Android modernos utilizan **Cifrado Basado en Archivos (FBE)**. Esto tiene implicaciones significativas para las copias de seguridad:

1. **Copias de seguridad de partición (`--image-backup`)**: Estas son copias crudas a nivel de bloques (cifrado). Debido a que las claves de cifrado están vinculadas al hardware del dispositivo (TEE/SE), una imagen de partición de `/data` **no es portátil** y solo puede restaurarse en el dispositivo exacto.
2. **Parada del Framework**: Detener el entorno de ejecución de Android (`stop`) a veces puede provocar que el kernel purgue las claves de cifrado de la memoria. Si esto ocurre, las copias de seguridad a nivel de archivo (`tar`) fallarán. Usa la bandera `--graceful` para mantener el framework en ejecución mientras se detienen las aplicaciones, asegurando que las claves permanezcan disponibles.


### full-restore.sh

./full-restore.sh [--data-backup][--no-data-backup][--media-backup][--no-media-backup][--image-backup][--no-image-backup] <directory_name>

Este script restaura datos creados previamente por `full-backup.sh`
Acepta los mismos parámetros que `full-backup.sh` y, además, toma el nombre del directorio desde donde se debe restaurar la copia de seguridad.


**Importante**

Ten **mucha** precaución al usar este método, especialmente cuando estés restaurando `/data`
Sobrescribirá todo en la partición `/data` y esto puede causar problemas graves hasta el punto de que tu dispositivo deje de ser utilizable. En ese caso, probablemente necesitarás hacer un borrado completo (wipe) para volver a hacerlo funcionar.


### Agradecimientos especiales
Los créditos van a Raphael Moll, quien inició un proyecto similar hace tiempo, y a Marc Merlin, quien lo mejoró para que funcionara con Android O. Tomé algunas ideas e inspiración de estos proyectos y de mi primer intento que comencé hace años. La implementación actual no tiene mucho en común con ninguna de esas versiones.

Especialmente, quiero agradecer a topjohnwu por su excelente proyecto Magisk y a osmOsis por su gran colección de scripts y herramientas.
