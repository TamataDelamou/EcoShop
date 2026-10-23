# google_mlkit_text_recognition référence les modules de langue chinois,
# devanagari, japonais et coréen, livrés à part. EcoShop ne reconnaît que
# l'écriture latine (scan d'exercice) : ces modules ne sont pas embarqués,
# R8 doit seulement ignorer leur absence.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
