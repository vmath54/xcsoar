#!/usr/bin/perl
#
# recuperation des cartes VAC de france, depuis le site SIA
#
# En prealable, il faut récupérer, manuellememnt, sur la page d'accueil du site SIA (https://www.sia.aviation-civile.gouv.fr ), la date eAIP ; par exemple, "eAIP_24_MAR_2022"
# auparavant, cette date était récupérée automatiquement ; c'est très difficile maintenant.
#
# Cete date doit être maintenant passée en argument du programme.
#
# Ceci permet de construire l'URL de la page qui répertorie les cartes VAC ; dans l'exemple :
# https://www.sia.aviation-civile.gouv.fr/dvd/eAIP_30_JAN_2020/Atlas-VAC/FR/VACProduitPartie.htm
# ET on peut récupérer le script JS qui répertorie toutes les cartes VAC ; dans notre exemple :
# https://www.sia.aviation-civile.gouv.fr/dvd/eAIP_30_JAN_2020/Atlas-VAC/Javascript/AeroArraysVac.js
#
# grace a ces infos, on reconstruit l'URL d'acces aux PDF des cartes VAC ; par exemple :
# https://www.sia.aviation-civile.gouv.fr/dvd/eAIP_30_JAN_2020/Atlas-VAC/PDF_AIPparSSection/VAC/AD/AD-2.LFEZ.pdf
#

use lib ".";       # necessaire avec strawberry, pour VAC.pm
use VAC;
use Data::Dumper;

use strict;


my $dirDownload = "vac";    # le répertoire qui va contenir les documents pdf charges
my $siteURL = "https://www.sia.aviation-civile.gouv.fr";
my $baseURL = "https://www.sia.aviation-civile.gouv.fr/dvd/__EAIP__/Atlas-VAC";
my $jsURL = "$baseURL/Javascript/AeroArraysVac.js";  # le code javascript qui contient la liste des terrains

my $infos = {};    # va contenir les infos necessaires a la construction de l'url de chaque doc pdf

{
  #my $eAIP = "eAIP_24_MAR_2022";
  my $eAIP = $ARGV[0];
  if ($eAIP eq "")
  {
	print "Il faut passer en argument de ce programme la date eAIP, de la forme \"eAIP_24_MAR_2022\"";
	exit();
  }
  
  print "   eAIP = $eAIP\n";
  die "eAIP ne semble pas conforme" if ($eAIP !~ /^eAIP_\d\d_..._20\d\d$/);

  $baseURL =~ s/__EAIP__/$eAIP/;
  $jsURL =~ s/__EAIP__/$eAIP/;
  
  print "\n## recuperation des codes OACI des terrains repertories ##\n";
  print "   $jsURL\n";

  my ($code, $page, $cookies) = &sendHttpRequest($jsURL, SSL_NO_VERIFY => 1);
  unless ($code =~ /^2\d\d/)
  {
	print "code retour http $code lors du chargement de $jsURL\n";
	print "Arret du traitement\n";
	exit 1;
  }

  die "Impossible de charger la page $jsURL" unless (defined($page));
  &writeBinFile("page.html", $page);
  # my $page; { local(*INPUT, $/); open (INPUT, "page.html") || die "can't open page.html"; $page = <INPUT>; close INPUT };  # debug, pour lire un fichier html local

  my $ads = &getOACIinfos($jsURL);
#  print Dumper($ads); exit;
  
  mkdir $dirDownload;

  print "\n## recuperation des cartes VAC ##\n";
  
  foreach my $ad (sort keys %$ads)
  {
    #next if ($ad le "LFPB");    # permet de reprendre l'operation sans recommencer au debut
	#next if ($ad eq "LFPC");    # permet de ne pas traiter une carte specifique
    my $refAD = $$ads{$ad};

	# https://www.sia.aviation-civile.gouv.fr/dvd/eAIP_19_JUL_2018/Atlas-VAC/PDF_AIPparSSection/VAC/AD/AD-2.LFEZ.pdf
	my $urlPDF = "$baseURL/PDF_AIPparSSection/VAC/AD/AD-2$$infos{vaerosection}.$ad.pdf";
	#print "$urlPDF\n"; exit;
	print "$ad.pdf\n";
	my ($code, $pdf, $cookies) = &sendHttpRequest($urlPDF, SSL_NO_VERIFY => 1, DIE => 0);
	unless ($code =~ /^2/)     # Erreur ; on retente une nouvelle fois
	{
	  print "Erreurt http $code lors de l'acces a $urlPDF\n";
	  print "On retente dans 10 secondes\n";
	  sleep 10;
	  ($code, $pdf, $cookies) = &sendHttpRequest($urlPDF, SSL_NO_VERIFY => 1);
	}
    die "Impossible de charger le fichier $urlPDF. Code = $code" unless (defined($pdf));
	&writeBinFile("$dirDownload/$ad.pdf", $pdf);
	sleep 1;
  }
}

#    ------------ recuperation ddu code OACI et des noms de terrains a partir d'un script JS --------------------
# ------------------------------------------------------------------------------------------------------------------
sub getOACIinfos
{
  my $url = shift;
  
  my $ads = {};
  
  print "\n## recuperation des codes OACI des terrains repertories ##\n";
  print "   $jsURL\n";

  my ($code, $page, $cookies) = &sendHttpRequest($url, SSL_NO_VERIFY => 1);
  die "Impossible de charger la page $url" unless (defined($page));
  
  die 'pas trouve la variable javascript vaerosoussection (les codes des terrains) dans la page chargee. Voir "page.html"'
    unless ($page =~ /var vaerosoussection =new Array\((.*?)\)/);
  my $allCodes = $1;   # contient une chaine comme : "LFOI","LFBA","LFDA",...
  $allCodes =~ s/"//sg;    # retrait des guillemets
  my @codes = split(",", $allCodes);

  die 'pas trouve la variable javascript vaeroportlong (les noms de terrains) dans la page chargee. Voir "page.html"'
    unless ($page =~ /var vaeroportlong =new Array\((.*?)\)/);
  my $allNames = $1;   # contient une chaine comme : "ABBEVILLE","AGEN LA GARENNE","AIRE SUR L'ADOUR",...
  $allNames =~ s/"//sg;    # retrait des guillemets
  my @names = split(",", $allNames);
  
  for (my $ind = 0 ; $ind < scalar(@codes) ; $ind++)
  {
    my $code = $codes[$ind];
	$$ads{$code}{code} = $code;
	$$ads{$code}{name} = $names[$ind];
  }
  
  return $ads
}

