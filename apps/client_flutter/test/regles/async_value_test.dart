import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Règle : jamais `.value` ni `.requireValue` sur un `AsyncValue` dans `lib/`.
///
/// En Riverpod 2, `.value` sur une erreur **relance l'erreur**. Lue pendant
/// la construction d'un widget ou d'un provider, elle fait planter tout
/// l'écran (écran gris en version publiée) — défaut constaté sans réseau,
/// thème lu depuis la liste des pays. Utiliser `.valueOrNull`, `.when` ou un
/// `switch` sur `AsyncData` / `AsyncError`.
///
/// `.value` reste permis sur un `AsyncData` (aucune erreur possible).
void main() {
  test('aucun .value / .requireValue sur un AsyncValue dans lib/', () async {
    final lib = Directory('lib').absolute.path;
    // Sous `flutter test`, l'exécutable est le moteur Flutter : on désigne
    // le SDK Dart livré avec Flutter.
    final racineFlutter = Platform.environment['FLUTTER_ROOT'];
    final collection = AnalysisContextCollection(
      includedPaths: [lib],
      sdkPath: racineFlutter == null
          ? null
          : [racineFlutter, 'bin', 'cache', 'dart-sdk'].join(Platform.pathSeparator),
    );
    final fautes = <String>[];

    for (final contexte in collection.contexts) {
      for (final chemin in contexte.contextRoot.analyzedFiles()) {
        if (!chemin.endsWith('.dart') || chemin.endsWith('.g.dart')) continue;
        final resultat = await contexte.currentSession.getResolvedUnit(chemin);
        if (resultat is! ResolvedUnitResult) continue;
        resultat.unit.accept(_Detecteur(resultat, fautes));
      }
    }

    expect(fautes, isEmpty,
        reason: 'Remplacer par .valueOrNull (ou .when) :\n${fautes.join('\n')}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

final _asyncRisque = RegExp(r'^Async(Value|Error|Loading)<');

class _Detecteur extends RecursiveAstVisitor<void> {
  _Detecteur(this._resultat, this._fautes);

  final ResolvedUnitResult _resultat;
  final List<String> _fautes;

  void _verifier(AstNode noeud, Expression? cible, String nom) {
    if (nom != 'value' && nom != 'requireValue') return;
    final type = cible?.staticType;
    if (type is! InterfaceType) return;
    if (!_asyncRisque.hasMatch(type.getDisplayString())) return;
    final ligne = _resultat.lineInfo.getLocation(noeud.offset).lineNumber;
    final relatif = _resultat.path.substring(_resultat.path.indexOf('lib'));
    _fautes.add('$relatif:$ligne  ${noeud.toSource()}');
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    _verifier(node, node.realTarget, node.propertyName.name);
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _verifier(node, node.prefix, node.identifier.name);
    super.visitPrefixedIdentifier(node);
  }
}
