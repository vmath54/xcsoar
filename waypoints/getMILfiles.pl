#!/usr/bin/perl
#
# recuperation de cartes VAC, depuis le site http://www.dircam.air.defense.gouv.fr
# permet de completer les cartes VAC recuperees depuis le site SIA
#
# pour se limiter aux cartes VAC, on va a http://www.dircam.dsae.defense.gouv.fr/index.php/infos-aeronautiques/a-vue-france
#
# exemple d'url finale, pour une carte : http://www.dircam.dsae.defense.gouv.fr/images/stories/Doc/AVUE/avue_nancy_ochey_lfso.pdf
#
# on ne recupere pas les cartes qu'on a par ailleurs depuis le site SIA ($dirSIA)
#
# A noter qu'il faut présenter au site www.dircam.air.defense.gouv.fr un User-Agent "propre", et gérer les cookies, sous peine de se faire black-lister plusieurs jours
#

use VAC;
use Text::Unaccent::PurePerl qw(unac_string);
use Data::Dumper;

use strict;

my $dirDownload = "mil";    # le répertoire qui va contenir les documents pdf charges
my $dirSIA = "./vac";            # les fichiers pdf recuperes du site SIA

my $siteURL = "http://www.dircam.dsae.defense.gouv.fr";

my $pageURL = "$siteURL/index.php/infos-aeronautiques/a-vue-france";
my $baseURL = "$siteURL/images/stories/Doc/AVUE";  # url de la page de téléchargement des cartes VAC

{
  my $ADsia = &getListSIA($dirSIA);   # les AD qu'on a deja charges depuis le site SIA
  
  my ($code, $page, $cookies) = &sendHttpRequest($pageURL);
  die "Impossible de charger la page $pageURL" unless (defined($page));
  #&writeBinFile("page.html", $page);
  #my ($page, $cookies); { local(*INPUT, $/); open (INPUT, "page.html") || die "can't open page.html"; $page = <INPUT>; close INPUT };  # debug, pour lire un fichier html local
  
  my $ADs = &decodePage($page);
  
  mkdir $dirDownload;
  
  foreach my $ad (sort keys %$ADs)
  {
    #next if ($ad ne "LFBA");
	next if (defined($$ADsia{$ad}));   # on ne traite pas les fichiers deja charges depuis le site SIA
	
    my $refAD = $$ADs{$ad};
	$ad = lc($ad);
	my $name = $$refAD{name};
	$name =~ s/ /_/sg;
	$name = lc($name);
	my $urlPDF = $baseURL . "/avue_" . $name . "_" . $ad . ".pdf";
	print "$ad.pdf\n";
	#print "$urlPDF\n"; next;

    my ($code, $pdf, $cookies) = &sendHttpRequest($urlPDF, COOKIES => $cookies);
	&writeBinFile("$dirDownload/$ad.pdf", $pdf);
	
	sleep 1;
  }
}

# on memorise les terrains deja recuperes depuis le site SIA
sub getListSIA
{
  my $dir = shift;
  
  my %ADs = ();
  
  my @fics = glob("$dir/*.pdf");
  return () if (scalar(@fics) == 0);
  
  foreach my $ad (@fics)
  {
    my ($rep,$fic) = $ad =~ /(.+[\/\\])([^\/\\]+)$/; 
    $fic =~ s/\.pdf$//;
	$ADs{$fic} = 1;
  }
  return \%ADs;
}

#    ------------ decode la page html qui permet de choisir un terrain --------------------
# les infos necessaires se trouvent dans du code javascript :
#
# voici un extrait de la page html (ou plutot, du code javascript) qui permet d'obtenir la liste des cartes de vol a vue disponibles :
#
# <script language='JavaScript' type='text/JavaScript'>
#  var terrain_avue =new Array(
#  "AGEN LA GARENNE","AIRE SUR L'ADOUR","AIX LES MILLES",...,"NANCY OCHEY",...);
#  var indicateur_avue =new Array(
#  "LFBA","LFDA","LFMA","LFKJ","LFAQ",...,"LFSO",...);

sub decodePage
{
  my $page = shift;
  
  my %ADs = ();     # va contenir le code et le nom des terrains disponible
  
  unless ($page =~ /var indicateur_avue =new Array\((.*?)\);/s)
  {
    die "pas trouve le contenu de la variable javascript 'indicateur_avue'";
  }
  my $allCodes = $1;   # contient une chaine comme : "LFOI","LFBA","LFDA",...
  $allCodes =~ s/\n//sg; $allCodes =~ s/^\s*//s; $allCodes =~ s/"//sg;   # retrait des retour-chariots, guillemets, espaces
  my @codes = split(",", $allCodes);
  
  #unless ($page =~ /var terrain_avue =new Array\(\n(.*?)\);/)
  unless ($page =~ /var terrain_avue =new Array\((.*?)\);/s)
  {
    die "pas trouve le contenu de la variable javascript 'terrain_avue'";
  }

  my $allNames = $1;
  $allNames =~s/\n//sg; $allNames =~s/^\s*//s; $allNames =~ s/"//sg;
  my @names = split(",", $allNames);  
  
  for (my $ind = 0 ; $ind < scalar(@codes) ; $ind++)
  {
    my $code = $codes[$ind];
	$code =~ s/^ //;
		
	$ADs{$code}{code} = $code;
	my $name = $names[$ind];
	$name =~ s/^ //;
	$name = unac_string("UTF-8", $name);
	$name =~ s/\\u00C8/e/; $name =~ s/\\u00C9/e/; $name =~ s/\\u00CA/e/; $name =~ s/\\u00Ca/e/; $name =~ s/\\u00C2/a/;  $name =~ s/\\u00C7/c/;   # crade, pas trouve mieux
	$ADs{$code}{name} = $name;
  }
  return \%ADs;
}
