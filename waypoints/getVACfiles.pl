#!/usr/bin/perl
#
# recuperation des cartes VAC de france, depuis le site SIA
#
# sur la page d'accueil ( https://www.sia.aviation-civile.gouv.fr ), on récupere un lien comme celui-ci, qui correspond au menu "eAIP FRANCE" :
# <a href='https://www.sia.aviation-civile.gouv.fr/documents/htmlshow?f=dvd/eAIP_30_JAN_2020/FRANCE/home.html'  class=''>eAIP FRANCE</a>
# On récupère la date eAIP ; ici, eAIP_30_JAN_2020
#
# Ceci permet de construire l'URL de la page qui répertorie les cartes VAC ; dans l'exemple :
# https://www.sia.aviation-civile.gouv.fr/dvd/eAIP_30_JAN_2020/Atlas-VAC/FR/VACProduitPartie.htm
# ET on peut récupérer le script JS qui répertorie toutes les cartes VAC ; dans notre exemple :
# https://www.sia.aviation-civile.gouv.fr/dvd/eAIP_30_JAN_2020/Atlas-VAC/Javascript/AeroArraysVac.js
#
# grace a ces infos, on reconstruit l'URL d'acces aux PDF des cartes VAC ; par exemple :
# https://www.sia.aviation-civile.gouv.fr/dvd/eAIP_30_JAN_2020/Atlas-VAC/PDF_AIPparSSection/VAC/AD/AD-2.LFEZ.pdf
#

use VAC;
#use LWP::Simple;
use Data::Dumper;

use strict;


my $dirDownload = "vac";    # le répertoire qui va contenir les documents pdf charges
my $siteURL = "https://www.sia.aviation-civile.gouv.fr";
my $baseURL = "https://www.sia.aviation-civile.gouv.fr/dvd/__EAIP__/Atlas-VAC";
my $jsURL = "$baseURL/Javascript/AeroArraysVac.js";  # le code javascript qui contient la liste des terrains

my $infos = {};    # va contenir les infos necessaires a la construction de l'url de chaque doc pdf

{
  my $eAIP = &getEAIP($siteURL);    # recuperation de la date eAIP, de la forme "eAIP_19_JUL_2018"
  
  print "   eAIP = $eAIP\n";
  die "eAIP ne semble pas conforme" if (length($eAIP) > 20);

  $baseURL =~ s/__EAIP__/$eAIP/;
  $jsURL =~ s/__EAIP__/$eAIP/;
  
  print "\n## recuperation des codes OACI des terrains repertories ##\n";
  print "   $jsURL\n";

  my ($code, $page, $cookies) = &sendHttpRequest($jsURL, SSL_NO_VERIFY => 1);
  die "Impossible de charger la page $jsURL" unless (defined($page));
  &writeBinFile("page.html", $page);
  #my $page; { local(*INPUT, $/); open (INPUT, "page.html") || die "can't open page.html"; $page = <INPUT>; close INPUT };  # debug, pour lire un fichier html local

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
    die "Impossible de charger le fichier $urlPDF" unless (defined($pdf));
	&writeBinFile("$dirDownload/$ad.pdf", $pdf);
	sleep 1;
  }
}

#    ------------ recuperation de la date eAIP a partir de la page principale --------------------
# recherche dans <a href='https://www.sia.aviation-civile.gouv.fr/documents/htmlshow?f=dvd/eAIP_30_JAN_2020/FRANCE/home.html'  class=''>eAIP FRANCE</a>
# retourne une chaine du genre "eAIP_30_JAN_2020"
# ------------------------------------------------------------------------------------------------------------------
sub getEAIP
{
  my $page = shift;
  
  print "## recuperation et traitement de la page d'accueil ##\n";
  print "   $page\n";
  my ($code, $page, $cookies) = &sendHttpRequest($siteURL, SSL_NO_VERIFY => 1);
  die "Impossible de charger la page $siteURL" unless (defined($page));

  my $eAIP;
  if ( $page =~ /gouv.fr\/documents\/htmlshow\?f=dvd\/(eAIP.*?)\/FRANCE\/home\.html/)    # "SUP AIP" est la rubrique juste avant  "Atlas VAC FRANCE"
  {
    $eAIP = $1
  }
  else
  {
    die "Pas trouvé eAIP dans la page d'accueil";
  }
  return $eAIP;
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

