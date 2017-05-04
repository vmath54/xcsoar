Ce dossier contient des scripts perl pour lire un fichier igc, et pour générer des trames NMEA à partir des enregistrements IGC.

- IGC.pm : c'est l'objet perl permettant de manipuler des infos IGC
- readIGC.pl : script de test
- sendIGCtoNMEA.pl : lit un fichier IGC, et le "rejoue" en envoyant des trames NMEA GPGGA et GPRMC dans une connexion TCP ou UDP.
  Ces trames peuvent être lues par XCSoar.

- sample_flarm.igc : un fichier IGC généré par un FLARM lors d'un vol réel, pour les essais
- sample_xcsoar.igc : un fichier IGC généré par XCSoar lors d'un vol réel, pour les essais


Exécuter sans paramètre, pour avoir de l'info de syntaxe.
Exemple d'utilisation : 
sendIGCtoNMEA.pl -file sample_flarm.igc -ip 192.168.0.106 -proto UDP -minutes2skip 70 -GGA --RMC --POV 

A noter, un fonctionement étrange avec XCSoar :
###############################################

Si on n'envoie que la trame GGA :
---------------------------------
$GPGGA,173314,4843.403,N,00612.265,E,1,12,10,367.0,M,,,,*34

Message "Mauvaise réception GPS" (Attente du signal GPS) ; L'infobox Alt GPS indique 313m (alors que la trame donne 367m), le vario donne des indications

Si on n'envoie que la trame RMC : 
---------------------------------
$GPRMC,181943,A,4843.403,N,00612.265,E,,,,*3F
L'infobox Alt GPS est vide, le vario reste à 0. La partie horizontale du GPS fonctionne : le planeur avance, la vitesse sol est indiquée

Si on envoie les trames GGA et RMC
----------------------------------
C'est OK


XCSoar et driver
****************
Quelque soit le driver de périphérique choisi, les trames essentielles sont reconnues. C'est en particulier le cas des trames GGA et RMC

Si on envoie les trames POV (openvario)
---------------------------------------
$POV,E,2.75*12
donne le vario (+2,75 m/s). Ca prend le dessus sur le GPS pour l'indication de vario

$POV,P,831.28*07
donne la pression (831.28 hPa). On obtient alors dans XCSoar l'info de pression barométrique si le QNH a été saisi


Si on envoie les trames LXWPO (driver LXNAV)
--------------------------------------------
Ca ne marche pas avec XCSoar ; pas compris pourquoi
