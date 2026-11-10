# Cómo se arman los instaladores

Los instaladores de Trabajito Motor (el `.exe` de Windows y el `.dmg` de Mac) los arma GitHub, no una
laptop. Lo hace el workflow [Armar instaladores](../.github/workflows/armar-instaladores.yml).

## Por qué aquí

- **Gratis.** GitHub no cobra las Actions de un repositorio público. En un repo privado saldrían de un
  crédito mensual de 12 USD, unos 190 minutos de Mac.
- **Mac sin tener una Mac.** GitHub presta Macs con Apple Silicon y con Intel para armar y probar el `.dmg`.
- **Siempre igual.** Cada instalador sale de un commit conocido, en una computadora limpia, y queda
  anotado de qué commit de trabajito-admin salió.

## De dónde sale el código

1. El código del motor está en `motor-whatsapp/` de trabajito-admin.
2. `bash ci/subir-codigo.sh <carpeta de trabajito-admin> [dev|main]` copia esa carpeta al repo
   **privado** `FreddyLeon02/trabajito-motor-codigo`:
   - copia solo los archivos versionados;
   - la deja en la rama del mismo nombre;
   - agrega `ORIGEN.txt`, que anota de qué commit salió;
   - si el repo no es privado, no sube nada.

   Hay que correrlo antes de armar, cada vez que cambie el motor.
3. El robot lee esa copia con una **llave de solo lectura**. La parte pública es una deploy key del
   repo privado y la parte privada es el secreto `CODIGO_MOTOR_SSH` de este repo. Se creó una sola vez
   con `bash ci/llave-codigo.sh`.

La URL y la clave **pública** de Supabase de cada entorno salen de la web publicada del superadmin. Así
el motor queda conectado a lo mismo que usa la web, y no hace falta guardar nada más.

**Ojo:** cualquiera con cuenta de GitHub puede ver los logs y los artefactos de este repo. El robot no
imprime el código ni las claves, y los artefactos (los instaladores recién armados y las capturas) se
borran al día.

## Cómo se usa

1. Si cambió el motor, corre primero `bash ci/subir-codigo.sh …`.
2. Entra a **Actions › Armar instaladores › Run workflow** y elige:
   - la rama (`dev` o `main`);
   - los entornos (PROD, DEV o los dos);
   - los sistemas;
   - si quieres **publicar**.
3. Mac y Windows se arman del mismo commit: lo fija el primer paso, «Fijar el commit del código». Después
   cada instalador se instala y se prueba (tabla de abajo).
4. Con «publicar», el robot sube a Releases los instaladores que falten, pero solo si pasaron:
   - el armado;
   - las pruebas automáticas del motor en macOS;
   - las pruebas en macOS 15, macOS 26 y macOS Intel;
   - la prueba en Windows Server 2025.

   La prueba en Windows 11 ARM es informativa y no frena nada. Además, el robot exige que estén todos
   los instaladores pedidos y que salieran del mismo commit. Al subir:
   - PROD va a la release `v<versión>`. Si no existe, la crea como **borrador**: nadie la ve ni cambia
     el enlace de descarga hasta que alguien la publique a mano. Si ya existe y es pública, lo que
     falte queda a la vista al instante, y la corrida lo avisa.
   - DEV va a la pre-release `dev`.
   - **Nunca reemplaza un archivo ya publicado.** Revisa que esté completo y avisa si no es el mismo
     que se acaba de probar. Para rearmar uno, primero hay que borrarlo de la release.

## Qué prueba en cada computadora

| Computadora | Instalador | Qué hace |
|---|---|---|
| macOS 15, Apple Silicon | `.dmg` | Lo arma. Después lo instala y lo prueba. |
| macOS 26, Apple Silicon | `.dmg` | Lo instala y lo prueba. |
| macOS 15, Intel | `.dmg` | Lo instala y lo prueba. |
| Windows Server 2025 | `.exe` | Lo arma. Después lo instala, lo prueba y lo desinstala. |
| Windows 11 ARM | `.exe` | Lo instala, lo prueba y lo desinstala. Es informativo: el `.exe` es x64 y ahí corre emulado. |

En cada computadora el robot:

1. instala el motor como lo haría una persona. En Mac copia la app del `.dmg` a Aplicaciones; en
   Windows corre el instalador por usuario;
2. revisa la versión, el enlace `trabajito-motor://` y que el motor traiga el Supabase de su entorno con
   solo la clave pública. En Windows revisa también «URL Protocol», que necesitan Chrome y Edge;
3. en Mac revisa además la firma, que el binario traiga los dos chips (Apple Silicon e Intel) y que App
   Nap esté apagado;
4. lo abre sin enlace, como desde Aplicaciones o el menú Inicio. Tiene que mostrar su ventana;
5. con el motor cerrado, abre `trabajito-motor://encender`, que es lo que hace «Encender mi motor» en
   la web. El motor tiene que arrancar con el Supabase de su entorno y atender el enlace;
6. con el motor abierto, abre el mismo enlace. Lo tiene que atender ese mismo motor, sin arrancar otro;
7. al cerrarlo, revisa `motor.log`. En Mac revisa además que macOS no haya registrado cierres inesperados.

## Qué no prueba

- El inicio de sesión con Google, el QR de WhatsApp y los envíos. Eso se prueba a mano con una persona.
- La pantalla con la que macOS frena la primera apertura. El robot solo anota qué responde Gatekeeper.
  La app está firmada ad hoc, no notarizada, así que la persona la abre desde Privacidad y seguridad
  («Abrir igualmente»).
- En Mac, «Encender» con la ventana cerrada: en una Mac de GitHub no se puede tocar el botón rojo. Lo
  cubre `scripts/mac/probar-motor.sh` del equipo, en una Mac de verdad.
