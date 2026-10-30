import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:ecoshop_client/core/offline/amorcage.dart';

/// REG-35 lot 2 — moteur d'amorçage : lectures d'avance par petits paquets,
/// arrêt propre sans réseau, refus ignorés, annulation.
void main() {
  test('exécute les tâches et celles qu\'elles produisent', () async {
    final lues = <String>[];
    TacheAmorcage simple(String n) => TacheAmorcage.lire(n, () async => lues.add(n));

    final fin = await executerAmorcage([
      TacheAmorcage('Classes', () async {
        lues.add('Classes');
        return [simple('6e A'), simple('6e B')];
      }),
      simple('Annonces'),
    ]);

    expect(fin.issue, IssueAmorcage.termine);
    expect(fin.enCours, isFalse);
    expect(fin.faites, 4);
    expect(fin.total, 4);
    expect(lues.toSet(), {'Classes', '6e A', '6e B', 'Annonces'});
  });

  test('ne dépasse jamais le nombre de lectures simultanées', () async {
    var enCours = 0;
    var maximum = 0;
    final taches = [
      for (var i = 0; i < 20; i++)
        TacheAmorcage.lire('t$i', () async {
          enCours++;
          if (enCours > maximum) maximum = enCours;
          await Future<void>.delayed(const Duration(milliseconds: 2));
          enCours--;
          return null;
        }),
    ];
    final fin = await executerAmorcage(taches, parallele: 4);
    expect(fin.faites, 20);
    expect(maximum, lessThanOrEqualTo(4));
  });

  test('un refus du serveur est compté et n\'arrête pas l\'amorçage', () async {
    final fin = await executerAmorcage([
      TacheAmorcage.lire('Personnel', () => Future.error(StateError('DROITS'))),
      TacheAmorcage.lire('Annonces', () async => null),
    ]);
    expect(fin.issue, IssueAmorcage.termine);
    expect(fin.refusees, 1);
    expect(fin.faites, 2);
  });

  test('sans réseau : arrêt après quelques pannes, à reprendre', () async {
    var appels = 0;
    final fin = await executerAmorcage(
      [
        for (var i = 0; i < 10; i++)
          TacheAmorcage.lire('t$i', () {
            appels++;
            return Future.error(http.ClientException('Network is unreachable'));
          }),
      ],
      parallele: 1,
      pannesMax: 3,
    );
    expect(fin.issue, IssueAmorcage.interrompu);
    expect(appels, 3, reason: 'on n\'insiste pas sur un réseau absent');
  });

  test('une lecture toujours en panne finit abandonnée sans bloquer les autres', () async {
    var autres = 0;
    final fin = await executerAmorcage(
      [
        TacheAmorcage.lire('lente', () => Future.error(TimeoutException('délai'))),
        for (var i = 0; i < 6; i++) TacheAmorcage.lire('ok$i', () async => autres++),
      ],
      parallele: 1,
      pannesMax: 3,
    );
    expect(fin.issue, IssueAmorcage.termine);
    expect(autres, 6);
    expect(fin.refusees, 1);
  });

  test('changement d\'espace : arrêt immédiat', () async {
    var continuer = true;
    var lues = 0;
    final fin = await executerAmorcage(
      [
        for (var i = 0; i < 10; i++)
          TacheAmorcage.lire('t$i', () async {
            lues++;
            if (lues == 2) continuer = false;
            return null;
          }),
      ],
      parallele: 1,
      continuer: () => continuer,
    );
    expect(fin.issue, IssueAmorcage.annule);
    expect(lues, 2);
  });

  test('la progression est publiée à chaque étape', () async {
    final etats = <EtatAmorcage>[];
    await executerAmorcage(
      [for (var i = 0; i < 3; i++) TacheAmorcage.lire('t$i', () async => null)],
      progres: etats.add,
    );
    expect(etats.first.enCours, isTrue);
    expect(etats.last.enCours, isFalse);
    expect(etats.last.progression, 1.0);
  });

  test('lot 3 : une portée inchangée est sautée, les autres lues et signalées', () async {
    final lues = <String>[];
    final signalees = <String, bool>{};
    final fin = await executerAmorcage(
      [
        TacheAmorcage.lire('6e A', () async => lues.add('6e A'), portee: 'classe:a'),
        TacheAmorcage.lire('6e B', () async => lues.add('6e B'), portee: 'classe:b'),
        TacheAmorcage.lire('refus', () => Future.error(StateError('DROITS')), portee: 'classe:c'),
        TacheAmorcage('Classes', () async {
          lues.add('Classes');
          return const [];
        }),
      ],
      ignorer: (t) => t.portee == 'classe:a',
      apres: (t, ok) => signalees[t.libelle] = ok,
    );
    expect(lues, isNot(contains('6e A')));
    expect(lues, containsAll(['6e B', 'Classes']));
    expect(fin.inchangees, 1);
    expect(fin.faites, 4);
    expect(signalees, {'6e B': true, 'refus': false, 'Classes': true});
  });
}
