import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Annonces et cahier de liaison sont des **prototypes locaux** : rien ne
/// part au serveur, aucun autre téléphone ne reçoit ce qui y est écrit (aucune
/// table serveur n'existe pour eux). Ils restent visibles pour les essais
/// (versions debug et profile), avec la mention « Prototype local — non
/// synchronisé », mais sont **masqués dans la version publiée** (`--release`)
/// : aucun parent ne doit écrire un message qui ne part jamais.
///
/// La messagerie prototype n'a déjà aucun point d'entrée.
final prototypesCommunicationVisiblesProvider = Provider<bool>((ref) => !kReleaseMode);
