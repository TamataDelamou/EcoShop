import 'dart:math';

/// Moteur de calcul de l'emploi du temps (REG-24).
///
/// Inspiré des logiciels de référence (EDT/Pronote d'Index Éducation, aSc
/// Timetables, FET, Horarium) :
/// - **contraintes impératives** : un enseignant, une classe (ou un groupe),
///   une salle ne sont jamais à deux endroits à la fois ; indisponibilités
///   des enseignants, des classes et des salles ; demi-journées libérées ;
///   séances verrouillées gardées telles quelles ; séances de 2 h sur des
///   créneaux consécutifs (jamais à cheval sur une récréation) ; groupes
///   d'une même classe en parallèle (langues, demi-classes de TP) ;
/// - **critères de qualité pondérés** (0 à 10, réglables par l'école) :
///   pas de trous pour les élèves, peu de trous pour les enseignants,
///   matières réparties sur la semaine, matières à fort coefficient le
///   matin, journées équilibrées, enseignants regroupés sur moins de jours,
///   dernière heure de la journée évitée.
///
/// Méthode : construction gloutonne « la séance la plus contrainte
/// d'abord » (DSatur) avec chaînes d'éjection quand une séance ne trouve
/// plus de place, puis amélioration par recuit simulé (déplacements et
/// échanges), plusieurs départs, meilleur résultat gardé.
///
/// Calcul 100 % sur l'appareil, sans réseau (hors connexion d'abord) ; code
/// Dart pur, exécutable dans un isolat. La Direction valide la proposition :
/// le moteur propose, l'humain décide.
class MoteurEmploiDuTemps {
  MoteurEmploiDuTemps(this.donnees) : _hasard = Random(donnees.graine);

  final DonneesEmploi donnees;
  final Random _hasard;

  // ------------------------------------------------------------------ grille
  late final int _nbJours = donnees.jours.length;
  late final List<int> _creneauxCours = [
    for (var i = 0; i < donnees.creneaux.length; i++)
      if (donnees.creneaux[i].cours) i,
  ];
  late final int _s = _creneauxCours.length;
  late final int _cases = _nbJours * _s;

  /// Créneaux de cours consécutifs (sans pause entre eux) à partir de p.
  late final List<int> _suite = _calculerSuites();

  /// Créneau du matin (début avant 12 h 30).
  late final List<bool> _matin = [
    for (final i in _creneauxCours) donnees.creneaux[i].debutMinutes < 12 * 60 + 30,
  ];

  /// Dernier créneau de cours de la journée.
  late final int _dernier = _s - 1;

  // ------------------------------------------------------------- entités
  final _classes = <String, int>{};
  final _groupes = <String, int>{};
  final _enseignants = <String, int>{};
  final _salles = <String, int>{};

  late List<List<int>> _classeEntiere;
  late List<List<int>> _classeGroupes;
  late List<List<int>> _groupeOccupe;
  late List<List<int>> _enseignantOccupe;
  late List<List<int>> _salleOccupee;
  late List<List<bool>> _classeBloquee;
  late List<List<bool>> _enseignantBloque;
  late List<List<bool>> _salleBloquee;
  late List<bool> _bloqueTous;

  // ------------------------------------------------------------- séances
  final _unites = <_Unite>[];
  late List<List<int>> _parClasse;
  late List<List<int>> _parEnseignant;
  late List<List<int>> _parSalle;
  late List<List<int>> _activiteJour;
  late List<int> _maxParJour;
  late List<int> _chargeClasse;

  final _cacheBesoin = <int, int>{};

  ReglesEmploi get _r => donnees.regles;

  // =================================================================== API

  /// Vérifications avant calcul : ce qui rendra l'emploi du temps
  /// impossible quoi qu'il arrive (trop d'heures pour une classe ou un
  /// enseignant, séance plus longue que tout bloc de créneaux…).
  static List<String> diagnostiquer(DonneesEmploi d) {
    final alertes = <String>[];
    final cours = d.creneaux.where((c) => c.cours).toList();
    if (d.jours.isEmpty || cours.isEmpty) {
      alertes.add('La grille horaire n’a aucun créneau de cours : définissez les jours et les heures.');
      return alertes;
    }
    final minutesSemaine = d.jours.length * cours.fold<int>(0, (s, c) => s + c.minutes);
    final parClasse = <String, int>{};
    final parEnseignant = <String, int>{};
    final nomsClasse = <String, String>{};
    final nomsEnseignant = <String, String>{};
    final plusLongBloc = _plusLongBloc(d.creneaux);
    for (final c in d.cours) {
      if (c.groupeId == null) parClasse[c.classeId] = (parClasse[c.classeId] ?? 0) + c.minutesParSemaine;
      nomsClasse[c.classeId] = c.nomClasse;
      if (c.enseignantId != null) {
        parEnseignant[c.enseignantId!] = (parEnseignant[c.enseignantId!] ?? 0) + c.minutesParSemaine;
        nomsEnseignant[c.enseignantId!] = c.nomEnseignant ?? 'Enseignant';
      }
      if (c.dureeSeance > plusLongBloc) {
        alertes.add('${c.libelle} : séances de ${_h(c.dureeSeance)}, mais la grille n’a pas de bloc aussi long '
            'sans pause (${_h(plusLongBloc)} au plus).');
      }
      if (c.minutesParSemaine <= 0) alertes.add('${c.libelle} : aucune heure par semaine indiquée.');
    }
    parClasse.forEach((id, m) {
      if (m > minutesSemaine) {
        alertes.add('${nomsClasse[id]} : ${_h(m)} de cours par semaine pour ${_h(minutesSemaine)} de créneaux.');
      }
    });
    parEnseignant.forEach((id, m) {
      if (m > minutesSemaine) {
        alertes.add('${nomsEnseignant[id]} : ${_h(m)} de cours par semaine pour ${_h(minutesSemaine)} de créneaux.');
      }
    });
    return alertes;
  }

  /// Calcule une proposition. [departs] départs différents, meilleur gardé.
  ResultatEmploi resoudre({int departs = 3}) {
    final chrono = Stopwatch()..start();
    _preparer();
    if (_s == 0 || _nbJours == 0) {
      return ResultatEmploi(
        seances: const [],
        nonPlacees: [
          for (final u in _unites)
            if (!u.fixe) _nonPlacee(u, 'Aucun créneau de cours dans la grille'),
        ],
        bilan: BilanQualite.vide(_unites.where((u) => !u.fixe).length),
      );
    }
    List<int>? meilleur;
    var meilleurCout = double.infinity;
    var meilleurNonPlaces = 1 << 30;
    final budgetParDepart = donnees.budget.inMilliseconds ~/ max(1, departs);
    for (var essai = 0; essai < departs; essai++) {
      _vider();
      // Construction puis amélioration, dans la part de temps du départ.
      final finDepart = chrono.elapsedMilliseconds + budgetParDepart;
      _construire(chrono, finDepart);
      _ameliorer(Duration(milliseconds: max(100, finDepart - chrono.elapsedMilliseconds)), chrono);
      final nonPlaces = _unites.where((u) => !u.fixe && u.position < 0).length;
      final cout = _coutTotal();
      if (nonPlaces < meilleurNonPlaces || (nonPlaces == meilleurNonPlaces && cout < meilleurCout)) {
        meilleur = [for (final u in _unites) u.position];
        meilleurCout = cout;
        meilleurNonPlaces = nonPlaces;
      }
      if (chrono.elapsedMilliseconds > donnees.budget.inMilliseconds) break;
    }
    // Rétablit la meilleure solution.
    _vider();
    for (var i = 0; i < _unites.length; i++) {
      final p = meilleur![i];
      if (p >= 0 && !_unites[i].fixe) _placer(i, p);
    }
    return _resultat();
  }

  // ============================================================ préparation

  List<int> _calculerSuites() {
    final suite = List<int>.filled(_creneauxCours.length, 1);
    for (var p = _creneauxCours.length - 2; p >= 0; p--) {
      final a = donnees.creneaux[_creneauxCours[p]];
      final b = donnees.creneaux[_creneauxCours[p + 1]];
      // Consécutifs : pas de créneau (pause) entre eux et sans écart.
      if (_creneauxCours[p + 1] == _creneauxCours[p] + 1 && b.debutMinutes - a.finMinutes <= 5) {
        suite[p] = suite[p + 1] + 1;
      }
    }
    return suite;
  }

  static int _plusLongBloc(List<CreneauEmploi> creneaux) {
    var meilleur = 0;
    var courant = 0;
    CreneauEmploi? precedent;
    for (final c in creneaux) {
      if (!c.cours) {
        courant = 0;
        precedent = null;
        continue;
      }
      if (precedent != null && c.debutMinutes - precedent.finMinutes <= 5) {
        courant += c.minutes;
      } else {
        courant = c.minutes;
      }
      precedent = c;
      meilleur = max(meilleur, courant);
    }
    return meilleur;
  }

  int _indexClasse(String id) => _classes.putIfAbsent(id, () => _classes.length);
  int _indexEnseignant(String? id) => id == null ? -1 : _enseignants.putIfAbsent(id, () => _enseignants.length);
  int _indexSalle(String? id) => id == null ? -1 : _salles.putIfAbsent(id, () => _salles.length);
  int _indexGroupe(String? id) => id == null ? -1 : _groupes.putIfAbsent(id, () => _groupes.length);

  void _preparer() {
    // Entités.
    for (final c in donnees.cours) {
      _indexClasse(c.classeId);
      _indexGroupe(c.groupeId);
      _indexEnseignant(c.enseignantId);
      _indexSalle(c.salleId);
    }
    for (final f in donnees.seancesFixes) {
      _indexClasse(f.classeId);
      _indexGroupe(f.groupeId);
      _indexEnseignant(f.enseignantId);
      _indexSalle(f.salleId);
    }
    for (final i in donnees.indisponibilites) {
      _indexEnseignant(i.enseignantId);
      _indexSalle(i.salleId);
      if (i.classeId != null) _indexClasse(i.classeId!);
    }

    List<List<int>> zeros(int n) => [for (var i = 0; i < n; i++) List<int>.filled(_cases, 0)];
    List<List<bool>> faux(int n) => [for (var i = 0; i < n; i++) List<bool>.filled(_cases, false)];
    _classeEntiere = zeros(_classes.length);
    _classeGroupes = zeros(_classes.length);
    _groupeOccupe = zeros(_groupes.length);
    _enseignantOccupe = zeros(_enseignants.length);
    _salleOccupee = zeros(_salles.length);
    _classeBloquee = faux(_classes.length);
    _enseignantBloque = faux(_enseignants.length);
    _salleBloquee = faux(_salles.length);
    _bloqueTous = List<bool>.filled(_cases, false);

    // Demi-journées libérées.
    donnees.demiJourneesLibres.forEach((jour, moment) {
      final di = donnees.jours.indexOf(jour);
      if (di < 0) return;
      for (var p = 0; p < _s; p++) {
        final libre = moment == 'journee' || (moment == 'matin' ? _matin[p] : !_matin[p]);
        if (libre) _bloqueTous[di * _s + p] = true;
      }
    });

    // Indisponibilités.
    for (final ind in donnees.indisponibilites) {
      final cible = ind.enseignantId != null
          ? _enseignantBloque[_enseignants[ind.enseignantId]!]
          : ind.salleId != null
              ? _salleBloquee[_salles[ind.salleId]!]
              : ind.classeId != null
                  ? _classeBloquee[_classes[ind.classeId]!]
                  : _bloqueTous;
      for (var di = 0; di < _nbJours; di++) {
        if (ind.jour != null && donnees.jours[di] != ind.jour) continue;
        for (var p = 0; p < _s; p++) {
          final c = donnees.creneaux[_creneauxCours[p]];
          if (ind.chevauche(c.debutMinutes, c.finMinutes)) cible[di * _s + p] = true;
        }
      }
    }

    // Unités : séances fixes (verrouillées) puis séances à placer.
    for (final f in donnees.seancesFixes) {
      final ci = _classes[f.classeId]!;
      final u = _Unite(
        activite: -1,
        classe: ci,
        groupe: f.groupeId == null ? -1 : _groupes[f.groupeId]!,
        enseignant: f.enseignantId == null ? -1 : _enseignants[f.enseignantId]!,
        salle: f.salleId == null ? -1 : _salles[f.salleId]!,
        minutes: f.finMinutes - f.debutMinutes,
        fixe: true,
        semaine: _semaine(f.semaine),
      );
      u.cases = _casesFixes(f);
      _unites.add(u);
    }
    for (var a = 0; a < donnees.cours.length; a++) {
      final c = donnees.cours[a];
      final ci = _classes[c.classeId]!;
      for (final duree in c.seances()) {
        _unites.add(_Unite(
          activite: a,
          classe: ci,
          groupe: c.groupeId == null ? -1 : _groupes[c.groupeId]!,
          enseignant: c.enseignantId == null ? -1 : _enseignants[c.enseignantId]!,
          salle: c.salleId == null ? -1 : _salles[c.salleId]!,
          minutes: duree,
          semaine: _semaine(c.semaine),
        ));
      }
    }

    _parClasse = [for (var i = 0; i < _classes.length; i++) <int>[]];
    _parEnseignant = [for (var i = 0; i < _enseignants.length; i++) <int>[]];
    _parSalle = [for (var i = 0; i < _salles.length; i++) <int>[]];
    _chargeClasse = List<int>.filled(_classes.length, 0);
    for (var i = 0; i < _unites.length; i++) {
      final u = _unites[i];
      _parClasse[u.classe].add(i);
      if (u.enseignant >= 0) _parEnseignant[u.enseignant].add(i);
      if (u.salle >= 0) _parSalle[u.salle].add(i);
      if (!u.fixe) _chargeClasse[u.classe] += _s == 0 ? 1 : max(1, _besoin(0, u.minutes));
    }
    _activiteJour = [for (var a = 0; a < donnees.cours.length; a++) List<int>.filled(_nbJours, 0)];
    _maxParJour = [
      for (final c in donnees.cours) max(1, (c.seances().length / max(1, _nbJours)).ceil()),
    ];
  }

  /// Cases (jour × créneau) d'une séance verrouillée, par chevauchement.
  List<int> _casesFixes(SeanceFixeEmploi f) {
    final di = donnees.jours.indexOf(f.jour);
    if (di < 0) return const [];
    return [
      for (var p = 0; p < _s; p++)
        if (donnees.creneaux[_creneauxCours[p]].debutMinutes < f.finMinutes &&
            donnees.creneaux[_creneauxCours[p]].finMinutes > f.debutMinutes)
          di * _s + p,
    ];
  }

  /// Nombre de créneaux consécutifs nécessaires à partir de p (-1 si
  /// impossible).
  int _besoin(int p, int minutes) {
    final cle = p * 10000 + minutes;
    return _cacheBesoin.putIfAbsent(cle, () {
      var total = 0;
      for (var k = 0; k < _suite[p]; k++) {
        total += donnees.creneaux[_creneauxCours[p + k]].minutes;
        if (total >= minutes - 5) return k + 1;
      }
      return -1;
    });
  }

  void _vider() {
    for (final l in [..._classeEntiere, ..._classeGroupes, ..._groupeOccupe, ..._enseignantOccupe, ..._salleOccupee]) {
      l.fillRange(0, l.length, 0);
    }
    for (final l in _activiteJour) {
      l.fillRange(0, l.length, 0);
    }
    for (var i = 0; i < _unites.length; i++) {
      final u = _unites[i];
      if (u.fixe) {
        _marquer(u, u.cases, 1);
      } else {
        u.position = -1;
        u.cases = const [];
        u.ejections = 0;
      }
    }
  }

  // ============================================================ occupation

  // Semaines A/B (REG-41) : chaque compteur d'occupation porte la semaine A
  // dans ses unités et la semaine B par milliers. Une séance de chaque
  // semaine compte des deux côtés ; « > 0 » reste « occupé » pour le reste
  // du moteur.
  static int _poids(int semaine) => semaine == 1 ? 1 : (semaine == 2 ? 1000 : 1001);
  static bool _gene(int compteur, int semaine) =>
      semaine == 1 ? compteur % 1000 > 0 : (semaine == 2 ? compteur >= 1000 : compteur > 0);

  void _marquer(_Unite u, List<int> cases, int signe) {
    final delta = signe * _poids(u.semaine);
    for (final x in cases) {
      if (u.groupe < 0) {
        _classeEntiere[u.classe][x] += delta;
      } else {
        _classeGroupes[u.classe][x] += delta;
        _groupeOccupe[u.groupe][x] += delta;
      }
      if (u.enseignant >= 0) _enseignantOccupe[u.enseignant][x] += delta;
      if (u.salle >= 0) _salleOccupee[u.salle][x] += delta;
    }
  }

  List<int> _casesDe(int position, int k) => [for (var j = 0; j < k; j++) position + j];

  void _placer(int i, int position) {
    final u = _unites[i];
    final k = _besoin(position % _s, u.minutes);
    u.position = position;
    u.cases = _casesDe(position, k);
    _marquer(u, u.cases, 1);
    if (u.activite >= 0) _activiteJour[u.activite][position ~/ _s]++;
  }

  void _retirer(int i) {
    final u = _unites[i];
    if (u.position < 0) return;
    _marquer(u, u.cases, -1);
    if (u.activite >= 0) _activiteJour[u.activite][u.position ~/ _s]--;
    u.position = -1;
    u.cases = const [];
  }

  /// La séance i peut-elle commencer en [position] ? (i non placée)
  bool _possible(int i, int position) {
    final u = _unites[i];
    final p = position % _s;
    final di = position ~/ _s;
    final k = _besoin(p, u.minutes);
    if (k < 0) return false;
    if (u.activite >= 0 && _activiteJour[u.activite][di] >= _maxParJour[u.activite]) return false;
    for (var j = 0; j < k; j++) {
      final x = position + j;
      if (_bloqueTous[x] || _classeBloquee[u.classe][x]) return false;
      if (_gene(_classeEntiere[u.classe][x], u.semaine)) return false;
      if (u.groupe < 0) {
        if (_gene(_classeGroupes[u.classe][x], u.semaine)) return false;
      } else if (_gene(_groupeOccupe[u.groupe][x], u.semaine)) {
        return false;
      }
      if (u.enseignant >= 0 && (_gene(_enseignantOccupe[u.enseignant][x], u.semaine) || _enseignantBloque[u.enseignant][x])) {
        return false;
      }
      if (u.salle >= 0 && (_gene(_salleOccupee[u.salle][x], u.semaine) || _salleBloquee[u.salle][x])) return false;
    }
    return true;
  }

  List<int> _positionsPossibles(int i) => [
        for (var x = 0; x < _cases; x++)
          if (_possible(i, x)) x,
      ];

  // ================================================================== coût

  bool _classeOccupee(int c, int x) => _classeEntiere[c][x] > 0 || _classeGroupes[c][x] > 0;

  /// Trous d'une journée : créneaux vides entre le premier et le dernier
  /// créneau occupé.
  int _trous(bool Function(int x) occupe, int di) {
    var premier = -1;
    var dernier = -1;
    var occupes = 0;
    for (var p = 0; p < _s; p++) {
      if (occupe(di * _s + p)) {
        if (premier < 0) premier = p;
        dernier = p;
        occupes++;
      }
    }
    if (premier < 0) return 0;
    return (dernier - premier + 1) - occupes;
  }

  double _coutClasseJour(int c, int di) => _r.trousEleves * 3.0 * _trous((x) => _classeOccupee(c, x), di);

  double _coutEnseignantJour(int t, int di) {
    var present = false;
    for (var p = 0; p < _s && !present; p++) {
      present = _enseignantOccupe[t][di * _s + p] > 0;
    }
    if (!present) return 0;
    return _r.trousEnseignants * 1.5 * _trous((x) => _enseignantOccupe[t][x] > 0, di) + _r.regrouperEnseignants * 1.0;
  }

  double _coutEquilibre(int c) {
    if (_r.equilibreJournees == 0) return 0;
    final moyenne = _chargeClasse[c] / _nbJours;
    var cout = 0.0;
    for (var di = 0; di < _nbJours; di++) {
      var charge = 0;
      for (var p = 0; p < _s; p++) {
        if (_classeOccupee(c, di * _s + p)) charge++;
      }
      final ecart = charge - moyenne;
      cout += ecart * ecart;
    }
    return _r.equilibreJournees * 0.3 * cout;
  }

  double _coutActivite(int a) {
    if (a < 0 || _r.repartition == 0) return 0;
    final jours = _activiteJour[a];
    var cout = 0.0;
    for (var di = 0; di < _nbJours; di++) {
      if (jours[di] > 1) cout += (jours[di] - 1) * 4.0;
      // Deux jours de suite : à éviter pour une matière à peu de séances.
      if (di + 1 < _nbJours && jours[di] > 0 && jours[di + 1] > 0 && donnees.jours[di + 1] == donnees.jours[di] + 1) {
        cout += 1.0;
      }
    }
    return _r.repartition * cout;
  }

  double _coutUnite(_Unite u) {
    if (u.position < 0 || u.activite < 0) return 0;
    var cout = 0.0;
    final p = u.position % _s;
    final coefficient = donnees.cours[u.activite].coefficient;
    if (coefficient >= _r.seuilMatierePrincipale && !_matin[p]) {
      cout += _r.principalesLeMatin * (1.0 + coefficient - _r.seuilMatierePrincipale);
    }
    if (u.cases.isNotEmpty && u.cases.last % _s == _dernier) cout += _r.eviterDerniereHeure * 0.5;
    return cout;
  }

  /// Séance non placée : très coûteuse (un emploi du temps complet passe
  /// toujours avant un emploi du temps « joli »).
  static const _coutNonPlacee = 1000.0;

  double _coutTotal() {
    var cout = 0.0;
    for (var c = 0; c < _classes.length; c++) {
      for (var di = 0; di < _nbJours; di++) {
        cout += _coutClasseJour(c, di);
      }
      cout += _coutEquilibre(c);
    }
    for (var t = 0; t < _enseignants.length; t++) {
      for (var di = 0; di < _nbJours; di++) {
        cout += _coutEnseignantJour(t, di);
      }
    }
    for (var a = 0; a < donnees.cours.length; a++) {
      cout += _coutActivite(a);
    }
    for (final u in _unites) {
      if (u.fixe) continue;
      cout += u.position < 0 ? _coutNonPlacee : _coutUnite(u);
    }
    return cout;
  }

  /// Coût des seules parties touchées par un changement des séances [ids]
  /// sur les jours [jours].
  double _coutLocal(Iterable<int> ids, Set<int> jours) {
    final classes = <int>{};
    final enseignants = <int>{};
    final activites = <int>{};
    var cout = 0.0;
    for (final i in ids) {
      final u = _unites[i];
      classes.add(u.classe);
      if (u.enseignant >= 0) enseignants.add(u.enseignant);
      if (u.activite >= 0) activites.add(u.activite);
      cout += u.position < 0 ? _coutNonPlacee : _coutUnite(u);
    }
    for (final c in classes) {
      for (final di in jours) {
        cout += _coutClasseJour(c, di);
      }
      cout += _coutEquilibre(c);
    }
    for (final t in enseignants) {
      for (final di in jours) {
        cout += _coutEnseignantJour(t, di);
      }
    }
    for (final a in activites) {
      cout += _coutActivite(a);
    }
    return cout;
  }

  // ============================================================ construction

  void _construire(Stopwatch chrono, int limiteMs) {
    final aPlacer = <int>[
      for (var i = 0; i < _unites.length; i++)
        if (!_unites[i].fixe) i,
    ];
    // Les plus longues d'abord, à difficulté égale.
    aPlacer.shuffle(_hasard);
    final file = aPlacer.toSet();
    var garde = aPlacer.length * 30;
    while (file.isNotEmpty && garde-- > 0) {
      // Temps écoulé : les séances restantes prennent la première place
      // libre ; l'amélioration fera le reste.
      if (chrono.elapsedMilliseconds > limiteMs) {
        for (final i in file) {
          final places = _positionsPossibles(i);
          if (places.isNotEmpty) _placer(i, places[_hasard.nextInt(places.length)]);
        }
        return;
      }
      // La séance qui a le moins de places possibles (DSatur).
      int? choisie;
      var moinsDePlaces = 1 << 30;
      List<int> places = const [];
      for (final i in file) {
        final possibles = _positionsPossibles(i);
        final rang = possibles.length * 4 - _unites[i].minutes ~/ 30;
        if (rang < moinsDePlaces) {
          moinsDePlaces = rang;
          choisie = i;
          places = possibles;
          if (possibles.isEmpty) break;
        }
      }
      final i = choisie!;
      file.remove(i);
      if (places.isNotEmpty) {
        _placer(i, _meilleurePlace(i, places));
        continue;
      }
      // Aucune place : éjection des séances qui gênent le moins.
      final ejectees = _ejecterPour(i);
      if (ejectees == null) continue; // reste non placée
      file.addAll(ejectees);
    }
  }

  int _meilleurePlace(int i, List<int> places) {
    var meilleure = places.first;
    var meilleurCout = double.infinity;
    // Échantillon si beaucoup de places : rapide et assez bon.
    final candidats = places.length > 24 ? (places.toList()..shuffle(_hasard)).sublist(0, 24) : places;
    for (final x in candidats) {
      final jours = {x ~/ _s};
      final avant = _coutLocal([i], jours);
      _placer(i, x);
      final apres = _coutLocal([i], jours) - avant + _hasard.nextDouble() * 0.01;
      _retirer(i);
      if (apres < meilleurCout) {
        meilleurCout = apres;
        meilleure = x;
      }
    }
    return meilleure;
  }

  /// Place la séance i en retirant au plus deux séances déplaçables qui
  /// occupent la place ; renvoie les séances retirées, ou null si rien
  /// n'est possible (indisponibilités, séances verrouillées…).
  List<int>? _ejecterPour(int i) {
    final u = _unites[i];
    if (u.ejections > 12) return null;
    List<int>? meilleure;
    var meilleurePosition = -1;
    for (var x = 0; x < _cases; x++) {
      final gene = _genes(i, x);
      if (gene == null || gene.isEmpty || gene.length > 2) continue;
      if (gene.any((g) => _unites[g].ejections > 12)) continue;
      if (meilleure == null || gene.length < meilleure.length || (gene.length == meilleure.length && _hasard.nextBool())) {
        meilleure = gene;
        meilleurePosition = x;
      }
    }
    if (meilleure == null) return null;
    final anciennes = {for (final g in meilleure) g: _unites[g].position};
    for (final g in meilleure) {
      _retirer(g);
    }
    if (!_possible(i, meilleurePosition)) {
      // Rien de gagné : on remet tout en place.
      anciennes.forEach(_placer);
      return null;
    }
    for (final g in meilleure) {
      _unites[g].ejections++;
    }
    _placer(i, meilleurePosition);
    u.ejections++;
    return meilleure;
  }

  /// Séances déplaçables qui empêchent i de commencer en x ; null si un
  /// obstacle impossible à lever (indisponibilité, séance verrouillée,
  /// bloc trop court, limite par jour).
  List<int>? _genes(int i, int x) {
    final u = _unites[i];
    final p = x % _s;
    final di = x ~/ _s;
    final k = _besoin(p, u.minutes);
    if (k < 0) return null;
    if (u.activite >= 0 && _activiteJour[u.activite][di] >= _maxParJour[u.activite]) return null;
    final cases = _casesDe(x, k);
    for (final c in cases) {
      if (_bloqueTous[c] || _classeBloquee[u.classe][c]) return null;
      if (u.enseignant >= 0 && _enseignantBloque[u.enseignant][c]) return null;
      if (u.salle >= 0 && _salleBloquee[u.salle][c]) return null;
    }
    final gene = <int>{};
    // Semaines A et B (REG-41) : une séance A et une séance B ne se gênent pas.
    bool chevauche(_Unite v) =>
        (u.semaine == 0 || v.semaine == 0 || u.semaine == v.semaine) && v.cases.any(cases.contains);
    for (final j in _parClasse[u.classe]) {
      final v = _unites[j];
      if (j == i || v.position < 0 && !v.fixe) continue;
      final conflit = u.groupe < 0 || v.groupe < 0 || u.groupe == v.groupe;
      if (conflit && chevauche(v)) {
        if (v.fixe) return null;
        gene.add(j);
      }
    }
    if (u.enseignant >= 0) {
      for (final j in _parEnseignant[u.enseignant]) {
        final v = _unites[j];
        if (j == i || (v.position < 0 && !v.fixe)) continue;
        if (chevauche(v)) {
          if (v.fixe) return null;
          gene.add(j);
        }
      }
    }
    if (u.salle >= 0) {
      for (final j in _parSalle[u.salle]) {
        final v = _unites[j];
        if (j == i || (v.position < 0 && !v.fixe)) continue;
        if (chevauche(v)) {
          if (v.fixe) return null;
          gene.add(j);
        }
      }
    }
    return gene.toList();
  }

  // ============================================================ amélioration

  void _ameliorer(Duration budget, Stopwatch chrono) {
    final mobiles = [
      for (var i = 0; i < _unites.length; i++)
        if (!_unites[i].fixe) i,
    ];
    if (mobiles.isEmpty) return;
    final fin = chrono.elapsedMilliseconds + budget.inMilliseconds;
    const t0 = 6.0;
    const t1 = 0.05;
    var iteration = 0;
    while (true) {
      if ((iteration & 63) == 0) {
        final reste = fin - chrono.elapsedMilliseconds;
        if (reste <= 0) break;
        // Nouvel essai pour les séances non placées, régulièrement.
        if ((iteration & 1023) == 0) _reessayerNonPlacees(mobiles);
      }
      iteration++;
      final avancement = 1 - max(0, fin - chrono.elapsedMilliseconds) / max(1, budget.inMilliseconds);
      final temperature = t0 * pow(t1 / t0, avancement);
      final i = mobiles[_hasard.nextInt(mobiles.length)];
      if (_unites[i].position < 0) continue;
      if (_hasard.nextInt(3) == 0) {
        _essayerEchange(i, temperature.toDouble());
      } else {
        _essayerDeplacement(i, temperature.toDouble());
      }
    }
    _reessayerNonPlacees(mobiles);
  }

  bool _accepter(double delta, double temperature) =>
      delta <= 0 || _hasard.nextDouble() < exp(-delta / max(1e-6, temperature));

  void _essayerDeplacement(int i, double temperature) {
    final u = _unites[i];
    final ancienne = u.position;
    final x = _hasard.nextInt(_cases);
    if (x == ancienne) return;
    final jours = {ancienne ~/ _s, x ~/ _s};
    final avant = _coutLocal([i], jours);
    _retirer(i);
    if (!_possible(i, x)) {
      _placer(i, ancienne);
      return;
    }
    _placer(i, x);
    final delta = _coutLocal([i], jours) - avant;
    if (!_accepter(delta, temperature)) {
      _retirer(i);
      _placer(i, ancienne);
    }
  }

  /// Échange avec une autre séance de la même classe.
  void _essayerEchange(int i, double temperature) {
    final u = _unites[i];
    final voisines = _parClasse[u.classe];
    final j = voisines[_hasard.nextInt(voisines.length)];
    final v = _unites[j];
    if (j == i || v.fixe || v.position < 0 || v.position == u.position) return;
    final pu = u.position;
    final pv = v.position;
    final jours = {pu ~/ _s, pv ~/ _s};
    final avant = _coutLocal([i, j], jours);
    _retirer(i);
    _retirer(j);
    if (_possible(i, pv)) {
      _placer(i, pv);
      if (_possible(j, pu)) {
        _placer(j, pu);
        final delta = _coutLocal([i, j], jours) - avant;
        if (_accepter(delta, temperature)) return;
        _retirer(j);
      }
      _retirer(i);
    }
    _placer(i, pu);
    _placer(j, pv);
  }

  void _reessayerNonPlacees(List<int> mobiles) {
    for (final i in mobiles) {
      if (_unites[i].position >= 0) continue;
      final places = _positionsPossibles(i);
      if (places.isNotEmpty) {
        _placer(i, _meilleurePlace(i, places));
      } else {
        final ejectees = _ejecterPour(i);
        if (ejectees != null) {
          for (final g in ejectees) {
            final p = _positionsPossibles(g);
            if (p.isNotEmpty) _placer(g, _meilleurePlace(g, p));
          }
        }
      }
    }
  }

  // ================================================================ résultat

  ResultatEmploi _resultat() {
    final seances = <SeancePlacee>[];
    final nonPlacees = <SeanceNonPlacee>[];
    for (final u in _unites) {
      if (u.fixe) continue;
      final c = donnees.cours[u.activite];
      if (u.position < 0) {
        nonPlacees.add(_nonPlacee(u, _raison(_unites.indexOf(u))));
        continue;
      }
      final premier = donnees.creneaux[_creneauxCours[u.cases.first % _s]];
      final dernier = donnees.creneaux[_creneauxCours[u.cases.last % _s]];
      seances.add(SeancePlacee(
        cours: c,
        jour: donnees.jours[u.position ~/ _s],
        debut: premier.debut,
        fin: dernier.fin,
      ));
    }

    var trousEleves = 0;
    for (var c = 0; c < _classes.length; c++) {
      for (var di = 0; di < _nbJours; di++) {
        trousEleves += _trous((x) => _classeOccupee(c, x), di);
      }
    }
    var trousEnseignants = 0;
    for (var t = 0; t < _enseignants.length; t++) {
      for (var di = 0; di < _nbJours; di++) {
        trousEnseignants += _trous((x) => _enseignantOccupe[t][x] > 0, di);
      }
    }
    var memeJour = 0;
    for (final jours in _activiteJour) {
      for (final n in jours) {
        if (n > 1) memeJour += n - 1;
      }
    }
    var principalesApresMidi = 0;
    for (final u in _unites) {
      if (u.fixe || u.position < 0) continue;
      if (donnees.cours[u.activite].coefficient >= _r.seuilMatierePrincipale && !_matin[u.position % _s]) {
        principalesApresMidi++;
      }
    }
    final total = _unites.where((u) => !u.fixe).length;
    final placees = seances.length;
    // Qualité : 100 % = toutes les séances placées, sans trou pour les
    // élèves, matières principales le matin, peu de trous enseignants.
    final penalites = trousEleves * 4 + trousEnseignants * 1 + memeJour * 2 + principalesApresMidi * 1;
    final qualiteForme = total == 0 ? 100.0 : max(0.0, 100.0 - 100.0 * penalites / (total * 2));
    final qualite = total == 0 ? 100.0 : qualiteForme * placees / total;
    return ResultatEmploi(
      seances: seances,
      nonPlacees: nonPlacees,
      bilan: BilanQualite(
        seancesPlacees: placees,
        seancesTotal: total,
        trousEleves: trousEleves,
        trousEnseignants: trousEnseignants,
        matieresMemeJour: memeJour,
        principalesApresMidi: principalesApresMidi,
        qualite: qualite,
      ),
    );
  }

  SeanceNonPlacee _nonPlacee(_Unite u, String raison) {
    final c = donnees.cours[u.activite];
    return SeanceNonPlacee(cours: c, minutes: u.minutes, raison: raison);
  }

  /// Pourquoi la séance i n'a pas trouvé de place : l'obstacle le plus
  /// fréquent parmi tous les créneaux de la semaine.
  String _raison(int i) {
    final u = _unites[i];
    var bloc = 0, jourPlein = 0, indispo = 0, classe = 0, enseignant = 0, salle = 0;
    for (var x = 0; x < _cases; x++) {
      final p = x % _s;
      final k = _besoin(p, u.minutes);
      if (k < 0) {
        bloc++;
        continue;
      }
      if (u.activite >= 0 && _activiteJour[u.activite][x ~/ _s] >= _maxParJour[u.activite]) {
        jourPlein++;
        continue;
      }
      var raison = '';
      for (var j = 0; j < k && raison.isEmpty; j++) {
        final c = x + j;
        if (_bloqueTous[c] || _classeBloquee[u.classe][c] ||
            (u.enseignant >= 0 && _enseignantBloque[u.enseignant][c]) ||
            (u.salle >= 0 && _salleBloquee[u.salle][c])) {
          raison = 'indispo';
        } else if (_gene(_classeEntiere[u.classe][c], u.semaine) ||
            (u.groupe < 0
                ? _gene(_classeGroupes[u.classe][c], u.semaine)
                : _gene(_groupeOccupe[u.groupe][c], u.semaine))) {
          raison = 'classe';
        } else if (u.enseignant >= 0 && _gene(_enseignantOccupe[u.enseignant][c], u.semaine)) {
          raison = 'enseignant';
        } else if (u.salle >= 0 && _gene(_salleOccupee[u.salle][c], u.semaine)) {
          raison = 'salle';
        }
      }
      switch (raison) {
        case 'indispo':
          indispo++;
        case 'classe':
          classe++;
        case 'enseignant':
          enseignant++;
        case 'salle':
          salle++;
      }
    }
    final c = donnees.cours[u.activite];
    final candidats = <String, int>{
      'Pas de bloc de ${_h(u.minutes)} sans pause dans la grille': bloc,
      'Déjà une séance de cette matière chaque jour possible': jourPlein,
      'Indisponibilités ou demi-journées libérées': indispo,
      'Emploi du temps de la classe complet': classe,
      '${c.nomEnseignant ?? 'L’enseignant'} déjà occupé sur les créneaux libres de la classe': enseignant,
      'Salle déjà occupée': salle,
    };
    final tri = candidats.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return tri.first.key;
  }

  static String _h(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m min';
    return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
  }
}

/// 0 : chaque semaine ; 1 : semaine A ; 2 : semaine B (REG-41).
int _semaine(String? s) => s == 'A' ? 1 : (s == 'B' ? 2 : 0);

class _Unite {
  _Unite({
    required this.activite,
    required this.classe,
    required this.groupe,
    required this.enseignant,
    required this.salle,
    required this.minutes,
    this.fixe = false,
    this.semaine = 0,
  });

  final int semaine;

  final int activite;
  final int classe;
  final int groupe;
  final int enseignant;
  final int salle;
  final int minutes;
  final bool fixe;
  int position = -1;
  List<int> cases = const [];
  int ejections = 0;
}

// =================================================================== données

int minutesDe(String hhmm) {
  final parts = hhmm.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

String hhmmDe(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// Un créneau de la journée-type : cours, récréation ou pause de midi.
class CreneauEmploi {
  const CreneauEmploi({required this.debut, required this.fin, this.cours = true, this.libelle});

  factory CreneauEmploi.depuisJson(Map<String, dynamic> j) => CreneauEmploi(
        debut: j['debut'] as String,
        fin: j['fin'] as String,
        cours: (j['type'] as String? ?? 'cours') == 'cours',
        libelle: j['libelle'] as String?,
      );

  Map<String, dynamic> versJson() => {
        'debut': debut,
        'fin': fin,
        'type': cours ? 'cours' : 'pause',
        if (libelle != null) 'libelle': libelle,
      };

  /// `HH:mm`.
  final String debut;
  final String fin;
  final bool cours;
  final String? libelle;

  int get debutMinutes => minutesDe(debut);
  int get finMinutes => minutesDe(fin);
  int get minutes => finMinutes - debutMinutes;
}

/// Poids des critères de qualité (0 = ignoré, 10 = très important).
class ReglesEmploi {
  const ReglesEmploi({
    this.trousEleves = 10,
    this.trousEnseignants = 5,
    this.repartition = 6,
    this.principalesLeMatin = 4,
    this.equilibreJournees = 3,
    this.regrouperEnseignants = 2,
    this.eviterDerniereHeure = 1,
    this.seuilMatierePrincipale = 3,
  });

  factory ReglesEmploi.depuisJson(Map<String, dynamic>? j) {
    const d = ReglesEmploi();
    int lire(String cle, int defaut) => (j?[cle] as num?)?.toInt() ?? defaut;
    return ReglesEmploi(
      trousEleves: lire('trous_eleves', d.trousEleves),
      trousEnseignants: lire('trous_enseignants', d.trousEnseignants),
      repartition: lire('repartition', d.repartition),
      principalesLeMatin: lire('principales_le_matin', d.principalesLeMatin),
      equilibreJournees: lire('equilibre_journees', d.equilibreJournees),
      regrouperEnseignants: lire('regrouper_enseignants', d.regrouperEnseignants),
      eviterDerniereHeure: lire('eviter_derniere_heure', d.eviterDerniereHeure),
      seuilMatierePrincipale: lire('seuil_matiere_principale', d.seuilMatierePrincipale),
    );
  }

  Map<String, dynamic> versJson() => {
        'trous_eleves': trousEleves,
        'trous_enseignants': trousEnseignants,
        'repartition': repartition,
        'principales_le_matin': principalesLeMatin,
        'equilibre_journees': equilibreJournees,
        'regrouper_enseignants': regrouperEnseignants,
        'eviter_derniere_heure': eviterDerniereHeure,
        'seuil_matiere_principale': seuilMatierePrincipale,
      };

  ReglesEmploi copier({
    int? trousEleves,
    int? trousEnseignants,
    int? repartition,
    int? principalesLeMatin,
    int? equilibreJournees,
    int? regrouperEnseignants,
    int? eviterDerniereHeure,
    int? seuilMatierePrincipale,
  }) =>
      ReglesEmploi(
        trousEleves: trousEleves ?? this.trousEleves,
        trousEnseignants: trousEnseignants ?? this.trousEnseignants,
        repartition: repartition ?? this.repartition,
        principalesLeMatin: principalesLeMatin ?? this.principalesLeMatin,
        equilibreJournees: equilibreJournees ?? this.equilibreJournees,
        regrouperEnseignants: regrouperEnseignants ?? this.regrouperEnseignants,
        eviterDerniereHeure: eviterDerniereHeure ?? this.eviterDerniereHeure,
        seuilMatierePrincipale: seuilMatierePrincipale ?? this.seuilMatierePrincipale,
      );

  final int trousEleves;
  final int trousEnseignants;
  final int repartition;
  final int principalesLeMatin;
  final int equilibreJournees;
  final int regrouperEnseignants;
  final int eviterDerniereHeure;

  /// Coefficient à partir duquel une matière est « principale » (le matin).
  final int seuilMatierePrincipale;
}

/// Un cours à placer : une classe (ou un groupe), une matière, un
/// enseignant, un volume hebdomadaire découpé en séances.
class CoursAPlacer {
  const CoursAPlacer({
    required this.id,
    required this.classeId,
    required this.nomClasse,
    this.groupeId,
    this.nomGroupe,
    this.enseignantId,
    this.nomEnseignant,
    this.matiereId,
    this.nomMatiere,
    this.salleId,
    required this.minutesParSemaine,
    this.dureeSeance = 60,
    this.coefficient = 1,
    this.semaine,
  });

  /// Une semaine sur deux : « A » ou « B » ; nul = chaque semaine (REG-41).
  final String? semaine;

  /// Identifiant de l'affectation d'origine.
  final String id;
  final String classeId;
  final String nomClasse;
  final String? groupeId;
  final String? nomGroupe;
  final String? enseignantId;
  final String? nomEnseignant;
  final String? matiereId;
  final String? nomMatiere;
  final String? salleId;
  final int minutesParSemaine;
  final int dureeSeance;
  /// Coefficient de la matière (décimal depuis REG-33).
  final double coefficient;

  String get libelle =>
      '${nomMatiere ?? 'Cours'} — $nomClasse${nomGroupe == null ? '' : ' ($nomGroupe)'}';

  /// Durées des séances de la semaine : séances pleines, plus une séance
  /// plus courte pour le reste (au moins 30 min).
  List<int> seances() {
    if (minutesParSemaine <= 0 || dureeSeance <= 0) return const [];
    final n = minutesParSemaine ~/ dureeSeance;
    final reste = minutesParSemaine - n * dureeSeance;
    return [
      for (var i = 0; i < n; i++) dureeSeance,
      if (reste >= 30) reste,
    ];
  }
}

/// Séance verrouillée (ou saisie à la main et gardée) : occupe sa place.
class SeanceFixeEmploi {
  const SeanceFixeEmploi({
    required this.classeId,
    this.groupeId,
    this.enseignantId,
    this.salleId,
    required this.jour,
    required this.debut,
    required this.fin,
    this.semaine,
  });

  final String classeId;
  final String? groupeId;
  final String? enseignantId;
  final String? salleId;
  final String? semaine;
  final int jour;
  final String debut;
  final String fin;

  int get debutMinutes => minutesDe(debut);
  int get finMinutes => minutesDe(fin);
}

/// Indisponibilité d'un enseignant, d'une classe ou d'une salle (jour
/// entier si les heures sont absentes ; toute la semaine si le jour l'est).
class IndisponibiliteEmploi {
  const IndisponibiliteEmploi({this.enseignantId, this.classeId, this.salleId, this.jour, this.debut, this.fin});

  final String? enseignantId;
  final String? classeId;
  final String? salleId;
  final int? jour;
  final String? debut;
  final String? fin;

  bool chevauche(int debutMinutes, int finMinutes) {
    if (debut == null || fin == null) return true;
    return minutesDe(debut!) < finMinutes && minutesDe(fin!) > debutMinutes;
  }
}

class DonneesEmploi {
  const DonneesEmploi({
    required this.jours,
    required this.creneaux,
    this.demiJourneesLibres = const {},
    this.regles = const ReglesEmploi(),
    required this.cours,
    this.seancesFixes = const [],
    this.indisponibilites = const [],
    this.graine = 42,
    this.budget = const Duration(seconds: 6),
  });

  /// 1 = lundi … 7 = dimanche, dans l'ordre.
  final List<int> jours;
  final List<CreneauEmploi> creneaux;

  /// Jour → « matin », « apres_midi » ou « journee ».
  final Map<int, String> demiJourneesLibres;
  final ReglesEmploi regles;
  final List<CoursAPlacer> cours;
  final List<SeanceFixeEmploi> seancesFixes;
  final List<IndisponibiliteEmploi> indisponibilites;
  final int graine;

  /// Temps de calcul accordé (amélioration comprise).
  final Duration budget;
}

class SeancePlacee {
  const SeancePlacee({required this.cours, required this.jour, required this.debut, required this.fin});

  final CoursAPlacer cours;
  final int jour;
  final String debut;
  final String fin;

  Map<String, dynamic> versJsonServeur() => {
        'classe_id': cours.classeId,
        'groupe_id': cours.groupeId,
        'enseignant_profile_id': cours.enseignantId,
        'programme_matiere_id': cours.matiereId,
        'salle_id': cours.salleId,
        'affectation_id': cours.id,
        'jour_semaine': jour,
        'heure_debut': debut,
        'heure_fin': fin,
        'semaine': cours.semaine,
      };
}

class SeanceNonPlacee {
  const SeanceNonPlacee({required this.cours, required this.minutes, required this.raison});

  final CoursAPlacer cours;
  final int minutes;
  final String raison;
}

class BilanQualite {
  const BilanQualite({
    required this.seancesPlacees,
    required this.seancesTotal,
    required this.trousEleves,
    required this.trousEnseignants,
    required this.matieresMemeJour,
    required this.principalesApresMidi,
    required this.qualite,
  });

  factory BilanQualite.vide(int total) => BilanQualite(
        seancesPlacees: 0,
        seancesTotal: total,
        trousEleves: 0,
        trousEnseignants: 0,
        matieresMemeJour: 0,
        principalesApresMidi: 0,
        qualite: 0,
      );

  final int seancesPlacees;
  final int seancesTotal;
  final int trousEleves;
  final int trousEnseignants;
  final int matieresMemeJour;
  final int principalesApresMidi;

  /// 0 à 100.
  final double qualite;
}

class ResultatEmploi {
  const ResultatEmploi({required this.seances, required this.nonPlacees, required this.bilan});

  final List<SeancePlacee> seances;
  final List<SeanceNonPlacee> nonPlacees;
  final BilanQualite bilan;
}
