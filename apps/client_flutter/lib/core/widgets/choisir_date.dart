import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Date au format JJ/MM/AAAA (« 05/09/2026 »).
String formaterDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year.toString().padLeft(4, '0')}';

/// Lit une date JJ/MM/AAAA ; `null` si incomplète ou impossible (31/02).
DateTime? lireDate(String texte) {
  final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(texte.trim());
  if (m == null) return null;
  final j = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final a = int.parse(m.group(3)!);
  final d = DateTime(a, mo, j);
  if (d.day != j || d.month != mo || d.year != a) return null;
  return d;
}

/// Saisie de date au clavier : seuls les chiffres sont tapés, les barres
/// obliques s'ajoutent toutes seules (« 05092026 » → « 05/09/2026 »).
class FormateurDate extends TextInputFormatter {
  const FormateurDate();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue ancien, TextEditingValue nouveau) {
    var chiffres = nouveau.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (chiffres.length > 8) chiffres = chiffres.substring(0, 8);
    final ajout = nouveau.text.length > ancien.text.length;
    final b = StringBuffer();
    for (var i = 0; i < chiffres.length; i++) {
      b.write(chiffres[i]);
      final finDeBloc = i == 1 || i == 3;
      // Barre entre deux blocs, ou juste après le jour et le mois quand on
      // tape (pas quand on efface : la barre se laisse supprimer).
      if (finDeBloc && (i < chiffres.length - 1 || ajout)) b.write('/');
    }
    final texte = b.toString();
    return TextEditingValue(text: texte, selection: TextSelection.collapsed(offset: texte.length));
  }
}

/// Sélecteur de date d'EcoShop, à la place de `showDatePicker` : calendrier
/// en français **et** champ de saisie JJ/MM/AAAA où les barres obliques
/// s'écrivent toutes seules. Mêmes paramètres que `showDatePicker`.
Future<DateTime?> choisirDate({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
}) {
  DateTime jour(DateTime d) => DateTime(d.year, d.month, d.day);
  final premier = jour(firstDate);
  final dernier = jour(lastDate);
  var initial = jour(initialDate);
  if (initial.isBefore(premier)) initial = premier;
  if (initial.isAfter(dernier)) initial = dernier;
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _DialogueDate(initiale: initial, premiere: premier, derniere: dernier, titre: helpText),
  );
}

class _DialogueDate extends StatefulWidget {
  const _DialogueDate({required this.initiale, required this.premiere, required this.derniere, this.titre});

  final DateTime initiale;
  final DateTime premiere;
  final DateTime derniere;
  final String? titre;

  @override
  State<_DialogueDate> createState() => _DialogueDateState();
}

class _DialogueDateState extends State<_DialogueDate> {
  late DateTime _date = widget.initiale;
  late final _saisie = TextEditingController(text: formaterDate(widget.initiale));
  String? _erreur;
  // Change quand une date tapée au clavier est valide : le calendrier se
  // replace sur son mois.
  int _version = 0;

  @override
  void dispose() {
    _saisie.dispose();
    super.dispose();
  }

  String? _verifier(DateTime? d) {
    if (d == null) return 'Date incomplète ou impossible (JJ/MM/AAAA)';
    if (d.isBefore(widget.premiere)) return 'Pas avant le ${formaterDate(widget.premiere)}';
    if (d.isAfter(widget.derniere)) return 'Pas après le ${formaterDate(widget.derniere)}';
    return null;
  }

  void _saisieModifiee(String texte) {
    if (texte.length < 10) {
      setState(() => _erreur = null);
      return;
    }
    final d = lireDate(texte);
    final erreur = _verifier(d);
    setState(() {
      _erreur = erreur;
      if (erreur == null) {
        _date = d!;
        _version++;
      }
    });
  }

  void _valider() {
    final d = lireDate(_saisie.text);
    final erreur = _verifier(d);
    if (erreur != null) {
      setState(() => _erreur = erreur);
      return;
    }
    Navigator.of(context).pop(d);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titre ?? 'Choisir une date'),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('saisie_date'),
                controller: _saisie,
                keyboardType: TextInputType.number,
                inputFormatters: const [FormateurDate()],
                decoration: InputDecoration(
                  labelText: 'Date',
                  hintText: 'JJ/MM/AAAA',
                  helperText: 'Tapez les chiffres : les barres s’ajoutent seules',
                  errorText: _erreur,
                  prefixIcon: const Icon(Icons.edit_calendar_outlined),
                  border: const OutlineInputBorder(),
                ),
                onChanged: _saisieModifiee,
                onSubmitted: (_) => _valider(),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 320,
                child: CalendarDatePicker(
                  key: ValueKey(_version),
                  initialDate: _date,
                  firstDate: widget.premiere,
                  lastDate: widget.derniere,
                  onDateChanged: (d) => setState(() {
                    _date = d;
                    _erreur = null;
                    _saisie.text = formaterDate(d);
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(key: const Key('valider_date'), onPressed: _valider, child: const Text('Valider')),
      ],
    );
  }
}
