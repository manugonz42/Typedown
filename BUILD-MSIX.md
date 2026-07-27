# Compilación del MSIX en local (Windows)

Notas de cómo compilar **Typedown** a un paquete **MSIX** en una máquina Windows
moderna (Windows 11), reproduciendo lo que hace el workflow de CI
(`.github/workflows/build-and-release.yml`) pero en local.

El proyecto está pensado para un toolchain **EOL** (`.NET Core 3.1` +
`Windows SDK 10.0.22000`), por lo que en una máquina actual (que trae .NET 8/9 y
SDKs de Windows más nuevos) hacen falta varios ajustes. Todo lo necesario está
documentado abajo.

> Resultado: `Tools/Typedown.Package/AppPackages/Typedown.Package_1.2.18.0_x64_Test/Typedown.Package_1.2.18.0_x64.msix` (~72 MB, sin firmar).

---

## 1. Requisitos (software a instalar)

| Componente | Uso | Cómo instalar |
|---|---|---|
| **Node.js 18+ y Yarn** | Compilar el editor React (`Dev/Typedown.Editor`) | `winget install OpenJS.NodeJS.LTS` + `npm i -g yarn` |
| **Visual Studio 2022 Build Tools** con los workloads:<br>• `Microsoft.VisualStudio.Workload.ManagedDesktopBuildTools`<br>• `Microsoft.VisualStudio.Workload.UniversalBuildTools`<br>• componente `Microsoft.VisualStudio.ComponentGroup.MSIX.Packaging` | MSBuild + targets WPF/UWP + empaquetado MSIX (DesktopBridge) | Instalador de VS Build Tools (ver comando abajo) |
| **.NET Core 3.1 SDK** | El grafo de RID de .NET Core 3.1 (`win-x64`) para el WPF host | `winget install Microsoft.DotNet.SDK.3_1` |
| **Windows SDK 10.0.22000** | *TargetPlatformVersion* del proyecto UWP | `winget install Microsoft.WindowsSDK.10.0.22000` |
| **Windows SDK 10.0.18362** | *TargetPlatformMinVersion* — el resolutor UWP busca la *union metadata* (`Windows.winmd`) en la versión **mínima** | `winget install Microsoft.WindowsSDK.10.0.18362` |

Comando para añadir los workloads a un VS Build Tools ya instalado (requiere admin / UAC):

```powershell
& "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe" `
  modify --installPath "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools" `
  --add Microsoft.VisualStudio.Workload.ManagedDesktopBuildTools `
  --add Microsoft.VisualStudio.Workload.UniversalBuildTools `
  --add Microsoft.VisualStudio.ComponentGroup.MSIX.Packaging `
  --includeRecommended --passive --norestart
```

> ⚠️ Si pasas la ruta con espacios a `setup.exe`, **entrecomíllala**. Con
> `Start-Process -ArgumentList` en Windows PowerShell 5.1, un array no
> entrecomilla los elementos y `--installPath C:\Program Files...` se corta en
> `C:\Program`, dejando el instalador sin hacer nada (sale en ~2 s).

---

## 2. Modificaciones hechas al proyecto

Solo se tocó **`Dev/Typedown/Typedown.csproj`** (2 cambios). Todo lo demás son
argumentos de MSBuild / variables de entorno (ver script), no cambios de código.

1. **RID `win10-x64` → `win-x64`** (y `win10-x86` → `win-x86`).
   El .NET SDK 9 usa el grafo de RID portable; `win10-x64` ya no existe y el
   build fallaba con `NETSDK1047` («no target for netcoreapp3.1/win-x64»).
   Con `.NET Core 3.1 SDK` fijado esto también funciona con `win-x64`.

2. **`Link` de los `Statics`: se elimina un backslash duplicado.**
   ```diff
   - Link="Resources\Statics\%(RecursiveDir)\%(Filename)%(Extension)"
   + Link="Resources\Statics\%(RecursiveDir)%(Filename)%(Extension)"
   ```
   `%(RecursiveDir)` ya termina en `\`, así que el original generaba rutas con
   `...\media\\open-sans...` (segmento vacío). MakeAppx rechaza ese nombre con
   `error 0x8007007b` (ERROR_INVALID_NAME) y no crea el paquete.

*(Durante la investigación se probó a fijar el SDK con `global.json` y a
retargetear el `TargetPlatformVersion` a 26100; ambos se revirtieron por
innecesarios/contraproducentes.)*

---

## 3. Gotchas clave (por qué el build fallaba)

- **`VisualStudioVersion` vacío** → los targets UWP XAML
  (`...\WindowsXaml\v$(VisualStudioVersion)\Microsoft.Windows.UI.Xaml.CSharp.targets`)
  no se importan y no se añade ninguna referencia de plataforma. **Solución:**
  `-p:VisualStudioVersion=17.0` (y/o `$env:VisualStudioVersion="17.0"`).
- **Windows SDK 18362 ausente** → el compilador no recibe `Windows.winmd` y
  fallan ~1200 tipos UWP (`Windows.UI.Xaml.*`, `Windows.Storage`, …). El
  resolutor busca el SDK en la **MinVersion (18362)**, no en la target (22000).
- **`MSB4044` en `Microsoft.VCRTForwarders.140.targets`** al compilar solo el
  `.wapproj` (sin contexto de solución, la metadata `Configuration` de las
  ProjectReferences queda vacía). **Solución:** `-p:VCRTForwarders-IncludeDebugCRT=false`
  (salta la tarea `UseDebugCRT`; en Release no se quiere el CRT debug igualmente).
- **No compiles la solución completa**: `Tools/XamlDesignApp` (UWP) dispara la
  compilación **.NET Native (AOT)**, lentísima (10+ min) y no necesaria para el
  MSIX. Compila solo el `.wapproj`, que arrastra `Typedown` → `Typedown.Core`.

---

## 4. Paso a paso

```powershell
# --- 1) Editor React -> se despliega en Dev/Typedown/Resources/Statics ---
cd Dev/Typedown.Editor
$env:CI = "false"
yarn install
yarn build
cd ../..

# --- 2) Build + empaquetado MSIX ---
./build-msix.ps1
```

`build-msix.ps1` (incluido en el repo) localiza MSBuild con `vswhere`, restaura
y compila/empaqueta solo el `.wapproj` con todos los flags necesarios.

El MSIX queda en:
```
Tools/Typedown.Package/AppPackages/Typedown.Package_1.2.18.0_x64_Test/Typedown.Package_1.2.18.0_x64.msix
```

> El paquete se genera **sin firmar** (`AppxPackageSigningEnabled=false`). Para
> instalarlo hay que firmarlo con un certificado de confianza (o habilitar el
> modo desarrollador y usar un certificado de prueba).

---

## 5. Entorno verificado

- Windows 11 (10.0.26200)
- VS 2022 Build Tools 17.14
- .NET SDK: 3.1.426 (para netcoreapp3.1) y 9.0.316 (infra del `.wapproj`)
- Windows SDK: 10.0.18362, 10.0.22000 (+ 10.0.26100 preexistente)
- Node 24 / Yarn 4
