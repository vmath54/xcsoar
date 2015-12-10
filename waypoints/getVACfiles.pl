#!/usr/bin/perl
#
# recuperation des cartes VAC de france, depuis le site SIA
#
# exemple d'url finale, pour une carte :
# https://www.sia.aviation-civile.gouv.fr/aip/enligne/Atlas-VAC/PDF_AIPparSSection/VAC/AD/2/1512_AD-2.LFOI.pdf

use LWP::Simple;
use Data::Dumper;

use strict;

my $dirDownload = "vac";    # le répertoire qui va contenir les documents pdf charges
my $baseURL = "https://www.sia.aviation-civile.gouv.fr/aip/enligne/Atlas-VAC";
my $pageURL = "$baseURL/FR/VACProduitPartie.htm";  # url de la page de téléchargement des cartes VAC

{
  my $page = get($pageURL);
  die "Impossible de charger la page $pageURL" unless (defined($page));

  my $infos = &decodePage($page);
  my $ads = $$infos{ad};
  
  mkdir $dirDownload;
  
  foreach my $ad (sort keys %$ads)
  {
    my $refAD = $$ads{$ad};
	my $urlPDF = "$baseURL/PDF_AIPparSSection/$$infos{vaeroproduit}/$$infos{vaeropartie}/$$infos{vaerosection}/$$infos{prefixe}_$$infos{vaeropartie}-$$infos{vaerosection}.$ad.pdf";
	#print "$urlPDF\n";
	print "$ad.pdf\n";
	my $status = getstore($urlPDF, "$dirDownload/$ad.pdf");   #download de la fiche pdf
    unless ($status =~ /^2\d\d/)
    {
	  print "code retour http $status lors du chargement du doc $urlPDF\n";
	  print "Arret du traitement\n";
	  exit 1;
	}
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
