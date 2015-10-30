Depot xcsoar de vmath54 - README.txt
------------------------------------
Ce depot contient certains outils en lien avec xcsoar

Dossier "vac"
-------------
Contient des scripts et fichiers permettant d'accéder aux cartes VAC pdf depuis les waypoints des aérodromes proposés par FRA_FULL_HighRes.xcm ou France.cup

- waypointsDetailsWithVAC.txt : a déposer dans XCSoarData. Fichier de détail de waypoints permettant de lier les fichiers pdf aux terrains

- genereDetailsWaypoints.pl : script perl, qui permet de générer le fichier waypointsDetailsWithVAC.txt
                              Il utilise en entrée la base WELT2000.txt, disponible a http://www.segelflug.de/vereine/welt2000/download/WELT2000.TXT
							  
- getVACfiles.pl : script perl, qui permet de récupérer les cartes VAC de France, depuis le site du SIA
