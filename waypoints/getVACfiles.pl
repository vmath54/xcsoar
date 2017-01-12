#!/usr/bin/perl
#
# recuperation des cartes VAC de france, depuis le site SIA
#
# sur la page d'accueil, on récupere un lien comme celui-ci, qui correspond au menu "Atlas VAC FRANCE" :
# <a href="https://www.sia.aviation-civile.gouv.fr/documents/htmlshow?f=dvd/eAIP_05_JAN_2017/Atlas-VAC/home.htm" title="">Atlas VAC FRANCE</a>
#
# On récupère la date eAIP ; ici, eAIP_05_JAN_2017
# Ceci permet de construire l'URL de la page qui répertorie toutes les cartes VAC ; dans notre exemple :
# "https://www.sia.aviation-civile.gouv.fr/dvd/eAIP_05_JAN_2017/Atlas-VAC/FR/VACProduitPartie.htm";
#
# grace a cette page, on reconstruit l'URL d'acces aux PDF des cartes VAC ; par exemple :
# https://www.sia.aviation-civile.gouv.fr/dvd/eAIP_05_JAN_2017/Atlas-VAC/PDF_AIPparSSection/VAC/AD/2/1702_AD-2.LFAB.pdf
#
# A noter qu'au 11/01/2017, le certification du site sia n'est pas valide ; d'ou l'option "SSL_NOP_VERIFY" lors des diffents acces


use VAC;
#use LWP::Simple;
use Data::Dumper;

use strict;


my $dirDownload = "vac";    # le répertoire qui va contenir les documents pdf charges
my $siteURL = "https://www.sia.aviation-civile.gouv.fr";
my $baseURL = "https://www.sia.aviation-civile.gouv.fr/dvd/__EAIP__/Atlas-VAC";
my $pageURL = "$baseURL/FR/VACProduitPartie.htm";  # url de la page de téléchargement des cartes VAC


{
  #    --- chargement page d'accueil, pour recuperer eAIP -----
  print "## recuperation et traitement de la page d'accueil ##\n";
  print "   $siteURL\n";
  my ($page, $cookies) = &sendHttpRequest($siteURL, SSL_NO_VERIFY => 1);
  die "Impossible de charger la page $siteURL" unless (defined($page));
  
  my $eAIP = $1 if ( $page =~ /SUP AIP.*\?f=dvd\/(eAIP.*?)\/Atlas\-VAC\/home\.htm\"/);
  die "Pas trouvé eAIP dans la page d'accueil" if ($eAIP eq "")  ;
  print "   eAIP = $eAIP\n";
  die "eAIP ne semble pas conforme" if (length($eAIP) > 20);

  $baseURL =~ s/__EAIP__/$eAIP/;
  $pageURL =~ s/__EAIP__/$eAIP/;

  print "\n## recuperation et traitement de la page des cartes VAC ##\n";
  print "   $baseURL\n";
  my ($page, $cookies) = &sendHttpRequest($pageURL, SSL_NO_VERIFY => 1);
  die "Impossible de charger la page $pageURL" unless (defined($page));
  &writeBinFile("page.html", $page);
  #my $page; { local(*INPUT, $/); open (INPUT, "page.html") || die "can't open page.html"; $page = <INPUT>; close INPUT };  # debug, pour lire un fichier html local

  my $infos = &decodePage($page);
  my $ads = $$infos{ad};
  
  mkdir $dirDownload;

  print "\n## recuperation des cartes VAC ##\n";
  
  foreach my $ad (sort keys %$ads)
  {
    #next if ($ad ne "LFEG");
    my $refAD = $$ads{$ad};
	my $urlPDF = "$baseURL/PDF_AIPparSSection/$$infos{vaeroproduit}/$$infos{vaeropartie}/$$infos{vaerosection}/$$infos{prefixe}_$$infos{vaeropartie}-$$infos{vaerosection}.$ad.pdf";
	#print "$urlPDF\n";
	print "$ad.pdf\n";
	my ($pdf, $cookies) = &sendHttpRequest($urlPDF, SSL_NO_VERIFY => 1);
    die "Impossible de charger le fichier $urlPDF" unless (defined($pdf));
	&writeBinFile("$dirDownload/$ad.pdf", $pdf);
	sleep 1;
  }
}


#    ------------ decode la page html qui permet de choisir un terrain --------------------
# les infos necessaires se trouvent dans du code javascript, et un bout dans du html :
#
# voici un extrait de la page html (ou plutot, du code javascript) 
#  <script language='JavaScript' type='text/JavaScript'>
#  <!--
#  var vaeroportlong =new Array("ABBEVILLE","AGEN LA GARENNE","AIRE SUR L'ADOUR",...
#  var vaeroproduit ="VAC";
#  var vaeropartie ="AD";
#  var vaerosection ="2";
#  var vaerosoussection =new Array("LFOI","LFBA","LFDA",...
#  //-->
#
# et le bout de html qui contient le prefixe "1512|", 
#  <input name='Bouton' onClick='clickok("tout","1512_","..|");' type='button'  value='OK' style ="margin-right:21%"/>
sub decodePage
{
  my $page = shift;
  
  my %infos = ();     # va contenir les infos utiles de la page. En fait, les elements necessaires a la construction de l'url de chaque doc pdf
  
  # on ne teste pas les variables javascripts vaeroproduit, vaeropartie, vaerosection ; on suppose que ca ne change pas.
  $infos{vaeroproduit} = "VAC";
  $infos{vaeropartie}  = "AD";
  $infos{vaerosection} = "2";
  
  die 'pas trouve la variable javascript vaerosoussection (les codes des terrains) dans la page chargee'
    unless ($page =~ /var vaerosoussection =new Array\((.*?)\)/);
  my $allCodes = $1;   # contient une chaine comme : "LFOI","LFBA","LFDA",...
  $allCodes =~ s/"//sg;    # retrait des guillemets
  my @codes = split(",", $allCodes);

  die 'pas trouve la variable javascript vaeroportlong (les noms de terrains) dans la page chargee'
    unless ($page =~ /var vaeroportlong =new Array\((.*?)\)/);
  my $allNames = $1;   # contient une chaine comme : "ABBEVILLE","AGEN LA GARENNE","AIRE SUR L'ADOUR",...
  $allNames =~ s/"//sg;    # retrait des guillemets
  my @names = split(",", $allNames);

  die 'pas trouve le prefixe (du genre "1512_") dans la page chargee'
    unless ($page =~ /onClick='clickok\(\"tout\",\"(.*?)_\",\"..\|\"\);'/);
  $infos{prefixe} = $1;
  
  for (my $ind = 0 ; $ind < scalar(@codes) ; $ind++)
  {
    my $code = $codes[$ind];
	$infos{ad}{$code}{code} = $code;
	$infos{ad}{$code}{name} = $names[$ind];
  }
  
  return \%infos;
}

