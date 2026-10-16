<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.zh-TW.md">繁體中文</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.es.md"><strong>Español</strong></a>
</p>

# UsageDock

UsageDock es una barra ligera para el borde de la pantalla en macOS que permite consultar de un vistazo el uso de servicios de IA y sus tiempos de reinicio, sin necesidad de abrir un panel completo.

## Demostración en movimiento

<a href="https://drive.google.com/file/d/1I1TLPKhvvgevAjZ8R0ceHMxTLhVdE_f0/preview">
  <img src="docs/images/usagedock-rail.png" alt="Ver la demostración del arrastre líquido de UsageDock" width="763">
</a>

**▶ [Ver la demostración de UsageDock](https://drive.google.com/file/d/1I1TLPKhvvgevAjZ8R0ceHMxTLhVdE_f0/preview)**

## Vista previa

### Barra lateral

<img src="docs/images/usagedock-rail.png" alt="Barra lateral de UsageDock mostrando uso de IA" width="763">

### Ajustes

<img src="docs/images/usagedock-settings.png" alt="Ventana de ajustes de UsageDock" width="900">

## Funciones principales

- Muestra el uso por proveedor y cuenta en una barra compacta junto al borde de la pantalla.
- Permite seleccionar hasta tres cuentas para la barra y configurar por separado las cuentas del menú de macOS.
- Muestra anillos, porcentajes, tiempos de reinicio, colores por proveedor/cuenta y fuentes de cuota configurables.
- Incluye colocación en el borde izquierdo o derecho, controles de diseño y borde, materiales, gotas y una interacción de arrastre elástico con aspecto líquido.
- Ofrece un elemento compacto en la barra de menús de macOS con un panel emergente para las cuentas seleccionadas.
- Conserva la apariencia, la posición, las cuentas visibles y las preferencias del menú tras reiniciar.

## Destino al hacer clic

En **Settings → Data → Provider Order, Colors & Click Targets**, elige **App (predeterminado)** o **Link** por proveedor. **Choose App…** permite seleccionar una app en ejecución o un archivo `.app` con el selector de Finder, que comienza en `/Applications`. Se muestran el nombre y el icono, y la selección persiste tras reiniciar. La barra lateral, los menús de cuenta y las filas de cuentas de la barra de menús comparten el destino.

Las apps predeterminadas, si están instaladas, son Claude.app, ChatGPT.app para Codex, Antigravity.app, Kimi Code.app, Cursor.app y Grok Bot.app para Grok. Si la app no existe o no se inicia, se abre la URL alternativa editable y aparece un estado en los ajustes y en la ayuda del clic. La URL de la cuenta tiene prioridad; las URL vacías o inválidas usan una URL válida del proveedor. **Use Default App / Use Default URL** restaura los valores originales. Elegir una app no cambia la política de cuentas con inicio de sesión.

## Política de cuentas

UsageDock es **solo para cuentas autenticadas mediante inicio de sesión**.

- Claude, Codex, Antigravity, Kimi y Grok pueden registrarse mediante flujos compatibles de inicio de sesión o sesión autenticada.
- Cursor no está disponible hasta que UsageDock disponga de un inicio de sesión verificado y una integración de uso en tiempo real para ese proveedor.
- Las cuentas que no procedan de un inicio de sesión autenticado compatible quedan fuera del conjunto de cuentas activas.

Grok tiene dos inicios de sesión. **Sign in on grok.com** abre una ventana dentro de la app en `https://grok.com/?_s=usage`. Esa sesión permanece en un almacén web aislado por cuenta y es la fuente del porcentaje semanal y del reinicio que muestra Settings → Usage en grok.com. **Use Current Login** y **Login New Profile** siguen usando `grok login`. Si la sesión web falta, caduca o la respuesta no se puede decodificar, UsageDock muestra la lectura de facturación de la CLI e indica que hay que volver a entrar en la web. Una respuesta web ilegible no se convierte en 0%. Las cookies y los tokens no se copian a los ajustes de UsageDock. Copy diagnostics copia solo las rutas de campos decodificadas.

## Requisitos

- macOS 14 o posterior
- Se recomienda Xcode 16+

## Compilación

Release:

```bash
xcodebuild \
  -project UsageDock.xcodeproj \
  -scheme UsageDock \
  -configuration Release \
  -derivedDataPath DerivedDataRelease \
  build
```

Debug:

```bash
xcodebuild \
  -project UsageDock.xcodeproj \
  -scheme UsageDock \
  -configuration Debug \
  -derivedDataPath DerivedData \
  build
```

## Registro de cuentas

Abre **Settings → Accounts** y utiliza los controles de inicio de sesión del proveedor. UsageDock solo registra fuentes compatibles procedentes de un inicio de sesión o sesión autenticada.

## Estructura del proyecto

- `UsageDock/Domain` — modelos de uso, agregación y runtime de movimiento de la barra
- `UsageDock/Providers` — adaptadores de proveedores e integraciones de uso en tiempo real
- `UsageDock/Storage` — persistencia de ajustes y estado de cuentas
- `UsageDock/UI` — interfaz de la barra y de los ajustes
- `UsageDock/Window` — integración de paneles y ventanas con AppKit
- `UsageDockTests` — pruebas unitarias y de comportamiento

Consulta [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) para obtener más detalles de implementación.
