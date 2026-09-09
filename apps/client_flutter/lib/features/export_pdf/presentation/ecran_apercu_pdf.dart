import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// Prévisualisation, impression et partage d'un document PDF déjà généré.
///
/// Le document lui-même reste toujours dans la variante claire de la charte
/// de l'établissement (voir `pdf_palette.dart`) — mais l'écran qui l'entoure
/// (barre d'application, fond) suit le thème actif de l'application comme
/// n'importe quel autre écran, y compris en mode sombre (M15bis).
class EcranApercuPdf extends StatelessWidget {
  const EcranApercuPdf({super.key, required this.titre, required this.octets, required this.nomFichier});

  final String titre;
  final Uint8List octets;
  final String nomFichier;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titre)),
      body: PdfPreview(
        build: (format) async => octets,
        pdfFileName: nomFichier,
        canChangeOrientation: false,
        canChangePageFormat: false,
      ),
    );
  }
}
