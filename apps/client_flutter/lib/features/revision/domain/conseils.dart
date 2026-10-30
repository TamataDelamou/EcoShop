import 'quiz.dart';

/// Conseil concret pour le parent (J-PAL : une action précise, à temps,
/// marche mieux qu'un message de motivation).
class ConseilParent {
  const ConseilParent(this.texte, {this.competenceId, this.matiereId});

  final String texte;

  /// Compétence ou matière à travailler, pour lancer le quiz qui va avec.
  final String? competenceId;
  final String? matiereId;
}

List<ConseilParent> conseilsParent({
  required String prenom,
  required ResumeRevision resume,
  required PaquetRevision paquet,
  required DateTime maintenant,
}) {
  final conseils = <ConseilParent>[];
  if (paquet.vide) return conseils;

  final derniere = resume.derniereActivite;
  if (derniere == null) {
    conseils.add(ConseilParent(
      'Proposez à $prenom un premier quiz rapide de 5 questions, ensemble : cela prend moins de 5 minutes.',
    ));
  } else {
    final jours = maintenant.difference(derniere).inDays;
    if (jours >= 4) {
      conseils.add(ConseilParent(
        '$prenom n’a pas révisé depuis $jours jours. Un quiz rapide ce soir suffit à reprendre l’habitude.',
      ));
    }
  }

  final aRevoir = resume.competencesARevoir();
  if (aRevoir.isNotEmpty) {
    final k = paquet.competences.where((c) => c.id == aRevoir.first).firstOrNull;
    if (k != null) {
      final matiere = paquet.matieres.where((m) => m.id == k.matiereId).firstOrNull;
      conseils.add(ConseilParent(
        'À travailler : « ${k.libelle} »${matiere == null ? '' : ' (${matiere.nom})'}. Faites le quiz avec $prenom '
        'et demandez-lui d’expliquer chaque bonne réponse avec ses mots.',
        competenceId: k.id,
        matiereId: k.matiereId,
      ));
    }
  }

  if (resume.quizTermines >= 3) {
    conseils.add(ConseilParent(
      '$prenom a terminé ${resume.quizTermines} quiz : félicitez son travail régulier, plus que ses notes.',
    ));
  }
  return conseils;
}
