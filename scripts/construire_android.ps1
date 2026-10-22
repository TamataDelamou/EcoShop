<#
.SYNOPSIS
  Construit l'application Android d'EcoShop pour le Play Store (ou un APK
  à installer directement).

.DESCRIPTION
  À lancer depuis la racine du dépôt :

    powershell -ExecutionPolicy Bypass -File scripts\construire_android.ps1
    powershell -ExecutionPolicy Bypass -File scripts\construire_android.ps1 -Format apk

  Au premier lancement, le script crée la clé de signature de GSG (gardée
  hors du dépôt) et le fichier de configuration de production.

  Guide complet : docs\MISE_EN_SERVICE.md
#>
param(
  [ValidateSet('appbundle', 'apk')]
  [string]$Format = 'appbundle'
)

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

# 4. Construction
& flutter pub get
if ($LASTEXITCODE -ne 0) { Echec 'flutter pub get a échoué.' }
& flutter build $Format --release --dart-define-from-file=config/production.json
if ($LASTEXITCODE -ne 0) { Echec 'La construction a échoué (voir ci-dessus).' }

$sortie = if ($Format -eq 'apk') { 'build\app\outputs\flutter-apk\app-release.apk' } else { 'build\app\outputs\bundle\release\app-release.aab' }
Write-Host ''
Write-Host "Application prête : $(Join-Path $App $sortie)" -ForegroundColor Green
