# Guía de instalación de Typedown

Typedown es una aplicación WinUI empaquetada como MSIX. Hay tres formas de instalarla, ordenadas de más simple a más manual.

## Requisitos

- Windows 10 versión 1809 (build 17763) o superior, o Windows 11
- Arquitectura x64 (los paquetes publicados en Releases se compilan solo para x64)

Para comprobar tu versión: `Win + R` → `winver`.

---

## Opción 1 — Microsoft Store (recomendada)

Es la vía más sencilla: el paquete viene firmado y las actualizaciones son automáticas.

[Descargar desde la Microsoft Store](https://apps.microsoft.com/detail/9p8tcw4h2hb4)

O desde PowerShell:

```powershell
winget install --id 9P8TCW4H2HB4 --source msstore
```

---

## Opción 2 — MSIX desde GitHub Releases (sideload)

Los paquetes de la sección [Releases](https://github.com/manugonz42/Typedown/releases) los genera el workflow de CI, que compila **sin firmar** (`AppxPackageSigningEnabled=false`). Windows no instala un MSIX sin firma, así que hay que firmarlo con un certificado propio y confiar en él. Es un proceso de una sola vez.

### 2.1 Habilitar la instalación de aplicaciones externas

`Configuración` → `Privacidad y seguridad` → `Para desarrolladores` → activa **Modo de desarrollador** (o, como mínimo, la instalación de aplicaciones de origen externo).

Equivalente por PowerShell **como administrador**:

```powershell
$key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
New-ItemProperty -Path $key -Name AllowDevelopmentWithoutDevLicense -Value 1 -PropertyType DWord -Force
```

### 2.2 Crear un certificado autofirmado

El campo `Subject` **tiene que coincidir exactamente** con el `Publisher` del manifiesto del paquete, que es:

```
CN=70DB4128-9F7D-4D9C-ADFC-7B5988F89237
```

En PowerShell **como administrador**:

```powershell
$cert = New-SelfSignedCertificate `
  -Type Custom `
  -Subject "CN=70DB4128-9F7D-4D9C-ADFC-7B5988F89237" `
  -KeyUsage DigitalSignature `
  -FriendlyName "Typedown Sideload" `
  -CertStoreLocation "Cert:\CurrentUser\My" `
  -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}")

$pwd = ConvertTo-SecureString -String "typedown" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath "$env:USERPROFILE\typedown-sideload.pfx" -Password $pwd
```

> Si el paquete que vas a instalar no es de este repositorio, comprueba antes su `Publisher` real:
> ```powershell
> Add-Type -AssemblyName System.IO.Compression.FileSystem
> $zip = [IO.Compression.ZipFile]::OpenRead("C:\ruta\a\Typedown_1.2.18_x64.msix")
> $entry = $zip.GetEntry("AppxManifest.xml")
> (New-Object IO.StreamReader($entry.Open())).ReadToEnd() -match 'Publisher="([^"]+)"' | Out-Null
> $Matches[1]
> $zip.Dispose()
> ```

### 2.3 Firmar el paquete

`signtool.exe` viene con el Windows SDK. Suele estar en
`C:\Program Files (x86)\Windows Kits\10\bin\<versión>\x64\signtool.exe`.
Para localizarlo:

```powershell
Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin" -Recurse -Filter signtool.exe |
  Where-Object { $_.FullName -like "*x64*" } |
  Select-Object -Last 1 -ExpandProperty FullName
```

Firma el MSIX:

```powershell
& "<ruta-a-signtool>" sign /fd SHA256 /a `
  /f "$env:USERPROFILE\typedown-sideload.pfx" /p "typedown" `
  "C:\ruta\a\Typedown_1.2.18_x64.msix"
```

### 2.4 Confiar en el certificado

El certificado debe estar en **Personas de confianza** (`TrustedPeople`) de la máquina local. Como administrador:

```powershell
Import-Certificate `
  -FilePath (Export-Certificate -Cert $cert -FilePath "$env:TEMP\typedown-sideload.cer").FullName `
  -CertStoreLocation "Cert:\LocalMachine\TrustedPeople"
```

Si abres una sesión nueva y ya no tienes `$cert` en memoria, exporta el `.cer` desde el propio MSIX firmado: clic derecho sobre el archivo → `Propiedades` → `Firmas digitales` → selecciona la firma → `Detalles` → `Ver certificado` → `Instalar certificado` → `Equipo local` → `Colocar todos los certificados en el siguiente almacén` → **Personas de confianza**.

### 2.5 Instalar

Doble clic sobre el `.msix` y pulsa **Instalar**, o desde PowerShell:

```powershell
Add-AppxPackage -Path "C:\ruta\a\Typedown_1.2.18_x64.msix"
```

---

## Opción 3 — Compilar desde el código fuente

Ver la sección [Building from source](README.md#building-from-source) del README. Resumen:

```powershell
git clone https://github.com/manugonz42/Typedown
cd Typedown\Dev\Typedown.Editor
yarn && yarn build
```

Después abre `Typedown.sln` en Visual Studio 2022, marca el proyecto `Typedown` como proyecto de inicio, elige la configuración (`Debug`, `Debug_Local` o `Release`) y la plataforma, y ejecuta.

Requiere Visual Studio 2022 con el SDK de .NET Core 3.1, la carga de trabajo de desarrollo para la Plataforma universal de Windows, Node.js y yarn.

---

## Actualizar

Instalar una versión más reciente sobre la anterior conserva la configuración y la base de datos local:

```powershell
Add-AppxPackage -Path "C:\ruta\a\Typedown_<nueva-version>_x64.msix"
```

La versión nueva debe estar firmada con el mismo certificado que la instalada; si no, Windows la rechaza por conflicto de publisher.

## Desinstalar

Desde `Configuración` → `Aplicaciones` → `Aplicaciones instaladas` → Typedown → `Desinstalar`, o:

```powershell
Get-AppxPackage *Typedown* | Remove-AppxPackage
```

Para eliminar también el certificado de sideload:

```powershell
Get-ChildItem Cert:\LocalMachine\TrustedPeople |
  Where-Object { $_.Subject -eq "CN=70DB4128-9F7D-4D9C-ADFC-7B5988F89237" } |
  Remove-Item
```

---

## Problemas frecuentes

| Error | Causa y solución |
|---|---|
| `No se pudo comprobar la firma del paquete` / error `0x800B0100` | El MSIX no está firmado. Sigue los pasos 2.2 y 2.3. |
| `El certificado del editor no es de confianza` / error `0x800B0109` | El certificado no está en `TrustedPeople` del **equipo local** (no del usuario actual). Repite el paso 2.4. |
| `0x80073CFF` — no cumple los requisitos para instalarse | Falta activar el modo de desarrollador / instalación de apps externas (paso 2.1). |
| `0x80073CF3` — error de validación de la actualización | El paquete instalado tiene otro publisher. Desinstala Typedown y vuelve a instalar. |
| Error al firmar: `SignerSign() failed` `(0x8007000B)` | El `Subject` del certificado no coincide con el `Publisher` del manifiesto. Verifícalo con el snippet del paso 2.2. |
| `signtool` no se reconoce como comando | Falta el Windows SDK. Instálalo desde Visual Studio Installer (componente *Windows 11 SDK*). |
