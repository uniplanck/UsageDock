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

## Política de cuentas

UsageDock es **solo para cuentas autenticadas mediante inicio de sesión**.

- Claude, Codex, Antigravity y Kimi pueden registrarse mediante flujos compatibles de inicio de sesión o sesión autenticada.
- Cursor y Grok no están disponibles hasta que UsageDock disponga de un inicio de sesión verificado y una integración de uso en tiempo real para esos proveedores.
- Las cuentas que no procedan de un inicio de sesión autenticado compatible quedan fuera del conjunto de cuentas activas.

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
