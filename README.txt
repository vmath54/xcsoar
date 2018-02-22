Depot xcsoar de vmath54 - README.txt
------------------------------------
Ce depot contient certains outils en lien avec xcsoar

Dossier "waypoints"
-------------------
Contient des scripts et fichiers permettant d'accéder aux cartes VAC pdf depuis les waypoints des aérodromes proposés par un fichier .cup
FRA_FULL_HighRes.xcm ou France.cup

- FranceVacEtUlm.cup : c'est le fichier de référence. Il contient l'ensemble des terrains répertoriés sur le site SIA, les terrains militaires et les terrains basULM
                       il est mis à jour à partir des informations provenant de ces 3 sources
					   
- VAC.pm :             librairie perl. Partage des données et procédures utilisées par la plupart des scripts perl décrits ici
							  
- getVACfiles.pl :     script perl, qui permet de récupérer les cartes VAC de France, depuis le site du SIA :
                       https://www.sia.aviation-civile.gouv.fr/aip/enligne/Atlas-VAC/FR/VACProduitPartie.htm
					  
- getMILfiles.pl :    script perl qui permet de récupérer les cartes VAC des bases militaires, depuis
                      http://www.dircam.air.defense.gouv.fr/index.php/infos-aeronautiques/a-vue-france
					  ne récupère pas les terrains ayant même code que des terrains SIA

- getBASULMfiles.pl : script perl, qui permet de récupérer les cartes PDF du site baseULM depuis 
                      http://basulm.ffplum.info/PDF/
					  par défaut, ne récupère pas les terrains ayant même code que des terrains SIA ou MIL

- makeZipFromBasulm.pl : contruit un fichier zip par "grande région", et y dépose les fichiers de basULM correspondants
                      les fichies basULM sont volumineux, ceci permet d'avoir plusieurs fichiers, plus petits
					  
- getInfosFromVACfiles.pl : analyse les fichires pdf issus des bases SIA et MIL
                      compare avec les infos de FranceVacEtUlm.csv, et produit un fichier intermédiaire : listVACfromPDF.csv
					  ATTENTION : utilise le binaire pdftotext.exe (windows) pour analyser le contenu des fichiers pdf
					  
- getInfosFromApiBasulm.pl : recupération des infos basULM, sur tous les terrais répertoriés par la FFPLUM
                      névessite une clé API (un mot de passe d'application), qu'on peut demander à admin.basulm@orange.fr
					  compare avec les infos de FranceVacEtUlm.csv, et produit un fichier intermédiaire : listULMfromAPI.csv					  
					  
- genereDetailsFromCUP.pl : permet de créer un fichier de détails de waypoints a partir d'un fichier .cup
                      ce fichier de détails de waypoints permet de faire le lien entre un terrain, et la carte VAC ou basULM correspondante
					  Voir README.details pour plus d'infos

- regenereReferenceCUPfile.pl : permet de mettre à jour les infos du fichier de référence FranceVacEtUlm.csv
                      génère le fichier FranceVacEtUlm_new.csv à partir du fichier FranceVacEtUlm.csv, et les éventuelles nouvelles infos
                      provenant de listVACfromPDF.csv et listULMfromAPI.csv
					  Voir README.update pour plus d'infos
					  
- France_details.cup et FranceVacEtUlm_details.cup : des fichiers de détail générés avec France.cup et FranceVacEtUlm.cup à l'aide de genereDetailsFromCUP.pl
