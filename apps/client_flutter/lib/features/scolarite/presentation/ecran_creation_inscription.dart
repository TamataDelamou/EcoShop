import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../auth/application/auth_providers.dart';
import '../../planification/presentation/ecran_choix_classe.dart';
import '../application/scolarite_providers.dart';
import '../data/inscription_complete_repository.dart';
import '../domain/classe.dart';
import '../domain/scolarite_repository.dart';
import '../../../core/widgets/choisir_date.dart';

/// Inscription d'un nouvel élève (M15quater, complétée par REG-39).
///
/// Retour du test sur téléphone (2026-10-31) : la fiche ne demandait que le
/// nom, le prénom, la date de naissance et la classe. Elle demande désormais,
/// en sections : la photo, le téléphone de l'élève (surtout à partir du
/// secondaire), le père et la mère avec leur téléphone, le tuteur (qui peut
/// être l'un des parents), la situation de handicap, le quartier, l'école
/// d'origine et — dans les écoles de Guinée — le matricule national
/// attribué par l'État.
///
/// Le matricule de l'école reste généré par le serveur. Le doublon est
/// vérifié avant l'envoi, à titre informatif.
class EcranCreationInscription extends ConsumerStatefulWidget {
  const EcranCreationInscription({super.key});

  @override
  ConsumerState<EcranCreationInscription> createState() => _EcranCreationInscriptionState();
}

class _EcranCreationInscriptionState extends ConsumerState<EcranCreationInscription> {
  final _formulaire = GlobalKey<FormState>();
  final _champs = <String, TextEditingController>{};
  DateTime? _dateNaissance;
  String? _sexe;
  Classe? _classe;
  String _tuteur = 'pere';
  bool _handicap = false;
  Uint8List? _photo;
  bool _enCours = false;
  String? _erreur;

  TextEditingController _c(String cle) => _champs.putIfAbsent(cle, TextEditingController.new);
  String? _v(String cle) {
    final t = _champs[cle]?.text.trim();
    return t == null || t.isEmpty ? null : t;
  }

  @override
  void dispose() {
    for (final c in _champs.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _choisirDate() async {
    final maintenant = DateTime.now();
    final date = await choisirDate(
      context: context,
      initialDate: _dateNaissance ?? DateTime(maintenant.year - 10),
      firstDate: DateTime(maintenant.year - 30),
      lastDate: maintenant,
      helpText: 'Date de naissance',
    );
    if (date != null) setState(() => _dateNaissance = date);
  }

  Future<void> _choisirClasse() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EcranChoixClasse(
          titre: 'Classe d\'inscription',
          onSelectionner: (context, classe) {
            setState(() => _classe = classe);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> _choisirPhoto(ImageSource source) async {
    try {
      final fichier = await ImagePicker().pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (fichier == null) return;
      final octets = await fichier.readAsBytes();
      if (mounted) setState(() => _photo = octets);
    } catch (_) {
      if (mounted) setState(() => _erreur = 'Photo indisponible : vérifiez l’autorisation d’accès à l’appareil photo.');
    }
  }

  Future<void> _menuPhoto() async {
    final source = await showModalBottomSheet<ImageSource?>(
      context: context,
      showDragHandle: true,
      builder: (contexte) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Prendre une photo'),
            onTap: () => Navigator.of(contexte).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choisir dans la galerie'),
            onTap: () => Navigator.of(contexte).pop(ImageSource.gallery),
          ),
          if (_photo != null)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Retirer la photo'),
              onTap: () {
                setState(() => _photo = null);
                Navigator.of(contexte).pop();
              },
            ),
        ]),
      ),
    );
    if (source != null) await _choisirPhoto(source);
  }

  Future<void> _valider() async {
    final etablissement = ref.read(etablissementActifProvider);
    final structure = ref.read(structureEtablissementProvider(null)).valueOrNull;
    final anneeId = structure?.anneeCourante?.id;
    final date = _dateNaissance;
    final classe = _classe;

    if (etablissement == null || anneeId == null) {
      setState(() => _erreur = 'Créez d’abord l’année scolaire (« Configurer mon établissement »).');
      return;
    }
    final valide = _formulaire.currentState?.validate() ?? false;
    if (!valide || date == null || classe == null) {
      setState(() => _erreur = 'Renseignez au moins le nom, le prénom, la date de naissance et la classe.');
      return;
    }

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      final doublon = await ref.read(scolariteRepositoryProvider).verifierDoublonEleve(
            nom: _v('nom')!,
            prenom: _v('prenom')!,
            dateNaissance: date,
          );
      if (doublon && mounted) {
        final continuer = await _confirmerDoublon();
        if (continuer != true) {
          setState(() => _enCours = false);
          return;
        }
      }

      final eleve = RenseignementsEleve(
        nom: _v('nom')!,
        prenom: _v('prenom')!,
        dateNaissance: date,
        sexe: _sexe,
        lieuNaissance: _v('lieu_naissance'),
        nationalite: _v('nationalite'),
        telephoneEleve: _v('telephone_eleve'),
        nomPere: _v('nom_pere'),
        telephonePere: _v('telephone_pere'),
        professionPere: _v('profession_pere'),
        nomMere: _v('nom_mere'),
        telephoneMere: _v('telephone_mere'),
        professionMere: _v('profession_mere'),
        tuteurLien: _tuteur,
        tuteurNom: _tuteur == 'autre' ? _v('tuteur_nom') : null,
        tuteurTelephone: _tuteur == 'autre' ? _v('tuteur_telephone') : null,
        situationHandicap: _handicap,
        handicapPrecision: _v('handicap_precision'),
        quartier: _v('quartier'),
        ecoleOrigine: _v('ecole_origine'),
        matriculeNational: _v('matricule_national'),
      );
      final depot = ref.read(inscriptionCompleteRepositoryProvider);
      final ficheId = await depot.inscrire(
        etablissementId: etablissement.id,
        classeId: classe.id,
        anneeScolaireId: anneeId,
        eleve: eleve,
      );

      // La photo ne bloque jamais l'inscription.
      var photoEnvoyee = true;
      final photo = _photo;
      if (photo != null) {
        try {
          await depot.definirPhoto(etablissementId: etablissement.id, ficheId: ficheId, octets: photo);
        } catch (_) {
          photoEnvoyee = false;
        }
      }

      if (!mounted) return;
      ref.invalidate(inscriptionsDeClasseProvider(classe.id));
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(photoEnvoyee
            ? 'Élève inscrit — matricule de l’école généré automatiquement.'
            : 'Élève inscrit. La photo n’a pas pu être envoyée : ajoutez-la plus tard depuis sa fiche.'),
      ));
    } on ErreurScolarite catch (e) {
      setState(() => _erreur = _messageErreur(e.code));
    } catch (_) {
      setState(() => _erreur = 'Inscription impossible pour le moment. Vérifiez votre connexion et réessayez.');
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<bool?> _confirmerDoublon() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Élève peut-être déjà inscrit'),
        content: const Text(
          'Un élève avec les mêmes nom, prénom et date de naissance semble déjà '
          'inscrit ailleurs. Voulez-vous continuer cette inscription ?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Continuer')),
        ],
      ),
    );
  }

  String _messageErreur(String code) => switch (code) {
        'PERMISSION_REFUSEE' => "Vous n'avez pas le droit d'inscrire un élève.",
        'CLASSE_AUTRE_ETABLISSEMENT' => 'Cette classe n\'appartient pas à cet établissement.',
        'CHAMPS_OBLIGATOIRES' => 'Renseignez le nom, le prénom et la date de naissance.',
        _ => 'Inscription impossible pour le moment.',
      };

  // ------------------------------------------------------------- champs

  Widget _texte(String cle, String libelle,
      {bool obligatoire = false, TextInputType? clavier, String? aide, TextCapitalization? casse}) {
    final telephone = clavier == TextInputType.phone;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: Key('inscription_$cle'),
        controller: _c(cle),
        keyboardType: clavier,
        textCapitalization: casse ?? (telephone ? TextCapitalization.none : TextCapitalization.words),
        inputFormatters: telephone ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))] : null,
        decoration: InputDecoration(
          labelText: obligatoire ? '$libelle *' : libelle,
          helperText: aide,
          border: const OutlineInputBorder(),
          prefixIcon: telephone ? const Icon(Icons.phone_outlined) : null,
        ),
        validator: (v) {
          final t = v?.trim() ?? '';
          if (obligatoire && t.isEmpty) return 'Obligatoire';
          if (telephone && t.isNotEmpty && t.replaceAll(RegExp(r'[^0-9]'), '').length < 8) {
            return 'Numéro trop court';
          }
          return null;
        },
      ),
    );
  }

  Widget _section(String titre, {String? aide}) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titre, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (aide != null) Text(aide, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final pays = ref.watch(etablissementActifProvider)?.paysCode;
    // Matricule de l'État : écoles de Guinée (ou pays non renseigné).
    final guinee = pays == null || pays.isEmpty || pays.toUpperCase() == 'GN';
    final schema = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle inscription')),
      body: Form(
        key: _formulaire,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // Photo
            Center(
              child: InkWell(
                key: const Key('inscription_photo'),
                customBorder: const CircleBorder(),
                onTap: _menuPhoto,
                child: Stack(children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: schema.surfaceContainerHighest,
                    backgroundImage: _photo == null ? null : MemoryImage(_photo!),
                    child: _photo == null ? Icon(Icons.person_outline, size: 48, color: schema.onSurfaceVariant) : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: schema.primary,
                      child: Icon(Icons.photo_camera, size: 16, color: schema.onPrimary),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            Center(child: Text(_photo == null ? 'Photo de l’élève' : 'Touchez pour changer', style: Theme.of(context).textTheme.bodySmall)),

            _section('Élève'),
            _texte('nom', 'Nom', obligatoire: true, casse: TextCapitalization.characters),
            _texte('prenom', 'Prénom(s)', obligatoire: true),
            ListTile(
              key: const Key('inscription_date_naissance'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Date de naissance *'),
              subtitle: Text(_dateNaissance == null ? 'Non renseignée' : _formatDate(_dateNaissance!)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: _choisirDate,
            ),
            _texte('lieu_naissance', 'Lieu de naissance'),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SegmentedButton<String>(
                key: const Key('inscription_sexe'),
                emptySelectionAllowed: true,
                segments: const [
                  ButtonSegment(value: 'M', label: Text('Garçon'), icon: Icon(Icons.male)),
                  ButtonSegment(value: 'F', label: Text('Fille'), icon: Icon(Icons.female)),
                ],
                selected: {?_sexe},
                onSelectionChanged: (s) => setState(() => _sexe = s.isEmpty ? null : s.first),
              ),
            ),
            _texte('nationalite', 'Nationalité'),
            _texte('telephone_eleve', 'Téléphone de l’élève',
                clavier: TextInputType.phone, aide: 'Conseillé à partir du secondaire'),
            if (guinee)
              _texte('matricule_national', 'Matricule national (attribué par l’État)',
                  casse: TextCapitalization.characters, aide: 'Pour les élèves guinéens qui en ont un'),

            _section('Classe'),
            ListTile(
              key: const Key('inscription_classe'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Classe d’inscription *'),
              subtitle: Text(_classe?.nom ?? 'Non choisie'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _choisirClasse,
            ),
            _texte('ecole_origine', 'École d’origine', aide: 'École fréquentée l’an dernier'),

            _section('Parents'),
            _texte('nom_pere', 'Nom et prénom du père'),
            _texte('telephone_pere', 'Téléphone du père', clavier: TextInputType.phone),
            _texte('profession_pere', 'Profession du père', casse: TextCapitalization.sentences),
            _texte('nom_mere', 'Nom et prénom de la mère'),
            _texte('telephone_mere', 'Téléphone de la mère', clavier: TextInputType.phone),
            _texte('profession_mere', 'Profession de la mère', casse: TextCapitalization.sentences),

            _section('Tuteur', aide: 'La personne qui suit l’élève au quotidien ; elle est prévenue en cas d’urgence.'),
            SegmentedButton<String>(
              key: const Key('inscription_tuteur'),
              segments: const [
                ButtonSegment(value: 'pere', label: Text('Le père')),
                ButtonSegment(value: 'mere', label: Text('La mère')),
                ButtonSegment(value: 'autre', label: Text('Autre')),
              ],
              selected: {_tuteur},
              onSelectionChanged: (s) => setState(() => _tuteur = s.first),
            ),
            const SizedBox(height: 12),
            if (_tuteur == 'autre') ...[
              _texte('tuteur_nom', 'Nom et prénom du tuteur', obligatoire: true),
              _texte('tuteur_telephone', 'Téléphone du tuteur', clavier: TextInputType.phone),
            ],

            _section('Santé et adresse'),
            SwitchListTile(
              key: const Key('inscription_handicap'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Situation de handicap'),
              subtitle: const Text('Pour adapter l’accueil et les examens'),
              value: _handicap,
              onChanged: (v) => setState(() => _handicap = v),
            ),
            if (_handicap) _texte('handicap_precision', 'Précisez (vue, ouïe, mobilité…)', casse: TextCapitalization.sentences),
            _texte('quartier', 'Quartier'),

            if (_erreur != null) ...[
              const SizedBox(height: 12),
              Text(_erreur!, key: const Key('inscription_erreur'), style: TextStyle(color: schema.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('bouton_inscrire'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _enCours ? null : _valider,
              child: _enCours
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Inscrire l\'élève'),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
