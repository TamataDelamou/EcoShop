<#
.SYNOPSIS
  Construit l'application Android d'EcoShop pour le Play Store (ou un APK
  à installer directement).

.DESCRIPTION
  À lancer depuis la racine du dépôt :

    powershell -ExecutionPolicy Bypass -File scripts\construire_android.ps1
    powershell -ExecutionPolicy Bypass -File scripts\construire_android.ps1 -Format apk
    powershell -ExecutionPolicy Bypass -File scripts\construire_android.ps1 -Format apk -ParAbi

  -ParAbi : un APK par type de téléphone (environ 45 Mo au lieu de 124 Mo),
  plus léger à envoyer par WhatsApp. arm64-v8a convient à presque tous les
  téléphones Android récents.

  Avant Gradle, le script arrête la machine Podman si elle tourne (base de
  test locale) : Gradle se réserve 8 Go de mémoire, et sans cette mémoire
  la construction peut durer des heures.

  Au premier lancement, le script crée la clé de signature de GSG (gardée
  hors du dépôt) et le fichier de configuration de production.

  Guide complet : docs\MISE_EN_SERVICE.md
#>
param(
  [ValidateSet('appbundle', 'apk')]
  [string]$Format = 'appbundle',
  [switch]$ParAbi
)
if ($ParAbi -and $Format -ne 'apk') {
  Write-Host '-ParAbi ne concerne que les APK : utilisez -Format apk -ParAbi.' -ForegroundColor Red
  exit 1
}

$ErrorActionPreference = 'Stop'
$Racine = Split-Path -Parent $PSScriptRoot
$App = Join-Path $Racine 'apps\client_flutter'
Set-Location $App
$SansBom = New-Object System.Text.UTF8Encoding $false

function Echec([string]$texte) {
  Write-Host ''
  Write-Host $texte -ForegroundColor Red
  exit 1
}

function Texte-Clair([Security.SecureString]$s) {
  return [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { Echec 'Flutter introuvable dans le PATH.' }

# 1. Configuration de production (adresse et clé publique Supabase)
$config = Join-Path $App 'config\production.json'
if (-not (Test-Path $config)) {
  Copy-Item (Join-Path $App 'config\production.exemple.json') $config
  Write-Host "Configuration créée : $config" -ForegroundColor Yellow
  Write-Host 'Remplissez SUPABASE_URL et SUPABASE_PUBLISHABLE_KEY (Supabase → Settings → API Keys), enregistrez, relancez.' -ForegroundColor Yellow
  Start-Process notepad.exe $config
  exit 0
}
$lu = Get-Content -Raw -Encoding UTF8 $config | ConvertFrom-Json
if (-not $lu.SUPABASE_URL -or $lu.SUPABASE_URL -match '<' -or -not $lu.SUPABASE_PUBLISHABLE_KEY -or $lu.SUPABASE_PUBLISHABLE_KEY -match '<') {
  Echec "Complétez $config avant de construire."
}

# 2. Notifications push
if (-not (Test-Path (Join-Path $App 'android\app\google-services.json'))) {
  Write-Host 'Attention : android\app\google-services.json absent, application construite SANS notifications push.' -ForegroundColor Yellow
}

# 3. Clé de signature (une seule fois, à conserver précieusement)
$proprietes = Join-Path $App 'android\key.properties'
if (-not (Test-Path $proprietes)) {
  $keytool = (Get-Command keytool -ErrorAction SilentlyContinue).Source
  if (-not $keytool) {
    foreach ($candidat in @("$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe", "$env:ProgramFiles\Android\Android Studio\jre\bin\keytool.exe")) {
      if (Test-Path $candidat) { $keytool = $candidat; break }
    }
  }
  if (-not $keytool) { Echec 'keytool introuvable : installez Android Studio (il fournit Java et keytool).' }

  $dossierCles = Join-Path $env:USERPROFILE 'cles-gsg'
  New-Item -ItemType Directory -Force -Path $dossierCles | Out-Null
  $magasin = Join-Path $dossierCles 'ecoshop-televersement.jks'
  Write-Host ''
  Write-Host "Création de la clé de signature de l'application : $magasin" -ForegroundColor Cyan
  Write-Host "Choisissez un mot de passe (6 caractères minimum) et notez-le dans un endroit sûr." -ForegroundColor Cyan
  $mdp1 = Texte-Clair (Read-Host 'Mot de passe de la clé' -AsSecureString)
  $mdp2 = Texte-Clair (Read-Host 'Confirmez le mot de passe' -AsSecureString)
  if ($mdp1 -ne $mdp2 -or $mdp1.Length -lt 6) { Echec 'Mots de passe différents ou trop courts.' }
  & $keytool -genkeypair -v -keystore $magasin -keyalg RSA -keysize 2048 -validity 10000 -alias ecoshop `
    -dname 'CN=Global Service Groupe, O=GSG, L=Conakry, C=GN' -storepass $mdp1 -keypass $mdp1
  if ($LASTEXITCODE -ne 0) { Echec 'Création de la clé impossible.' }
  $lignes = @(
    "storePassword=$mdp1",
    "keyPassword=$mdp1",
    'keyAlias=ecoshop',
    ('storeFile=' + ($magasin -replace '\\', '/'))
  )
  [IO.File]::WriteAllLines($proprietes, $lignes, $SansBom)
  Write-Host ''
  Write-Host "IMPORTANT : sauvegardez $magasin et son mot de passe (clé USB, coffre)." -ForegroundColor Yellow
  Write-Host "Sans eux, les mises à jour sur le Play Store demandent une procédure de remplacement de clé." -ForegroundColor Yellow
}

# 3 bis. Empreinte SHA-1 de la clé : à déclarer dans Firebase pour le
# bouton « Continuer avec Google » (docs\MISE_EN_SERVICE.md, étape 5).
$lus = @{}
foreach ($l in Get-Content -Encoding UTF8 $proprietes) { if ($l -match '^([^=]+)=(.*)$') { $lus[$Matches[1]] = $Matches[2] } }
$keytool = (Get-Command keytool -ErrorAction SilentlyContinue).Source
if (-not $keytool) {
  foreach ($candidat in @("$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe", "$env:ProgramFiles\Android\Android Studio\jre\bin\keytool.exe")) {
    if (Test-Path $candidat) { $keytool = $candidat; break }
  }
}
if ($keytool -and $lus['storeFile']) {
  $sha1 = & $keytool -list -v -keystore $lus['storeFile'] -alias $lus['keyAlias'] -storepass $lus['storePassword'] 2>$null | Select-String 'SHA-?\s?1:' | Select-Object -First 1
  if ($sha1) {
    $sha1 = $sha1.ToString().Trim()
    Write-Host ''
    Write-Host "Empreinte de la clé (Firebase → Paramètres du projet → application Android) : $sha1" -ForegroundColor Cyan
  }
}
if (-not $lu.GOOGLE_WEB_CLIENT_ID -or $lu.GOOGLE_WEB_CLIENT_ID -notmatch '\.apps\.googleusercontent\.com$') {
  Write-Host 'Attention : GOOGLE_WEB_CLIENT_ID non renseigné, application construite SANS le bouton « Continuer avec Google » (connexion par code e-mail seulement).' -ForegroundColor Yellow
}

# 4. Mémoire pour Gradle : la machine Podman (base de test locale) en
# occupe une partie ; sans elle, la construction peut durer des heures.
$podman = (Get-Command podman -ErrorAction SilentlyContinue).Source
if (-not $podman -and (Test-Path "$env:ProgramFiles\RedHat\Podman\podman.exe")) { $podman = "$env:ProgramFiles\RedHat\Podman\podman.exe" }
if ($podman) {
  $machines = @()
  try { $machines = @(& $podman machine list --format json 2>$null | Out-String | ConvertFrom-Json) } catch { }
  $actives = @($machines | Where-Object { $_.Running -or $_.Starting })
  foreach ($m in $actives) {
    Write-Host "Arrêt de la machine Podman « $($m.Name) » pour libérer de la mémoire…" -ForegroundColor Yellow
    & $podman machine stop $m.Name 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
      Write-Host "Impossible d'arrêter Podman : arrêtez-le vous-même (podman machine stop), sinon la construction sera très lente." -ForegroundColor Red
    }
  }
  # Windows rend la mémoire de la machine virtuelle quelques secondes après.
  if ($actives.Count -gt 0) { Start-Sleep -Seconds 10 }
}
$libreGo = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)
if ($libreGo -lt 6) {
  Write-Host "Attention : seulement $libreGo Go de mémoire libre. Fermez les autres applications (navigateur, émulateur), sinon la construction sera très lente." -ForegroundColor Yellow
}

# 5. Construction
& flutter pub get
if ($LASTEXITCODE -ne 0) { Echec 'flutter pub get a échoué.' }
$options = @('build', $Format, '--release', '--dart-define-from-file=config/production.json')
if ($ParAbi) { $options += '--split-per-abi' }
& flutter @options
if ($LASTEXITCODE -ne 0) { Echec 'La construction a échoué (voir ci-dessus).' }

Write-Host ''
if ($ParAbi) {
  $dossier = Join-Path $App 'build\app\outputs\flutter-apk'
  Write-Host 'APK prêts, un par type de téléphone :' -ForegroundColor Green
  foreach ($abi in @('arm64-v8a', 'armeabi-v7a', 'x86_64')) {
    $fichier = Join-Path $dossier "app-$abi-release.apk"
    if (-not (Test-Path $fichier)) { continue }
    $taille = [math]::Round((Get-Item $fichier).Length / 1MB, 1)
    $note = switch ($abi) {
      'arm64-v8a' { '  <- À ENVOYER PAR DÉFAUT (presque tous les téléphones récents)' }
      'armeabi-v7a' { '  (anciens téléphones 32 bits, si le premier refuse de s''installer)' }
      default { '  (émulateurs et rares tablettes Intel)' }
    }
    Write-Host ("  {0}  {1} Mo{2}" -f $fichier, $taille, $note)
  }
} else {
  $sortie = if ($Format -eq 'apk') { 'build\app\outputs\flutter-apk\app-release.apk' } else { 'build\app\outputs\bundle\release\app-release.aab' }
  $fichier = Join-Path $App $sortie
  $taille = [math]::Round((Get-Item $fichier).Length / 1MB, 1)
  Write-Host "Application prête : $fichier ($taille Mo)" -ForegroundColor Green
}
