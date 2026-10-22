<#
.SYNOPSIS
  Déploie EcoShop sur un projet Supabase : base de données, fonctions,
  secrets, tâches planifiées, administrateur GSG.

.DESCRIPTION
  À lancer depuis la racine du dépôt, dans PowerShell :

    powershell -ExecutionPolicy Bypass -File scripts\deployer_supabase.ps1

  Peut être relancé autant de fois que nécessaire : chaque étape remplace
  ce qui existe, rien n'est dupliqué. Les valeurs secrètes restent dans
  supabase\mise_en_service\secrets.local.env (ignoré par git) et dans le
  projet Supabase ; elles ne s'affichent jamais à l'écran.

  Guide complet : docs\MISE_EN_SERVICE.md
#>
param(
  [switch]$SansMigrations,
  [switch]$SansFonctions
)

$ErrorActionPreference = 'Stop'
$Racine = Split-Path -Parent $PSScriptRoot
Set-Location $Racine
$Dossier = Join-Path $Racine 'supabase\mise_en_service'
$FichierSecrets = Join-Path $Dossier 'secrets.local.env'
$SansBom = New-Object System.Text.UTF8Encoding $false

function Etape([string]$numero, [string]$texte) {
  Write-Host ''
  Write-Host "[$numero] $texte" -ForegroundColor Cyan
}

function Echec([string]$texte) {
  Write-Host ''
  Write-Host $texte -ForegroundColor Red
  exit 1
}

function Supabase {
  & supabase @args
  if ($LASTEXITCODE -ne 0) { Echec "La commande « supabase $($args[0]) $($args[1]) » a échoué (voir le message ci-dessus)." }
}

function Lire-Secrets([string]$chemin) {
  $valeurs = [ordered]@{}
  foreach ($ligne in [IO.File]::ReadAllLines($chemin)) {
    $l = $ligne.Trim().TrimStart([char]0xFEFF)
    if ($l -eq '' -or $l.StartsWith('#')) { continue }
    $i = $l.IndexOf('=')
    if ($i -lt 1) { continue }
    $cle = $l.Substring(0, $i).Trim()
    $valeur = $l.Substring($i + 1).Trim()
    if ($valeur.Length -ge 2 -and (($valeur.StartsWith('"') -and $valeur.EndsWith('"')) -or ($valeur.StartsWith("'") -and $valeur.EndsWith("'")))) {
      $valeur = $valeur.Substring(1, $valeur.Length - 2)
    }
    $valeurs[$cle] = $valeur
  }
  return $valeurs
}

function Nouveau-Secret {
  $octets = New-Object byte[] 32
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($octets)
  return (($octets | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Executer-Sql([string]$modele, [hashtable]$remplacements, [string]$nomLocal) {
  $sql = [IO.File]::ReadAllText((Join-Path $Dossier $modele))
  foreach ($cle in $remplacements.Keys) { $sql = $sql.Replace("{{$cle}}", [string]$remplacements[$cle]) }
  $fichier = Join-Path $Dossier $nomLocal
  [IO.File]::WriteAllText($fichier, $sql, $SansBom)
  try {
    & supabase db query --linked --file $fichier
    if ($LASTEXITCODE -ne 0) {
      Write-Host "Exécution impossible depuis le script. Ouvrez Supabase → SQL Editor, collez le contenu de :" -ForegroundColor Yellow
      Write-Host "  $fichier" -ForegroundColor Yellow
      Write-Host "puis exécutez-le et SUPPRIMEZ ce fichier (il contient des secrets)." -ForegroundColor Yellow
      return $false
    }
    Remove-Item $fichier -Force
    return $true
  } catch {
    Write-Host "Erreur : $_" -ForegroundColor Yellow
    return $false
  }
}

# ---------------------------------------------------------------------------
Etape 0 'Vérifications'
if (-not (Get-Command supabase -ErrorAction SilentlyContinue)) {
  Echec "Supabase CLI introuvable. Installez-le puis relancez (docs\MISE_EN_SERVICE.md, étape 2) :`n  scoop bucket add supabase https://github.com/supabase/scoop-bucket.git`n  scoop install supabase"
}
Write-Host ("Supabase CLI " + (& supabase --version))

if (-not (Test-Path $FichierSecrets)) {
  Copy-Item (Join-Path $Dossier 'secrets.exemple.env') $FichierSecrets
  Write-Host ''
  Write-Host "Fichier des secrets créé : $FichierSecrets" -ForegroundColor Yellow
  Write-Host "Remplissez-le (au minimum PROJET_REF), enregistrez, puis relancez ce script." -ForegroundColor Yellow
  Start-Process notepad.exe $FichierSecrets
  exit 0
}

$S = Lire-Secrets $FichierSecrets
$ref = $S['PROJET_REF']
if (-not $ref -or $ref -notmatch '^[a-z0-9]{20}$') {
  Echec "PROJET_REF manquant ou invalide dans $FichierSecrets (20 lettres minuscules et chiffres : Settings → General → Reference ID)."
}

# Déclencheurs des tâches planifiées : générés une fois, gardés dans le fichier.
$contenu = [IO.File]::ReadAllText($FichierSecrets)
foreach ($nom in @('NOTIFICATIONS_DECLENCHEUR_SECRET', 'PAIEMENTS_DECLENCHEUR_SECRET')) {
  if (-not $S[$nom]) {
    $S[$nom] = Nouveau-Secret
    $contenu = [regex]::Replace($contenu, "(?m)^$nom=.*$", "$nom=$($S[$nom])")
    Write-Host "Secret $nom généré."
  }
}
[IO.File]::WriteAllText($FichierSecrets, $contenu, $SansBom)

# ---------------------------------------------------------------------------
Etape 1 "Liaison au projet $ref (mot de passe de la base demandé)"
Supabase link --project-ref $ref

if (-not $SansMigrations) {
  Etape 2 'Base de données : application des migrations'
  Supabase db push
}

# ---------------------------------------------------------------------------
Etape 3 'Secrets des fonctions'
$locaux = @('PROJET_REF', 'ADMIN_GSG_COURRIEL', 'ADMIN_GSG_TELEPHONE', 'FCM_COMPTE_SERVICE_FICHIER')
$lignes = New-Object System.Collections.Generic.List[string]
foreach ($cle in $S.Keys) {
  if ($locaux -contains $cle -or -not $S[$cle]) { continue }
  if ($S[$cle].Contains("'")) { Echec "La valeur de $cle contient une apostrophe : à corriger dans $FichierSecrets." }
  $lignes.Add("$cle='$($S[$cle])'")
}
$cheminFcm = $S['FCM_COMPTE_SERVICE_FICHIER']
if ($cheminFcm) {
  if (-not (Test-Path $cheminFcm)) { Echec "Fichier du compte de service Firebase introuvable : $cheminFcm" }
  $compte = Get-Content -Raw -Encoding UTF8 $cheminFcm | ConvertFrom-Json
  if (-not $compte.private_key -or -not $compte.client_email -or -not $compte.project_id) {
    Echec "Ce fichier n'est pas un compte de service Firebase : $cheminFcm"
  }
  $lignes.Add("FCM_COMPTE_SERVICE='" + ($compte | ConvertTo-Json -Compress -Depth 5) + "'")
}
$temporaire = Join-Path $Dossier 'secrets_envoi.local.env'
[IO.File]::WriteAllLines($temporaire, $lignes, $SansBom)
try {
  Supabase secrets set --env-file $temporaire
} finally {
  Remove-Item $temporaire -Force -ErrorAction SilentlyContinue
}
Write-Host "$($lignes.Count) secrets envoyés (valeurs non affichées)."

if (-not $SansFonctions) {
  Etape 4 'Déploiement des Edge Functions'
  Supabase functions deploy --use-api
}

# ---------------------------------------------------------------------------
Etape 5 'Tâches planifiées et coffre'
$ok = Executer-Sql 'taches_planifiees.modele.sql' @{
  URL_PROJET                       = "https://$ref.supabase.co"
  NOTIFICATIONS_DECLENCHEUR_SECRET = $S['NOTIFICATIONS_DECLENCHEUR_SECRET']
  PAIEMENTS_DECLENCHEUR_SECRET     = $S['PAIEMENTS_DECLENCHEUR_SECRET']
  KERNEL_EXPORT_DECLENCHEUR_SECRET = $S['KERNEL_EXPORT_DECLENCHEUR_SECRET']
} 'taches_planifiees.local.sql'

if ($S['ADMIN_GSG_COURRIEL'] -or $S['ADMIN_GSG_TELEPHONE']) {
  Etape 6 'Administrateur GSG'
  $telephone = ($S['ADMIN_GSG_TELEPHONE'] -replace '[^0-9]', '')
  if ($telephone.StartsWith('00')) { $telephone = $telephone.Substring(2) }
  $null = Executer-Sql 'premier_admin.modele.sql' @{
    ADMIN_GSG_COURRIEL  = ($S['ADMIN_GSG_COURRIEL'] -replace "'", '')
    ADMIN_GSG_TELEPHONE = $telephone
  } 'premier_admin.local.sql'
  Write-Host "Si aucune ligne « Administrateur GSG désigné » n'apparaît ci-dessus : créez d'abord ce compte dans l'application, puis relancez."
}

# ---------------------------------------------------------------------------
Etape 7 'Contrôle de préparation'
& supabase db query --linked "select c ->> 'controle' as controle, case when (c ->> 'ok')::boolean then 'OK' else 'A FAIRE' end as etat, c ->> 'detail' as detail from jsonb_array_elements(public.etat_mise_en_service() -> 'controles') c"

Write-Host ''
Write-Host 'Déploiement terminé. Reste à faire dans le tableau de bord Supabase (docs\MISE_EN_SERVICE.md, étape 5) :' -ForegroundColor Green
Write-Host '  - Authentication → Hooks : « Customize Access Token » et « Send SMS »'
Write-Host '  - Authentication → Emails → SMTP : Brevo'
Write-Host '  - Authentication → URL Configuration'
